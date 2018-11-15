package Rex::Malta::QemuKVM;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( qemukvm => @_ );

  my $qemukvm = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
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

# file "/etc/sysctl.d/10-forward.conf", ensure => 'present',
#   owner => 'root', group => 'root', mode => 644,
#   content => template( "files/sysctl.conf.10-forward" ),
#   on_change => sub {
#     run 'sysctl_reload', timeout => 10,
#       command => "sysctl -p /etc/sysctl.d/10-forward.conf";
#   };

  service 'libvirtd', ensure => 'started';
  service 'libvirt-guests', ensure => 'started';
  service 'libvirtd' => "restart" if $qemukvm->{restart};

  if ( is_dir "/etc/monit" ) {
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

  file [
    "/etc/default/libvirtd", "/etc/default/libvirt-fuests",
    "/etc/monit/conf-available/qemukvm",
    "/etc/monit/conf-enabled/qemukvm",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $qemukvm = config -force;

  run 'qemukvm_status', timeout => 10,
    command => "/usr/sbin/service libvirtd status";

  say "QemuKVM service status:\n", last_command_output;
};

1;
