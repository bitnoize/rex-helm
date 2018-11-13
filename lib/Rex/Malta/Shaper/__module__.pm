package Rex::Malta::Shaper;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( shaper => @_ );

  my $shaper = {
    active      => $config->{active}  // 0,
    ifb         => $config->{ifb}     // 1,
    link        => $config->{link}    // [ qw/100Mbit 100Mbit/ ],
    base        => $config->{base}    // [ qw/ 10Mbit  95Mbit/ ],
    misc        => $config->{misc}    // [ qw/  5Mbit  10Mbit/ ]
  };

  $shaper->{active} = $config->{active};

  inspect $shaper if Rex::Malta::DEBUG;

  set 'shaper' => $shaper;
};

task 'setup' => sub {
  return unless my $shaper = config;

  if ( $shaper->{ifb} ) {
    file "/etc/modules-load.d/ifb.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/modules-load.conf.ifb" );

    file "/etc/network/interfaces.d/ifb", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/interfaces.ifb" );
  }

  file "/etc/network/if-up.d/shaper0", ensure => 'present',
    owner => 'root', group => 'root', mode => 755,
    content => template( "files/if-up.shaper.root" );

  file "/etc/network/if-down.d/shaper", ensure => 'present',
    owner => 'root', group => 'root', mode => 755,
    content => template( "files/if-down.shaper.root" );
};

task 'clean' => sub {
  return unless my $shaper = config;

  file [
    "/etc/network/if-down.d/shaper0",
  ], ensure => 'absent';
};

task 'remove' => sub {
  my $shaper = config -force;

  file [
    "/etc/modules-load.d/ifb.conf",
    "/etc/network/interfaces.d/ifb",
    "/etc/network/if-up.d/shaper0",
    "/etc/network/if-down.d/shaper",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $shaper = config -force;

  run 'shaper_status', timeout => 10,
    command => template( "\@shaper_status" );

  say "Traffic shaper status:\n", last_command_output;
};

1;

__DATA__

@shaper_status
echo "===== Network Ethernet device ====="
/sbin/tc -s qdisc show dev eth0
/sbin/tc -s class show dev eth0
/sbin/tc -s filter show dev eth0

if [ -n "<%= $shaper->{ifb} ? "IFB" : "" %>" ]; then
  echo "===== Intermediate Functional Block device ====="
  /sbin/tc -s qdisc show dev ifb0
  /sbin/tc -s class show dev ifb0
  /sbin/tc -s filter show dev ifb0
fi
@end

