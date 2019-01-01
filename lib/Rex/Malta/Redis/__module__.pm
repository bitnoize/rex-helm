package Rex::Malta::Redis;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'redis', { };
  return unless $config->{active} or $force;

  my $redis = {
    active      => $config->{active}    // 0,
    address     => $config->{address}   || "127.0.0.1",
    port        => $config->{port}      || 6379,
    monit       => $config->{monit}     || { },
  };

  $redis->{address} = [ $redis->{address} ]
    unless ref $redis->{address} eq 'ARRAY';

  $redis->{monit}{enabled}  //= 0;
  $redis->{monit}{address}  ||= $redis->{address}[0];
  $redis->{monit}{port}     ||= $redis->{port};
  $redis->{monit}{timeout}  ||= 10;
  $redis->{monit}{dumpsize} ||= 100;

  inspect $redis if Rex::Malta::DEBUG;

  set 'redis' => $redis;
};

task 'setup' => sub {
  return unless my $redis = config;

  pkg [ qw/redis-server redis-tools/ ], ensure => 'present';

  file "/etc/default/redis-server", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.redis" );

  file [ "/etc/redis" ], ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/redis/redis.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/redis.conf" );

  service 'redis', ensure => 'started';
  service 'redis' => 'restart';

  if ( is_installed 'logrotate' ) {
    file "/etc/logrotate.d/redis-server", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/logrotate.conf.redis" );
  }

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/redis", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.redis" );

    if ( $redis->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/redis",
        "/etc/monit/conf-enabled/redis";
    }

    else {
      unlink "/etc/monit/conf-enabled/redis";
    }

    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $redis = config;

};

task 'remove' => sub {
  my $redis = config -force;

  pkg [
    qw/redis-server redis-tools/
  ], ensure => 'absent';

  # Do NOT remove /var/lib/redis

  file [ qw{
    /etc/default/redis-server
    /etc/redis
  } ], ensure => 'absent';

  if ( is_installed 'logrotate' ) {
    file [ qw{
      /etc/logrotate.d/redis-server
    } ], ensure => 'absent';
  }

  if ( is_installed 'monit' ) {
    file [ qw{
      /etc/monit/conf-available/redis
      /etc/monit/conf-enabled/redis
    } ], ensure => 'absent';

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $redis = config -force;

  run 'redis_status', timeout => 10,
    command => "/usr/sbin/service redis status";

  say "Redis service status:\n", last_command_output;
};

1;
