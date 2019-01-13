package Rex::Malta::Rsyslog;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'rsyslog', { };
  return unless $config->{active} or $force;

  my $rsyslog = {
    active      => $config->{active}  // 0,
    confs       => $config->{confs}   || { },
    monit       => $config->{monit}   || { },
  };

  $rsyslog->{monit}{enabled} //= 0;

  inspect $rsyslog if Rex::Malta::DEBUG;

  set rsyslog => $rsyslog;
}

task 'setup' => sub {
  return unless my $rsyslog = config;

  pkg [ qw/rsyslog/ ], ensure => 'present';

  file "/etc/default/rsyslog", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.rsyslog" );

  file "/etc/rsyslog.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/rsyslog.conf" );

  for my $name ( keys %{ $rsyslog->{confs} } ) {
    my $conf = $rsyslog->{confs}{ $name };

    $conf->{enabled}  //= 0;
    $conf->{name}     ||= $name;

    set conf => $conf;

    if ( $conf->{enabled} ) {
      file "/etc/rsyslog.d/$conf->{name}.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/rsyslog.conf.$name" );
    }

    else {
      file "/etc/rsyslog.d/$conf->{name}.conf", ensure => 'absent';
    }
  }

  service 'rsyslog', ensure => 'started';
  service 'rsyslog' => 'restart';

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/rsyslog", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.rsyslog" );

    if ( $rsyslog->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/rsyslog",
        "/etc/monit/conf-enabled/rsyslog";
    }

    else {
      unlink "/etc/monit/conf-enabled/rsyslog";
    }

    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $rsyslog = config;

  file [ qw{
    /etc/monit/conf-available/syslog
    /etc/monit/conf-enabled/syslog

    /var/log/mail.err
    /var/log/mail.warn
    /var/log/mail.info
    /var/log/lpr.log
    /var/log/news.log
  } ], ensure => 'absent';
};

task 'remove' => sub {
  my $rsyslog = config -force;

  # Do NOT remove rsyslog

  if ( is_installed 'monit' ) {
    file [ qw{
      /etc/monit/conf-available/rsyslog
      /etc/monit/conf-enabled/rsyslog
    } ], ensure => 'absent';

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $rsyslog = config -force;

  run 'rsyslog_status',
    command => "/usr/sbin/service rsyslog status";

  say last_command_output;
};

1;
