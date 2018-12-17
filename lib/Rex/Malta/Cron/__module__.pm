package Rex::Malta::Cron;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( cron => @_ );

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

  inspect $cron if Rex::Malta::DEBUG;

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

  my $crontab = $cron->{crontab};

  for my $name ( keys %$crontab ) {
    my $enabled = $crontab->{ $name };

    if ( $enabled ) {
      file "/etc/cron.d/$name", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        source => "files/crontab.$name";
    }

    else {
      unlink "/etc/cron.d/$name";
    }
  }

  for my $period ( qw/hourly daily weekly monthly/ ) {
    my $conf = $cron->{ $period };

    for my $name ( keys %$conf ) {
      my $enabled = $conf->{ $name };

      if ( $enabled ) {
        file "/etc/cron.$period/$name", ensure => 'present',
          owner => 'root', group => 'root', mode => 644,
          source => "files/cron.$period.$name";
      }

      else {
        unlink "/etc/cron.$period/$name";
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
};

task 'status' => sub {
  my $cron = config -force;

  run 'cron_status', timeout => 10,
    command => "/usr/sbin/service cron status";

  say "Cron service status:\n", last_command_output;
};

1;
