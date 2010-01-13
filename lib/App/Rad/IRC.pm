package App::Rad::IRC;
use parent 'App::Rad';

use strict;
use warnings;

use POE 'Component::IRC::State';
use namespace::autoclean;

our $VERSION = '0.01';

###################################
## rewrite some of Rad's methods ##
###################################

sub new {
    my ($class, %opts) = (@_);
    my $self = bless {
        Nick     => $opts{Nick} || 'justabot',
        Username => $opts{Username} || 'radbot',
        Ircname  => $opts{Ircname}  || 'App::Rad powered IRC bot',
        Server   => $opts{Server}   || 'irc.freenode.org',
        Port     => $opts{Port}     || 6667,
        Channels => $opts{Channels} || [ '#bot' ],
        ALIASNAME => 'foo' . int(rand(10000)),
        Timeout   => 500,
    }, $class;

    $self->{'_functions'} = {
        setup        => \&setup,
        default      => \&default,
        pre_process  => \&pre_process,
        post_process => \&post_process,
        teardown     => \&teardown,
        invalid      => \&invalid,
    };

	$self->{'_stash'}   = {};
	$self->{'_config'}  = {};

    $self->{debug} = 1;

    $self->register('help', \&help);

    return $self;
}

sub run {
    my $self = new(@_);

    $self->_register_functions();

	$self->{'_functions'}->{'setup'}->($self);

    # create the callbacks to the object states
    POE::Session->create(
        object_states => [
            $self => {
                _start => "start_state",
                _stop  => "stop_state",

                irc_001          => "irc_001_state",
#                _default         => 'irc_default',
                irc_msg          => "irc_privmsg_state",
                irc_public       => "irc_public_state",
#                irc_ctcp_action  => "irc_emoted_state",
                irc_ping         => "irc_ping_state",
                reconnect        => "reconnect",

                irc_disconnected => "irc_disconnected_state",
                irc_error        => "irc_error_state",

                irc_join         => "irc_chanjoin_state",
#                irc_part         => "irc_chanpart_state",
#                irc_kick         => "irc_kicked_state",
#                irc_nick         => "irc_nick_state",
#                irc_mode         => "irc_mode_state",
#                irc_quit         => "irc_quit_state",
#
#                fork_close       => "fork_close_state",
#                fork_error       => "fork_error_state",
#
#                irc_353          => "names_state",
#                irc_366          => "names_done_state",
#
#                irc_332          => "topic_raw_state",
#                irc_topic        => "topic_state",
#
#                irc_391          => "_time_state",
#                _get_time        => "_get_time_state",
#                
                tick => "tick_state",
            }
        ]
    );

    # and say that we want to recive said messages
    $poe_kernel->post( $self->{Ircname} => register => 'all' );

    $poe_kernel->run();
}

sub parse_input {
    my ($self, $input) = (@_);

    $input =~ s/\s+$//; # rtrim

    # see if we were addressed or not
    my $nick = $self->{Nick};
    if ( $input =~ s/^\s*$nick[:,]?\s*// ) {
        $self->{addressed} = 1;
    }
    else {
        $self->{addressed} = 0;
    }

    $self->debug(">>>>parsing '$input'!!!");
    my ($cmd, $body) = ('', '');
    if ($input =~ m/\s*(\w+)\s*(.*)/) {
        ($cmd, $body) = ($1, $2);
        $self->debug(">>> cmd: $cmd, bd: $body\n");
    }
    $self->{cmd} = $cmd;
    $self->stash->{body} = $body;

    return;
}

sub help { 
    my $c = shift;
#    if ( $c->is_command( $c->stash->{body} ) ) {
#        return App::Rad::Help::get_help_attr_for($c, $c->stash->{body});
#    }
    return 'accepted commands: ' . join ', ', $c->commands 
}

sub teardown {}
sub default {}
sub invalid { $_[0]->{_functions}->{default}->(@_) }
sub pre_process {}
sub post_process {
    my $self = shift;
    if ( $self->output ) {
        $self->reply($self->output);
    }
}

sub setup {
    my $self = shift;
    $self->register_commands({ -ignore_prefix => '_' });
}


######################
## POE's IRC states ##
######################

sub start_state {
    my ( $self, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];

    $self->{kernel} = $kernel;
    $self->{session} = $session;

    # Make an alias for our session, to keep it from getting GC'ed.
    $kernel->alias_set($self->{ALIASNAME});

    $kernel->delay('reconnect', 1 );

    $kernel->delay('tick', 5);
}

sub reconnect {
    my ( $self, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];

    $self->debug("Trying to connect to server ".$self->{Server});

    $kernel->call( $self->{Ircname}, 'disconnect' );
    $kernel->call( $self->{Ircname}, 'shutdown' );
    POE::Component::IRC->spawn( alias => $self->{Ircname} );
    $kernel->post( $self->{Ircname}, 'register', 'all' );

    $kernel->post($self->{Ircname}, 'connect',
        {
            Debug    => 0,
            Nick     => $self->{Nick},
            Server   => $self->{Server},
            Port     => $self->{Port},
            Ircname  => $self->{Ircname},
#            Password => $self->password,
#            UseSSL => $self->ssl,
#            Flood    => $self->flood,
#            $self->charset_encode(
#              Nick     => $self->nick,
#              Username => $self->username,
#              Ircname  => $self->name,
        }
    );
    $kernel->delay( 'reconnect', $self->{Timeout} );
#    $kernel->delay('_get_time', 60);
}

