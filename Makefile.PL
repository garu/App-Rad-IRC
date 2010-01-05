use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'App::Rad::IRC',
    AUTHOR              => q{Breno G. de Oliveira <garu@cpan.org>},
    VERSION_FROM        => 'lib/App/Rad/IRC.pm',
    ABSTRACT_FROM       => 'lib/App/Rad/IRC.pm',
    ($ExtUtils::MakeMaker::VERSION >= 6.3002
      ? ('LICENSE'=> 'perl')
      : ()),
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'App-Rad-IRC-*' },
);
