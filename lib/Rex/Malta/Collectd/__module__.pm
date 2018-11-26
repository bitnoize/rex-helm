package Rex::Malta::Collectd;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( collectd => @_ );

  my $collectd = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    server      => $config->{server}    // 0,
    interval    => $config->{interval}  || 60,
    remote      => $config->{remote}    || "graph.test.net",
    interface   => $config->{interface} || [ "eth0" ],
    address     => $config->{address}   || [ "0.0.0.0" ],
    port        => $config->{port}      || 25826,
    username    => $config->{username}  || "stats",
    password    => $config->{password}  || "secret",
    confs       => $config->{confs}     || { },
  };

  inspect $collectd if Rex::Malta::DEBUG;

  set 'collectd' => $collectd;
};

task 'setup' => sub {
  return unless my $collectd = config;

  pkg [ qw/collectd libmnl0/ ], ensure => 'present';

  file "/etc/default/collectd", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.collectd" );

  file "/etc/collectd", ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/collectd/collectd.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/collectd.conf" );

  if ( $collectd->{server} ) {
    file "/etc/collectd/passwd", ensure => 'present',
      owner => 'root', group => 'root', mode => 640,
      content => template( "files/collectd.passwd" );
  }

  my $confs = $collectd->{confs};

  for my $name ( keys %$confs ) {
    my $conf = $confs->{ $name };

    $conf->{enabled}  //= 0;

    set conf => $conf;

    if ( $conf->{enabled} ) {
      file "/etc/collectd/collectd.conf.d/$name.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/collectd.conf.$name" );
    }

    else {
      unlink "/etc/collectd/collectd.conf.d/$name.conf";
    }
  }

  service 'collectd', ensure => "started";
  service 'collectd' => "restart" if $collectd->{restart};
};

task 'clean' => sub {
  return unless my $collectd = config;

  file [
    "/etc/collectd/collectd.conf.d/filters.conf",
    "/etc/collectd/collectd.conf.d/thresholds.conf",
    "/etc/collectd/collectd.conf.d/redis.conf",
    "/etc/collectd/collectd.conf.d/mysql.conf",
    "/etc/collectd/collectd.conf.d/grayips.conf",
    "/etc/collectd/collectd.conf.d/postfix.conf",
    "/etc/collectd/collectd.conf.d/postgrey.conf",
    "/etc/collectd/collectd.conf.d/netlink.conf",
  ], ensure => 'absent';
};

task 'remove' => sub {
  my $collectd = config -force;

# run "kill_collectd", timeout => 10,
#   command => template( "\@kill_collectd" );

  pkg [ qw/collectd collectd-core/ ], ensure => 'absent';

  # Do NOT remove /var/lib/collectd

  file [
    "/etc/default/collectd",
    "/etc/collectd",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $collectd = config -force;

  run 'collectd_status', timeout => 10,
    command => "/usr/sbin/service collectd status";

  say "Collectd service status:\n", last_command_output;
};

1;

__DATA__

@kill_collectd
/usr/bin/killall -9 collectd
@end

