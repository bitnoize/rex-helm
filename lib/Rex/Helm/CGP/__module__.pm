package Rex::Helm::CGP;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

use Rex::Commands::SCM;

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'cgp', { };
  return unless $config->{active} or $force;

  my $cgp = {
    active      => $config->{active}  // FALSE,
    distrib     => $config->{distrib} || "https://github.com/pommi/CGP.git",
    workdir     => $config->{workdir} || "/var/www/cgp",
  };

  inspect $cgp if Rex::Helm::DEBUG;

  set 'cgp' => $cgp;
};

task 'setup' => sub {
  return unless my $cgp = config;

  pkg [ qw/rrdtool php-fpm/ ], ensure => 'present';

  set repository => 'cgp', url => $cgp->{distrib};

  file $cgp->{workdir}, ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  checkout 'cgp', path => $cgp->{workdir};

  file "$cgp->{workdir}/conf/config.php", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/cgp.config.php" );
};

task 'clean' => sub {
  return unless my $cgp = config;

};

task 'remove' => sub {
  my $cgp = config -force;

  #pkg [ qw/rrdtool php-fpm/ ], ensure => 'present';

  file $cgp->{workdir}, ensure => 'absent';
};

task 'status' => sub {
  my $cgp = config -force;

};

1;
