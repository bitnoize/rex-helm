package Rex::Helm::Cron;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'cron', { };
  return unless $config->{active} or $force;

  my $cron = {
    active      => $config->{active}    // 0,
    crontab     => $config->{crontab}   || { },
    hourly      => $config->{hourly}    || { },
    daily       => $config->{daily}     || { },
    weekly      => $config->{weekly}    || { },
    monthly     => $config->{monthly}   || { },
    monit       => $config->{monit}     || { },
  };

  $cron->{monit}{enabled} //= 0;

  inspect $cron if Rex::Helm::DEBUG;

  set 'cron' => $cron;
};

task 'setup', sub {
  return unless my $cron = config;

  pkg [ qw/cron/ ], ensure => 'present';

  file "/etc/default/cron", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.cron" );

  file "/etc/crontab", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/crontab" );

  file [ "/var/spool/cron" ], ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  for my $name ( keys %{ $cron->{crontab} } ) {
    my $crontab = $cron->{crontab}{ $name };

    $crontab->{enabled} //= 0;
    $crontab->{name}    ||= $name;

    set crontab => $crontab;

    if ( $crontab->{enabled} ) {
      file "/etc/cron.d/$crontab->{name}", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        source => "files/crontab.$name";
    }

    else {
      file "/etc/cron.d/$crontab->{name}", ensure => 'absent';
    }
  }

  for my $period ( qw/hourly daily weekly monthly/ ) {
    for my $name ( keys %{ $cron->{ $period } } ) {
      my $script = $cron->{ $period }{ $name };

      $script->{enabled}  //= 0;
      $script->{name}     ||= $name;

      set script => $script;


      if ( $script->{enabled} ) {
        file "/etc/cron.$period/$script->{name}", ensure => 'present',
          owner => 'root', group => 'root', mode => 644,
          source => "files/cron.$period.$name";
      }

      else {
        file "/etc/cron.$period/$script->{name}", ensure => 'absent';
      }
    }
  }

  service 'cron', ensure => 'started';
  service 'cron' => 'restart';

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/cron", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.cron" );

    if ( $cron->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/cron",
        "/etc/monit/conf-enabled/cron";
    }

    else {
      unlink "/etc/monit/conf-enabled/cron";
    }

    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $cron = config;

};

task 'remove' => sub {
  my $cron = config -force;

  # Do NOT remove cron

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/cron", ensure => 'absent';
    unlink "/etc/monit/conf-enabled/cron";

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $cron = config -force;

};

1;
