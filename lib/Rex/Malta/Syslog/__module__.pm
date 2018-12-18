package Rex::Malta::Syslog;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'syslog', { };
  return unless $config->{active} or $force;

  my $syslog = {
    active      => $config->{active}    // 0,
    rsyslog     => $config->{rsyslog}   || { },
    logrotate   => $config->{logrotate} || { },
    monit       => $config->{monit}     || { },
  };

  $syslog->{monit}{enabled} //= 0;

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

  my $rsyslog = $syslog->{rsyslog};

  for my $name ( keys %$rsyslog ) {
    my $enabled = $rsyslog->{ $name };

    if ( $enabled ) {
      file "/etc/rsyslog.d/$name.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/rsyslog.conf.$name" );
    }

    else {
      unlink "/etc/rsyslog.d/$name.conf";
    }
  }

  service 'rsyslog', ensure => 'started';
  service 'rsyslog' => 'restart';

  file "/etc/logrotate.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/logrotate.conf" );

  my $logrotate = $syslog->{logrotate};

  for my $name ( keys %$logrotate ) {
    my $enabled = $logrotate->{ $name };

    if ( $enabled ) {
      file "/etc/logrotate.d/$name", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/logrotate.conf.$name" );
    }

    else {
      unlink "/etc/logrotate.d/$name";
    }
  }

  if ( is_installed 'monit' ) {
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

    service 'monit' => 'restart';
  }
};

task 'logrotate' => sub {
  return unless my $syslog = config;

  run 'logrotate_run', timeout => 60,
    command => "/usr/sbin/logrotate -f /etc/logrotate.conf";
};

task 'clean' => sub {
  return unless my $syslog = config;

  file [
    "/var/log/mail.err",
    "/var/log/mail.warn",
    "/var/log/mail.info",
    "/var/log/mail.log",
    "/var/log/lpr.log",
    "/var/log/news.log",
  ], ensure => 'absent';
};

task 'remove' => sub {
  my $syslog = config -force;

  # Do NOT remove rsyslog and logrotate

  if ( is_installed 'monit' ) {
    file [
      "/etc/monit/conf-available/syslog",
      "/etc/monit/conf-enabled/syslog",
    ], ensure => 'absent';

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $syslog = config -force;

};

1;
