package Rex::Malta::Redis;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( redis => @_ );

  my $redis = {
    active      => $config->{active}  // 0,
    restart     => $config->{restart} // 1,
    address     => $config->{address} // "127.0.0.1",
    port        => $config->{port}    // 6379,
  };

  inspect $redis if Rex::Malta::DEBUG;

  set 'redis' => $redis;
};

task 'setup' => sub {
  return unless my $redis = config;

  pkg [ qw/redis-server redis-tools/ ], ensure => 'present';

  file "/etc/default/redis-server", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@default.redis" );

  file [ "/etc/redis" ], ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/redis/redis.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/redis.conf" );

  service 'redis', ensure => "started";
  service 'redis' => "restart" if $redis->{restart};

  file "/etc/logrotate.d/redis-server", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/logrotate.conf.redis" );
};

task 'clean' => sub {
  return unless my $redis = config;

};

task 'remove' => sub {
  my $redis = config -force;

  pkg [ qw/redis-server redis-tools/ ], ensure => 'absent';

  file [ "/etc/redis", "/var/lib/redis" ], ensure => 'absent';
};

task 'status' => sub {
  my $redis = config -force;

  run 'redis_status', timeout => 10,
    command => "/usr/sbin/service redis status";

  say "Redis service status:\n", last_command_output;
};

1;

__DATA__

@default.redis
# Call ulimit -n with this argument prior to invoking Redis itself
ULIMIT=65536
@end

