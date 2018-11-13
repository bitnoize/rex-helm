package Rex::Malta::Unbound;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( unbound => @_ );

  my $unbound = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    resolver    => $config->{resolver}  // 0,
    address     => $config->{address}   // [ "127.0.0.1" ],
    port        => $config->{port}      // 53,
    allowed     => $config->{allowed}   // [ qw{127.0.0.0/8} ],
    confs       => $config->{confs}     // [ ],
  };

  my @nameserver = map {
    # Add port number only if non standart one
    int $unbound->{port} == 53 ? $_ : join ':', $_, $unbound->{port}
  } @{ $unbound->{address} };

  $unbound->{nameserver} = [ @nameserver ];

  inspect $unbound if Rex::Malta::DEBUG;

  set 'unbound' => $unbound;
};

task 'setup' => sub {
  return unless my $unbound = config;

  pkg [ qw/unbound/ ], ensure => 'present';

  file "/etc/default/unbound", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@default.unbound" );

  file "/etc/unbound/unbound.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/unbound.conf" );

  my $confs = $unbound->{confs};

  for my $name ( @$confs ) {
    file "/etc/unbound/unbound.conf.d/$name.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/unbound.conf.$name" );
  }

  service 'unbound', ensure => "started";
  service 'unbound' => "restart" if $unbound->{restart};

  if ( $unbound->{resolver} ) {
    file "/etc/resolv.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "\@resolv.conf.unbound" );
  }
};

task 'clean' => sub {
  return unless my $unbound = config;

  file [ "/etc/resolvconf" ], ensure => 'absent';
};

task 'remove' => sub {
  my $unbound = config -force;

  pkg [ qw/unbound/ ], ensure => 'absent';

  file [
    "/etc/unbound", "/var/lib/unbound"
  ], ensure => 'absent';
};

task 'status' => sub {
  my $unbound = config -force;

  run 'unbound_status', timeout => 10,
    command => "/usr/sbin/service unbound status";

  say "Unbound service status:\n", last_command_output;
};

1;

__DATA__

@default.unbound
UNBOUND_ENABLE="true"

# Whether to automatically update the root trust anchor file
ROOT_TRUST_ANCHOR_UPDATE="true"

# File in which to store the root trust anchor
ROOT_TRUST_ANCHOR_FILE="/var/lib/unbound/root.key"

# Provide unbound's ip to resolvconf
RESOLVCONF="false"

# Configure as forwarders
RESOLVCONF_FORWARDERS="false"

ulimit -Hn 10240
ulimit -Sn 10240
@end

@resolv.conf.unbound
<%= join "\n", map { "nameserver $_" } @{ $unbound->{nameserver} } %>
@end

