package Rex::Malta::QemuKVM;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'qemukvm', { };
  return unless $config->{active} or $force;

  my $qemukvm = {
    active      => $config->{active}    // 0,
    monit       => $config->{monit}     || { },
  };

  $qemukvm->{monit}{enabled}  //= 0;

  inspect $qemukvm if Rex::Malta::DEBUG;

  set 'qemukvm' => $qemukvm;
};

task 'setup' => sub {
  return unless my $qemukvm = config;

  pkg [
    qw/qemu-kvm qemu-utils libvirt-clients libvirt-daemon-system/,
    qw/irqbalance netcat-openbsd virtinst virt-top/,
  ], ensure => 'present';

  file "/etc/default/libvirtd", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.libvirtd" );

  file "/etc/default/libvirt-guests", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.libvirt-guests" );

  service 'libvirtd', ensure => 'started';
  service 'libvirt-guests', ensure => 'started';
  service 'libvirtd' => 'restart';

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/qemukvm", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.qemukvm" );

    if ( $qemukvm->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/qemukvm",
        "/etc/monit/conf-enabled/qemukvm";
    }

    else {
      unlink "/etc/monit/conf-enabled/qemukvm";
    }

    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $qemukvm = config;

};

task 'remove' => sub {
  my $qemukvm = config -force;

  pkg [
    qw/qemu-kvm libvirt-clients libvirt-daemon-system virtinst virt-top/
  ], ensure => 'absent';

  file [ qw{
    /etc/default/libvirtd
    /etc/default/libvirt-guests
  } ], ensure => 'absent';

  if ( is_installed 'monit' ) {
    file [ qw{
      /etc/monit/conf-available/qemukvm
      /etc/monit/conf-enabled/qemukvm
    } ], ensure => 'absent';

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $qemukvm = config -force;

  run 'qemukvm_status',
    command => "/usr/sbin/service libvirtd status";

  say last_command_output;
};

1;
