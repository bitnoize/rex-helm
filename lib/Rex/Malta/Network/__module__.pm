package Rex::Malta::Network;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( network => @_ );

  my $network = {
    active      => $config->{active}    // 0,
    forward     => $config->{forward}   // 0,
    resolver    => $config->{resolver}  || [ qw/8.8.8.8 8.8.4.4/ ],
    ethernet    => $config->{ethernet}  || { },
    bridge      => $config->{bridge}    || { },
  };

  inspect $network if Rex::Malta::DEBUG;

  set 'network' => $network;
};

task 'setup' => sub {
  return unless my $network = config;

  pkg [
    qw/netbase ifupdown net-tools/
  ], ensure => "present";

  if ( $network->{forward} ) {
    file "/etc/sysctl.d/10-ip_forward.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/sysctl.conf.10-ip_forward" ),
      on_change => sub {
        run 'sysctl_reload', timeout => 10,
          command => "sysctl -p /etc/sysctl.d/10-ip_forward.conf";
      };
  }

  file "/etc/resolv.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/resolv.conf" );

  #
  # Interfaces
  #

  file "/etc/network/interfaces", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/interfaces" );

  my $ethernet = $network->{ethernet};

  if ( keys %$ethernet ) {
    set ethernet => $ethernet;

    file "/etc/network/interfaces.d/ethernet", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/interfaces.ethernet" ),
      on_change => sub {
        Rex::Logger::info( "Network ethernet interface changed" => 'warn' );
      };
  }

  my $bridge = $network->{bridge};

  if ( keys %$bridge ) {
    pkg [ qw/bridge-utils/ ], ensure => "present";

    set bridge => $bridge;

    file "/etc/network/interfaces.d/bridge", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/interfaces.bridge" ),
      on_change => sub {
        Rex::Logger::info( "Network bridge interface changed" => 'warn' );
      };
  }

  pkg [ qw/isc-dhcp-client/ ], ensure => "present";

  file "/etc/dhcp/dhclient.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/dhclient.conf" );

  file "/etc/dhcp/dhclient-enter-hooks.d/nodnsupdate", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/dhclient-enter-hooks.nodnsupdate" );

  file "/etc/gai.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/gai.conf" );
};

task 'clean' => sub {
  return unless my $network = config;

};

task 'remove' => sub {
  my $network = config -force;

};

task 'status' => sub {
  my $network = config -force;

};

1;
