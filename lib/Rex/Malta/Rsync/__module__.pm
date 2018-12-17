package Rex::Malta::Rsync;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( rsync => @_ );

  my $rsync = {
    active      => $config->{active}    // 0,
    address     => $config->{address}   || "127.0.0.1",
    port        => $config->{port}      || 873,
    storage     => $config->{storage}   || "/var/www/stuff",
  };

  $rsync->{address} = [ $rsync->{address} ]
    unless ref $rsync->{address} eq 'ARRAY';

  $rsync->{monit}{enabled}  //= 0;
  $rsync->{monit}{address}  ||= $rsync->{address}[0];
  $rsync->{monit}{port}     ||= $rsync->{port};
  $rsync->{monit}{timeout}  ||= 10;

  inspect $rsync if Rex::Malta::DEBUG;

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

  file [
    "/etc/default/rsync",
    "/etc/rsyncd.conf",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $rsync = config -force;

};

1;
