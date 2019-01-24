package Rex::Helm::MySQL;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'mysql', { };
  return unless $config->{active} or $force;

  my $mysql = {
    active      => $config->{active}    // FALSE,
    address     => $config->{address}   || "127.0.0.1",
    port        => $config->{port}      || 3306,
    rootpw      => $config->{rootpw}    || "",
    conf        => $config->{conf}      || { },
    monit       => $config->{monit}     || { },
  };

  $mysql->{monit}{enabled}  //= FALSE;

  inspect $mysql if Rex::Helm::DEBUG;

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

  for my $name ( keys %{ $mysql->{conf} } ) {
    my $conf = $mysql->{conf}{ $name };

    $conf->{enabled}  //= 0;
    $conf->{name}     ||= $name;

    set conf => $conf;

    if ( $conf->{enabled} ) {
      file "/etc/mysql/conf.d/$conf->{name}.cnf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/mysql.conf.$name" );
    }

    else {
      file "/etc/mysql/conf.d/$conf->{name}.cnf", ensure => 'absent';
    }
  }

  service 'mysql', ensure => 'started';
  service 'mysql' => 'restart';

  if ( $mysql->{rootpw} ) {
    run 'update_mysql_rootpw',
      unless  => "mysqladmin -u root -p$mysql->{rootpw} status",
      command => "mysqladmin -u root password $mysql->{rootpw}";
  }

  else {
    Rex::Logger::info( "MySQL root password does not set" => 'warn' );
  }

  if ( is_installed 'logrotate' ) {
    file "/etc/logrotate.d/mysql-server", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/logrotate.conf.mysql" )
  }

  if ( is_installed 'monit' ) {
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

    service 'monit' => 'restart';
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

  # Do NOT remove MySQL datadir

  file [ qw{
    /etc/default/mysql
    /etc/mysql
  } ], ensure => 'absent';

  if ( is_installed 'logrotate' ) {
    file "/etc/logrotate.d/mysql-server", ensure => 'absent';
  }

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/mysql", ensure => 'absent';
    unlink "/etc/monit/conf-enabled/mysql";

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $mysql = config -force;

};

1;
