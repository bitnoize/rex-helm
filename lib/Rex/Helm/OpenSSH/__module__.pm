package Rex::Helm::OpenSSH;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'openssh', { };
  return unless $config->{active} or $force;

  my $openssh = {
    active      => $config->{active}    // FALSE,
    address     => $config->{address}   || "0.0.0.0",
    port        => $config->{port}      || 22,
    monit       => $config->{monit}     || { },
  };

  $openssh->{address} = [ $openssh->{address} ]
    unless ref $openssh->{address} eq 'ARRAY';

  $openssh->{monit}{enabled}  //= FALSE;
  $openssh->{monit}{timeout}  ||= 10;

  inspect $openssh if Rex::Helm::DEBUG;

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

  service 'ssh', ensure => 'started';
  service 'ssh' => 'restart';

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

    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $openssh = config;

};

task 'remove' => sub {
  my $openssh = config -force;

  # Do NOT remove OpenSSH

  if ( is_installed 'monit' ) {
    file [ qw{
      /etc/monit/conf-available/openssh
      /etc/monit/conf-enabled/openssh
    } ], ensure => 'absent';

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $openssh = config -force;

};

1;
