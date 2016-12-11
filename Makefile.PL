use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  VERSION   => '0.01',
  PREREQ_PM => {'Mojolicious' => '7.11',
		'Mojo::Pg' => '2.30',
		'Mojolicious::Plugin::Authentication ' => '1.29'
		},
  test      => {TESTS => 't/*.t'}
);
