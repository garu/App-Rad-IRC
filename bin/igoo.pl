use App::Rad::IRC;
###################################
##                               ##
##  this is Igoo, a bot we run   ##
##  in #app-rad in irc.perl.org  ##
##                               ##
###################################

use URI;
use URI::Escape;
use Web::Scraper::LibXML;
use namespace::autoclean;

App::Rad::IRC->run(
    Nick     => 'Igoo',
    Server   => 'irc.perl.org',
    Port     => '6667',
    Channels => [ '#app-rad' ],
);

sub calc {
    my $c = shift;
    my $body = $c->stash->{body};

    if ( $body =~ m{^\s*\d+\s*(?:[\+\-\*\/]\s*\d+\s*)*$} ) {
        my $ret = eval $body;
        return $ret unless $@;
    }
    return "sorry, can't calculate that...";
}


sub default {
    my $c = shift;
    my $ret;
    my $body = $c->stash->{body};

    # questions (only when directly addressed to)
    if ($c->addressed and $body =~ m{\?\s*$}) {
        $ret = _query($body);
    }
}

sub _query {
    my $query = uri_escape(shift, '\0-\377');
    my $ask = scraper { process 'id("r1_a")', text => 'TEXT'; };

    my $res = $ask->scrape( URI->new(
           "http://www.ask.com/web?q=$query&search=&qsrc=0&o=10181&l=dir"
    ));

    return $res ? $res->{text} 
           : 'I have no idea... did you try searching the web?'
           ;
}

