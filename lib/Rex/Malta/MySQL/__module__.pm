package Rex::Malta::MySQL;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( mysql => @_ );

  my $mysql = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    address     => $config->{address}   || "127.0.0.1",
    port        => $config->{port}      || 3306,
    rootpw      => $config->{rootpw}    || "",
    confs       => $config->{confs}     || [ ],
    monit       => $config->{monit}     || { },
  };

  $mysql->{monit}{enabled}  //= 0;
  $mysql->{monit}{address}  ||= $mysql->{address};
  $mysql->{monit}{port}     ||= $mysql->{port};
  $mysql->{monit}{timeout}  ||= 10;

  inspect $mysql if Rex::Malta::DEBUG;

  set 'mysql' => $mysql;
};

task 'setup' => sub {
  return unless my $mysql = config;

  pkg [ qw/mysql-server mysql-client/ ], ensure => 'present';

  file "/etc/default/mysql", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.mysql" );

  file "/etc/mysql", ensure => 'directory',
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

  if ( is_file "/etc/logrotate.conf" ) {
    file "/etc/logrotate.d/mysql-server", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/logrotate.conf.mysql" )
  }

  if ( is_dir "/etc/monit" ) {
    file "/etc/monit/conf-available/mysql", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.mysql" );

    if ( $mysql->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/mysql",
        "/etc/monit/conf-enabled/mysql";
    }

    else {
      unlink "/etc/monit/conf-enabled/mysql";
    }
  }
};

task 'clean' => sub {
  return unless my $mysql = config;

};

task 'remove' => sub {
  my $mysql = config -force;

  pkg [
    qw/mysql-server mysql-client/
  ], ensure => 'absent';

  file [
    "/etc/default/mysql", "/etc/mysql",
    "/etc/logrotate.d/mysql-server",
    "/etc/monit/conf-available/mysql",
    "/etc/monit/conf-enabled/mysql",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $mysql = config -force;

  run 'mysql_status', timeout => 10,
    command => "/usr/sbin/service mysql status";

  say "MySQL service status:\n", last_command_output;
};

1;
