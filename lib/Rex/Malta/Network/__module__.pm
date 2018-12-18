package Rex::Malta::Network;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'network', { };
  return unless $config->{active} or $force;

  my $network = {
    active      => $config->{active}      // 0,
    forward     => $config->{forward}     // 0,
    nameserver  => $config->{nameserver}  || [ qw/8.8.8.8 8.8.4.4/ ],
    ethernet    => $config->{ethernet}    || { },
    bridge      => $config->{bridge}      || { },
  };

  $network->{nameserver} = [ $network->{nameserver} ]
    unless ref $network->{nameserver} eq 'ARRAY';

  inspect $network if Rex::Malta::DEBUG;

  set 'network' => $network;
};

task 'setup' => sub {
  return unless my $network = config;

  pkg [
    qw/netbase ifupdown net-tools/
  ], ensure => "present";

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
