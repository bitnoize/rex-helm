package Rex::Malta::NTP;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $global = Rex::Malta::config( 'global' );
  my $config = Rex::Malta::config( 'ntp' );

  return unless $force or $config->{active};

  my $ntp = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    monit       => $config->{monit}     || { },
  };

  $ntp->{monit}{enabled}  //= 0;

  inspect $ntp if Rex::Malta::DEBUG;

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
  service 'ntp' => "restart" if $ntp->{restart};

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

    service 'monit' => "restart" if $ntp->{restart};
  }
};

task 'clean' => sub {
  return unless my $ntp = config;

  pkg [ qw/ntpdate/ ], ensure => 'absent';
};

task 'remove' => sub {
  my $ntp = config -force;

  pkg [ qw/ntp/ ], ensure => 'absent';

  file [
    "/etc/default/ntp",
    "/etc/ntp.conf",
    "/etc/monit/conf-available/ntp",
    "/etc/monit/conf-enabled/ntp",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $ntp = config -force;

  run 'ntp_status', timeout => 10,
    command => "ntpq -p";

  say "NTP service status:\n", last_command_output;
};

task 'sync' => sub {
  my $ntp = config -force;

  run 'sntp_sync', timeout => 60,
    command => "sntp -s pool.ntp.org && hwclock -w";
};

1;
