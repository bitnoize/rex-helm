#!/usr/bin/env perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Rex::Helm',
  VERSION_FROM => "lib/Rex/Helm.pm",
  ABSTRACT     => "My own high-level DevOps implementation on top of the Rex framework",
  LICENSE      => "artistic_2",
  AUTHOR       => "Dmitry Krutikov <hamster.fundation\@gmail.com>",
  PREREQ_PM    => {
    'Rex'   => '1.4.0',
  },
  test => { TESTS => 't/*.t' }
);
