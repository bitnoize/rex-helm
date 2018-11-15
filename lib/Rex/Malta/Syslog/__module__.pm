package Rex::Malta::Syslog;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( syslog => @_ );

  my $syslog = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    monit       => $config->{monit}     // 0,
  };

  inspect $syslog if Rex::Malta::DEBUG;

  set syslog => $syslog;
}

task 'setup' => sub {
  return unless my $syslog = config;

  # Sweet couple
  pkg [ qw/rsyslog logrotate/ ], ensure => 'present';

  file "/etc/default/rsyslog", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.rsyslog" );

  file "/etc/rsyslog.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/rsyslog.conf" );

  file "/etc/logrotate.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/logrotate.conf" );

  service 'rsyslog', ensure => "started";
  service 'rsyslog' => "restart" if $syslog->{restart};

  my @logrotate = qw/apt aptitude dpkg rsyslog/;

  for my $name ( @logrotate ) {
    file "/etc/logrotate.d/$name", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/logrotate.conf.$name" );
  }

  if ( is_dir "/etc/monit" ) {
    file "/etc/monit/conf-available/syslog", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.syslog" );

    if ( $syslog->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/syslog",
        "/etc/monit/conf-enabled/syslog";
    }

    else {
      unlink "/etc/monit/conf-enabled/syslog";
    }
  }
};

task 'clean' => sub {
  return unless my $syslog = config;

  file [
    "/var/log/mail.err", "/var/log/mail.warn",
    "/var/log/mail.info", "/var/log/mail.log",
    "/var/log/lpr.log", "/var/log/news.log",
  ], ensure => 'absent';
};

task 'logrotate' => sub {
  return unless my $syslog = config;

  run 'logrotate_run', timeout => 60,
    command => "/usr/sbin/logrotate -f /etc/logrotate.conf";
};

task 'remove' => sub {
  my $syslog = config -force;

  # Do NOT remove rsyslog and logrotate

  file [
    "/etc/monit/conf-available/syslog",
    "/etc/monit/conf-enabled/syslog",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $syslog = config -force;

};

1;