sub stop_state {
    my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];

    $kernel->post( $self->{Ircname}, 'quit', 'hasta' );
    $kernel->alias_remove($self->{ALIASNAME});
}

sub irc_default {
    my ($event, $args) = @_[ARG0 .. $#_];
    print "unhandled $event\n";
    my $arg_number = 0;
    foreach (@$args) {
        print "  ARG$arg_number = ";
        if (ref($_) eq 'ARRAY') {
            print "$_ = [", join(", ", @$_), "]\n";
        }
        else {
            print "'$_'\n";
        }
        $arg_number++;
    }
    return 0;    # Don't handle signals.
}

sub irc_001_state {
    my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];

    # ignore all messages from ourselves
    $kernel->post( $self->{Ircname}, 'ignore', $self->{Nick} );

    # connect to the channel
    foreach my $channel ( @{ $self->{Channels} } ) {
        $self->debug("Trying to connect to '$channel'\n");
        $kernel->post( $self->{Ircname}, 'join', $channel );
    }

    $self->schedule_tick(5);

#    $self->connected();
}

sub irc_chanjoin_state {
    my ($self, $channel, $nick) = @_[OBJECT, ARG1, ARG0];
    $_[KERNEL]->delay( 'reconnect', $self->{Timeout} );

    ($nick) = (split /!/, $nick);
    if ($self->{Nick} eq $nick) {
        $self->{in_channel} = 1; #TODO: remove workaround
    }
}

sub irc_disconnected_state {
    my ( $self, $kernel, $server ) = @_[ OBJECT, KERNEL, ARG0 ];
    $self->debug("Lost connection to server $server.\n");
    $kernel->delay('reconnect', 30);
}

sub irc_error_state {
    my ( $self, $err, $kernel ) = @_[ OBJECT, ARG0, KERNEL ];
    $self->debug("Server error occurred! $err\n");
    $kernel->delay('reconnect', 30);
}

sub irc_ping_state {
    $_[KERNEL]->delay( 'reconnect', $_[OBJECT]->{Timeout} );
}


sub irc_public_state {
    my ( $self, $kernel) = @_[ OBJECT, KERNEL ];
    $kernel->delay( 'reconnect', $self->{Timeout} );

    my ($nick, $channel, $body) = @_[ ARG0, ARG1, ARG2 ];
    ($self->stash->{from}) = split /!/, $nick;
    $self->stash->{from_full} = $nick;

    # the irc protocol allows messages sent to
    # multiple targets, but we don't care.
    $channel = $channel->[0];

    # unset channel if it's a private message
    $channel = undef if lc($channel) eq lc($self->{Nick});
    $self->stash->{channel} = $channel;
  
    $self->parse_input($body);
    $self->execute();
}

sub irc_privmsg_state {
    goto &irc_public_state;
}

sub tick_state {
    my ( $self, $kernel, $heap ) = @_[ OBJECT, KERNEL, HEAP ];
#    my $delay = $self->tick();
    my $delay = main::_on_timer($self);
    $self->schedule_tick($delay) if $delay;
}

sub schedule_tick {
  my $self = shift;
  my $time = shift || 5;
  $self->{kernel}->delay( tick => $time );
}

sub tick { print STDERR "moo\n"; return 5 }

#####################
## our new methods ##
#####################

sub addressed { return $_[0]->{addressed} }

sub reply {
    my ($self, $message) = (@_);
    return unless $message;
    my $target = $self->stash->{channel} || $self->stash->{from};

    $poe_kernel->post( $self->{Ircname}, 'privmsg',
                       $target,
                       $message
                     );
}

sub say {
    my ($self, $target, $message) = (@_);
    return unless $target and $message; 

    $poe_kernel->post( $self->{Ircname}, 'privmsg', 
                       $target, 
                       $message
                     );
}


# register subs as commands, except underlined ones and
# ones starting with 'irc_'

# register subs starting with irc_ as states


42;
__END__

=head1 SYNOPSIS

  use App::Rad 'IRC';
  App::Rad->run;

  # connect to the IRC server during setup
  # setup isn't even required if you have
  # these values in your app's config file!
  sub setup {
      my $c = shift;
      $c->irc_connect(
              # all optional!
              Nick     => 'randombot',
              Username => 'radbot',
              Ircname  => 'App::Rad powered IRC bot',
              Server   => 'irc.freenode.org',
              Port     => 6667,
              Channels => [ qw( #chan1 #chan2 ) ],
      );
     
      # register any commands you want, just like
      # a regular App::Rad application
      $c->register_commands();
  }

  # regular Rad command, but called via IRC
  # instead of via standard CLI!
  sub foo {
      my $c = shift;
     
      # this will be sent as a reply
      return 'baaaaarrrrr';
  }

  # and, of course, generic public messages go here
  sub default {
  }

=head1 DESCRIPTION


