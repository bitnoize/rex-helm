package Rex::Malta::OpenSSH;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $global = Rex::Malta::config( 'global' );
  my $config = Rex::Malta::config( 'openssh' );

  return unless $force or $config->{active};

  my $openssh = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    address     => $config->{address}   || [ $global->{address} ],
    port        => $config->{port}      || 22,
    monit       => $config->{monit}     || { },
  };

  $openssh->{monit}{enabled}  //= 0;

  inspect $openssh if Rex::Malta::DEBUG;

  set 'openssh' => $openssh;
};

task 'setup' => sub {
  return unless my $openssh = config;

  # Both OpenSSH server and client
  pkg [ qw/ssh/ ], ensure => 'present';

  file "/etc/default/ssh", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.ssh" );

  file "/etc/ssh/ssh_config", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/ssh_conf" );

  file "/etc/ssh/sshd_config", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/sshd_conf" );

  file "/root/.ssh", ensure => 'directory',
    owner => 'root', group => 'root', mode => 700;

  file "/root/.ssh/authorized_keys", ensure => 'present',
    owner => 'root', group => 'root', mode => 600,
    content => template( "files/authorized_keys" );

  service 'ssh', ensure => "started";
  service 'ssh' => "restart" if $openssh->{restart};

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/openssh", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.openssh" );

    if ( $openssh->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/openssh",
        "/etc/monit/conf-enabled/openssh";
    }

    else {
      unlink "/etc/monit/conf-enabled/openssh";
    }

    service 'monit' => "restart" if $openssh->{restart};
  }
};

task 'clean' => sub {
  return unless my $openssh = config;

};

task 'remove' => sub {
  my $openssh = config -force;

  Rex::Logger::info( "OpenSSH does NOT removed" => 'warn' );

  file [
    "/etc/monit/conf-available/openssh",
    "/etc/monit/conf-enabled/openssh",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $openssh = config -force;

  run 'openssh_status', timeout => 10,
    command => "/usr/sbin/service openssh status";

  say "OpenSSH service status:\n", last_command_output;
};

1;
