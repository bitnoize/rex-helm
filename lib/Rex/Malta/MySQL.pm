package Rex::Malta::MySQL;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( mysql => @_ );

  my $mysql = {
    active      => $config->{active}  // 0,
    restart     => $config->{restart} // 1,
    address     => $config->{address} // "127.0.0.1",
    port        => $config->{port}    // 3306,
    rootpw      => $config->{rootpw}  // "",
  };

  inspect $mysql if Rex::Malta::DEBUG;

  set 'mysql' => $mysql;
};

task 'setup' => sub {
  return unless my $mysql = config;

  pkg [ qw/mysql-server mysql-client/ ], ensure => 'present';

  file "/etc/default/mysql", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@default.mysql" );

  file [ "/etc/mysql" ], ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/mysql/my.cnf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/mysql.conf" );

  file "/etc/mysql/debian.cnf", ensure => 'present',
    owner => 'root', group => 'root', mode => 600,
    content => template( "files/mysql.debian.conf" );

  my $confs = $mysql->{confs};

  for my $name ( @$confs ) {
    file "/etc/mysql/conf.d/$name.cnf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/mysql.conf.$name" );
  }

  service 'mysql', ensure => "started";
  service 'mysql' => "restart" if $mysql->{restart};

  my $rootpw = $mysql->{rootpw};

  if ( $rootpw ) {
    run 'update_mysql_rootpw', timeout => 60,
      unless  => "mysqladmin -u root -p$rootpw status",
      command => "mysqladmin -u root password $rootpw";
  }

  file "/etc/logrotate.d/mysql-server", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/logrotate.conf.mysql" );
};

task 'clean' => sub {
  return unless my $mysql = config;

};

task 'remove' => sub {
  my $mysql = config -force;

  pkg [ qw/mysql-server mysql-client/ ], ensure => 'absent';

  file [ "/etc/mysql" ], ensure => 'absent';
};

task 'status' => sub {
  my $mysql = config -force;

  run 'mysql_status', timeout => 10,
    command => "/usr/sbin/service mysql status";

  say "MySQL service status:\n", last_command_output;
};

1;

__DATA__

@default.mysql
@end

