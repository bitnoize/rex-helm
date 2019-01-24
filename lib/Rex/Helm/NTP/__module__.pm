package Rex::Helm::NTP;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'ntp', { };
  return unless $config->{active} or $force;

  my $ntp = {
    active      => $config->{active}    // FALSE,
    monit       => $config->{monit}     || { },
  };

  $ntp->{monit}{enabled}  //= FALSE;

  inspect $ntp if Rex::Helm::DEBUG;

  set 'ntp' => $ntp;
};

task 'setup' => sub {
  return unless my $ntp = config;

  pkg [ qw/ntp/ ], ensure => 'present';

  file "/etc/default/ntp", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.ntp" );

  file "/etc/ntp.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/ntp.conf" );

  service 'ntp', ensure => 'started';
  service 'ntp' => 'restart';

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/ntp", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.ntp" );

    if ( $ntp->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/ntp",
        "/etc/monit/conf-enabled/ntp";
    }

    else {
      unlink "/etc/monit/conf-enabled/ntp";
    }

    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $ntp = config;

  pkg [ qw/ntpdate/ ], ensure => 'absent';
};

task 'remove' => sub {
  my $ntp = config -force;

  pkg [ qw/ntp/ ], ensure => 'absent';

  file [ qw{
    /etc/default/ntp
    /etc/ntp.conf
  } ], ensure => 'absent';

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/ntp", ensure => 'absent';
    unlink "/etc/monit/conf-enabled/ntp";

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $ntp = config -force;

};

task 'sync' => sub {
  my $ntp = config -force;

  run 'sntp_sync', timeout => 60,
    command => "/usr/bin/sntp -s pool.ntp.org && hwclock -w";
};

1;
