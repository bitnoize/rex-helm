package Rex::Malta::Dnsmasq;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( dnsmasq => @_ );

  my $dnsmasq = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    resolver    => $config->{resolver}  // 1,
    address     => $config->{address}   // [ "127.0.0.1" ],
    interface   => $config->{interface} // [ "lo" ],
    port        => $config->{port}      // 53,
    upstream    => $config->{upstream}  // [ qw/8.8.8.8 8.8.4.4/ ],
    confs       => $config->{confs}     // [ ],
  };

  my @nameserver = map {
    # Add port number only if non standart one
    int $dnsmasq->{port} == 53 ? $_ : join ':', $_, $dnsmasq->{port}
  } @{ $dnsmasq->{address} };

  $dnsmasq->{nameserver} = [ @nameserver ];

  $dnsmasq->{local} = [
    map { join '#', $_, $dnsmasq->{port} } @{ $dnsmasq->{address} }
  ];

  inspect $dnsmasq if Rex::Malta::DEBUG;

  set 'dnsmasq' => $dnsmasq;
};

task 'setup' => sub {
  return unless my $dnsmasq = config;

  pkg [ qw/dnsmasq/ ], ensure => 'present';

  file "/etc/default/dnsmasq", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@default.dnsmasq" );

  file "/etc/dnsmasq.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/dnsmasq.conf" );

  my $confs = $dnsmasq->{confs};

  for my $name ( @$confs ) {
    file "/etc/dnsmasq.d/$name", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/dnsmasq.conf.$name" );
  }

  service 'dnsmasq', ensure => "started";
  service 'dnsmasq' => "restart" if $dnsmasq->{restart};

  if ( $dnsmasq->{resolver} ) {
    file "/etc/resolv.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "\@resolv.conf.dnsmasq" );
  }
};

task 'clean' => sub {
  return unless my $dnsmasq = config;

};

task 'remove' => sub {
  my $dnsmasq = config -force;

  pkg [ qw/dnsmasq/ ], ensure => "absent";

  file [
    "/etc/dnsmasq.conf", "/etc/dnsmasq.d",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $dnsmasq = config -force;

  run 'dnsmasq_status', timeout => 10,
    command => "/usr/sbin/service dnsmasq status";

  say "Dnsmasq service status:\n", last_command_output;
};

1;

__DATA__

@default.dnsmasq
#DOMAIN_SUFFIX="$(dnsdomainname)"
#DNSMASQ_OPTS="--conf-file=/etc/dnsmasq.alt"

# Whether or not to run the dnsmasq daemon
ENABLED=1

# Search this drop directory for configuration options
CONFIG_DIR=/etc/dnsmasq.d,.dpkg-dist,.dpkg-old,.dpkg-new
@end

@resolv.conf.dnsmasq
<%= join "\n", map { "nameserver $_" } @{ $dnsmasq->{dnsmasq} } %>
@end

