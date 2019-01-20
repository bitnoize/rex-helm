package Rex::Helm::Rsync;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'rsync', { };
  return unless $config->{active} or $force;

  my $rsync = {
    active      => $config->{active}    // FALSE,
    address     => $config->{address}   || "0.0.0.0",
    port        => $config->{port}      || 873,
    storage     => $config->{storage}   || "/var/www/stuff",
  };

  $rsync->{address} = [ $rsync->{address} ]
    unless ref $rsync->{address} eq 'ARRAY';

  $rsync->{monit}{enabled}  //= FALSE;
  $rsync->{monit}{timeout}  ||= 10;

  inspect $rsync if Rex::Helm::DEBUG;

  set 'rsync' => $rsync;
};

task 'setup' => sub {
  return unless my $rsync = config;

  pkg [ qw/rsync/ ], ensure => 'present';

  file "/etc/default/rsync", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.rsync" );

  file "/etc/rsyncd.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/rsyncd.conf" );

  file $rsync->{storage}, ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  service 'rsync', ensure => 'started';
  service 'rsync' => 'restart';
};

task 'clean' => sub {
  return unless my $rsync = config;

};

task 'remove' => sub {
  my $rsync = config -force;

  pkg [ qw/rsync/ ], ensure => 'absent';

  file [ qw{
    /etc/default/rsync
    /etc/rsyncd.conf
  } ], ensure => 'absent';
};

task 'status' => sub {
  my $rsync = config -force;

};

1;
