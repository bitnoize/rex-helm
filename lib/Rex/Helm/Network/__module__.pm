package Rex::Helm::Network;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'network', { };
  return unless $config->{active} or $force;

  my $network = {
    active      => $config->{active}      // FALSE,
    nameserver  => $config->{nameserver}  || [ qw/8.8.8.8 8.8.4.4/ ],
    ethernet    => $config->{ethernet}    || { },
    bridge      => $config->{bridge}      || { },
    shaper      => $config->{shaper}      || { },
  };

  $network->{nameserver} = [ $network->{nameserver} ]
    unless ref $network->{nameserver} eq 'ARRAY';

  $network->{shaper}{enabled} //= FALSE;
  $network->{shaper}{ifbs}    //= 1;
  $network->{shaper}{link}    ||= [ qw/100Mbit 100Mbit/ ];
  $network->{shaper}{misc}    ||= [ qw/ 10Mbit  10Mbit/ ];

  inspect $network if Rex::Helm::DEBUG;

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

  if ( keys %{ $network->{ethernet} } ) {
    set ethernet => $network->{ethernet};

    file "/etc/network/interfaces.d/ethernet", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/interfaces.ethernet" ),
      on_change => sub {
        Rex::Logger::info( "Network ethernet interface changed" => 'warn' );
      };
  }

  else {
    file "/etc/network/interfaces.d/ethernet", ensure => 'absent';
  }

  if ( keys %{ $network->{bridge} } ) {
    pkg [ qw/bridge-utils/ ], ensure => "present";

    set bridge => $network->{bridge};

    file "/etc/network/interfaces.d/bridge", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/interfaces.bridge" ),
      on_change => sub {
        Rex::Logger::info( "Network bridge interface changed" => 'warn' );
      };
  }

  else {
    file "/etc/network/interfaces.d/bridge", ensure => 'absent';
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

  if ( $network->{shaper}{enabled} ) {
    file "/etc/modules-load.d/ifb.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/modules-load.conf.ifb" );

    file "/etc/modprobe.d/ifb.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/modprobe.conf.ifb" );

    file "/etc/network/shaper.sh", ensure => 'present',
      owner => 'root', group => 'root', mode => 755,
      content => template( "files/network.shaper.sh" );
  }

  else {
    file [ qw{
      /etc/modules-load.d/ifb.conf
      /etc/modprobe.d/ifb.conf
      /etc/network/shaper.sh
    } ], ensure => 'absent';
      
  }
};

task 'clean' => sub {
  return unless my $network = config;

  file [ qw{
    /etc/network/if-up.d/shaper
    /etc/network/if-up.d/shaper0
    /etc/network/if-down.d/shaper
    /etc/network/if-down.d/shaper0
    /etc/network/interfaces.d/ifb
  } ], ensure => 'absent';
};

task 'remove' => sub {
  my $network = config -force;

  file [ qw{
    /etc/modules-load.d/ifb.conf
    /etc/modprobe.d/ifb.conf
    /etc/network/shaper.sh
  } ], ensure => 'absent';
};

task 'status' => sub {
  my $network = config -force;

};

task 'shaper' => sub {
  return unless my $network = config;

  die "Param --iface with interface name required\n"
    unless my $iface = param_lookup 'iface';

  run 'shaper_details',
    command => template( "\@shaper_details", iface => $iface );

  say last_command_output;
};

1;

__DATA__

@shaper_details
echo -e "\n===== Disciplines ====="
/sbin/tc -s -p qdisc show dev <%= $iface %>

echo -e "\n===== Classes ====="
/sbin/tc -s -p class show dev <%= $iface %>

echo -e "\n===== Fileters ====="
/sbin/tc -s -p filter show dev <%= $iface %>
@end

