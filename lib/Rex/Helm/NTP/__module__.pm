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

  # NTP is depreceted on Debian systems
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

1;
