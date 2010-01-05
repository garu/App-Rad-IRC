#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'App::Rad::IRC' ) || print "Bail out!
";
}

diag( "Testing App::Rad::IRC $App::Rad::IRC::VERSION, Perl $], $^X" );
