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

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/rsync", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.rsync" );

    if ( $rsync->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/rsync",
        "/etc/monit/conf-enabled/rsync";
    }

    else {
      unlink "/etc/monit/conf-enabled/rsync";
    }

    service 'monit' => 'restart';
  }
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

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/rsync", ensure => 'absent';
    unlink "/etc/monit/conf-enabled/rsync";

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $rsync = config -force;

};

1;
