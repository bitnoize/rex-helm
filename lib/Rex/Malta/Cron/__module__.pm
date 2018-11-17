package Rex::Malta::Cron;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( cron => @_ );

  my $cron = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
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

  service 'cron', ensure => "started";
  service 'cron' => "restart" if $cron->{restart};

  if ( is_dir "/etc/monit" ) {
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
  }
};

task 'clean' => sub {
  return unless my $cron = config;

};

task 'remove' => sub {
  my $cron = config -force;

  Rex::Logger::info( "Cron will NOT removed" => 'warn' );
};

task 'status' => sub {
  my $cron = config -force;

  run 'cron_status', timeout => 10,
    command => "/usr/sbin/service cron status";

  say "Cron service status:\n", last_command_output;
};

1;
