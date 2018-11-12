#!/usr/bin/env perl

use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
  NAME         => 'Rex::Malta',
  VERSION_FROM => "lib/Rex/Malta.pm",
  ABSTRACT     => "My own high-level DevOps implementation on top of the Rex framework",
  LICENSE      => "artistic_2",
  AUTHOR       => "Dmitry Krutikov <d.krutikov\@gmail.com>",
  PREREQ_PM    => {
    'Rex'   => '1.4.0',
  },
  test => { TESTS => 't/*.t' }
);
