package Rex::Malta::NTP;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( ntp => @_ );

  my $ntp = {
    active      => $config->{active}  // 0,
    restart     => $config->{restart} // 1,
  };

  inspect $ntp if Rex::Malta::DEBUG;

  set 'ntp' => $ntp;
};

task 'setup' => sub {
  return unless my $ntp = config;

  pkg [ qw/ntp/ ], ensure => 'present';

  file "/etc/default/ntp", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@default.ntp" );

  file "/etc/ntp.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/ntp.conf" );

  service 'ntp', ensure => 'started';
  service 'ntp' => "restart" if $ntp->{restart};
};

task 'clean' => sub {
  return unless my $ntp = config;

  pkg [ qw/ntpdate/ ], ensure => 'absent';
};

task 'remove' => sub {
  my $ntp = config -force;

  pkg [ qw/ntp/ ], ensure => 'absent';
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

__DATA__

@default.ntp
NTPD_OPTS="-g"
@end

