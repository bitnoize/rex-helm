package Rex::Helm::Collectd;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'collectd', { };
  return unless $config->{active} or $force;

  my $collectd = {
    active      => $config->{active}    // FALSE,
    server      => $config->{server}    // FALSE,
    remote      => $config->{remote}    || "",
    interface   => $config->{interface} || "eth0",
    address     => $config->{address}   || "0.0.0.0",
    port        => $config->{port}      || 25826,
    username    => $config->{username}  || "",
    password    => $config->{password}  || "",
    confs       => $config->{confs}     || { },
  };

  for ( qw/interface address/ ) {
    $collectd->{ $_ } = [ $collectd->{ $_ } ]
      unless ref $collectd->{ $_ } eq 'ARRAY';
  }

  $collectd->{monit}{enabled}   //= FALSE;
  $collectd->{monit}{timeout}   ||= 10;

  inspect $collectd if Rex::Helm::DEBUG;

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

  else {
    file "/etc/collectd/passwd", ensure => 'absent';
  }

  for my $name ( keys %{ $collectd->{confs} } ) {
    my $conf = $collectd->{confs}{ $name };

    $conf->{enabled}  //= FALSE;
    $conf->{name}     ||= $name;

    set conf => $conf;

    if ( $conf->{enabled} ) {
      file "/etc/collectd/collectd.conf.d/$conf->{name}.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/collectd.conf.$name" );
    }

    else {
      file "/etc/collectd/collectd.conf.d/$conf->{name}.conf", ensure => 'absent';
    }
  }

  service 'collectd', ensure => 'started';
  service 'collectd' => 'restart';

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/collectd", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.collectd" );

    if ( $collectd->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/collectd",
        "/etc/monit/conf-enabled/collectd";
    }

    else {
      unlink "/etc/monit/conf-enabled/collectd";
    }

    service 'monit' => 'restart';
  }

};

task 'clean' => sub {
  return unless my $collectd = config;

  file [ qw{
    /etc/collectd/collectd.conf.d/filters.conf
    /etc/collectd/collectd.conf.d/thresholds.conf
    /etc/collectd/collectd.conf.d/redis.conf
    /etc/collectd/collectd.conf.d/mysql.conf
    /etc/collectd/collectd.conf.d/grayips.conf
    /etc/collectd/collectd.conf.d/postfix.conf
    /etc/collectd/collectd.conf.d/postgrey.conf
    /etc/collectd/collectd.conf.d/netlink.conf
  } ], ensure => 'absent';
};

task 'remove' => sub {
  my $collectd = config -force;

  #run "kill_collectd",
  # command => "/usr/bin/killall -9 collectd";

  pkg [ qw/collectd collectd-core/ ], ensure => 'absent';

  # Do NOT remove /var/lib/collectd

  file [ qw{
    /etc/default/collectd
    /etc/collectd
  } ], ensure => 'absent';
};

task 'status' => sub {
  my $collectd = config -force;

};

1;
