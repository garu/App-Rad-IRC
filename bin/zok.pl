use App::Rad::IRC;
###################################
##                               ##
##  this is Zok, a bot we run    ##
##  in #app-rad in irc.perl.org  ##
##  to notify us of feeds        ##
###################################

use strict;
use warnings;

# TODO: proper authorization

use namespace::autoclean;

use XML::Atom::Feed;
#use LWP::Curl;
use LWP::Simple 'get';
use URI::Escape::XS 'uri_escape';
use WWW::Shorten 'Miudin';

use ORLite {
    package => 'Model',
    file => 'data/feeds.db',
    create => sub {
        my $dbh = shift;
        $dbh->do( 'CREATE TABLE feeds ( 
                    name TEXT NOT NULL PRIMARY KEY, 
                    uri TEXT NOT NULL,
                    last TEXT NOT NULL
                   )' 
              );
        $dbh->do( 'CREATE TABLE nicks (
                    name TEXT NOT NULL PRIMARY KEY,
                    nick TEXT NOT NULL
                   )'
                );
    },
};


App::Rad::IRC->run(
    Nick     => 'Zok',
    Server   => 'irc.perl.org',
    Port     => '6667',
    Channels => [ '#app-rad' ],
);

#sub pre_process {
#    my $c = shift;
#    $c->stash->{from} = 'garu';
#    $c->stash->{body} = join ' ', @{ $c->argv };
#}


sub add 
:Help(add <label> <url> - add a new feed to watch) 
{
    my $c = shift;

    # make sure input is ok
    my ($name, $feed) = split /\s+/, $c->stash->{body};
    return 'sorry, I need a nametag and a feed uri'
        unless $name and $feed and (substr ($feed, 0, 7) eq 'http://');

    # make sure it's not already in
    my @rs = Model::Feeds->select('where name = ? or uri = ?', $name, $feed);
    if (@rs) {
        return 'Sorry, ' 
            . ($name eq $rs[0]->name ? 'name' : 'url')
            . ' is already in our records (' . $rs[0]->name . ')';
    }

#    $feed = uri_escape($feed);
    my $content = _get_latest_feed($feed)
        or return "hmm... $feed is either down or plain wrong. Try me again?";


    # add data to our database
    Model->begin;
    Model->do( 
        'insert into feeds (name, uri, last) values( ?, ?, ? )', 
        {}, $name, $feed, $content->title
    );
    Model->commit;

    return 'ok, ' . $c->stash->{from};
}


sub remove 
:Help(remove <label> - remove a feed) 
{
    my $c = shift;

    # make sure input is ok
    my $label = $c->stash->{body};
    return 'remove what? I can haz label?'
        unless $label and $label =~ /^\S+$/;

    # make sure we have the given label stored
    my @rs = Model::Feeds->select('where name = ?', $label);
    return "Sorry, no feed named '$label' found."
        unless @rs;

    # remove data from our database
    Model->begin;
    Model->do( 'delete from feeds where name = ?', {}, $label);
    Model->commit;

    return 'ok, ' . $c->stash->{from};
}


sub list 
:Help(list current feeds) 
{
    my @rs = Model::Feeds->select('order by name');
    return 'no feeds atm :(' unless @rs;
    return 'following: ' . join ', ', map { $_->name } @rs;
}


sub _get_latest_feed {
    my ($url, $last_entry) = (@_);
    my $content = get($url) or return;
    my $feed = XML::Atom::Feed->new(\$content) or return;

    my $entry = ($feed->entries)[0];
    if ( defined $last_entry ) {
        return if $entry->title eq $last_entry;
    }

    return $entry;
}

sub _on_timer {
    my $c = shift;
    return 600 unless $c->{in_channel};

    foreach my $feed ( Model::Feeds->select() ) {
        _update($c, $feed); #TODO: different POE session?
    }
    return 600;  # seconds until next call (600 -> 10 minutes)
}

sub _update {
    my ($c, $rs) = (@_);
    my $new_feed = _get_latest_feed($rs->uri, $rs->last);
    if ($new_feed) {
        Model->begin;
        Model->do('update feeds set last = ? where name = ?',
                {}, $new_feed->title, $rs->name
        );
        Model->commit;

        #TODO: say only in the proper channel
        $c->stash->{channel} = $c->{Channels}->[0];
        $c->say(_format($rs->name, $new_feed)) if $new_feed;
    }
}

sub _format {
    my ($label, $entry) = (@_);

    my @nicks = Model::Nicks->select( 'where name = ?', $entry->author->name );
    my $nick = (@nicks ? $nicks[0]->nick : $entry->author->name);

    return sprintf '[%s] %s (%s++) - %s', 
           $label, $entry->title, $nick, makeashorterlink($entry->link->href);
}
