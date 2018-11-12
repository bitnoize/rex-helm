package Rex::Malta::QemuKVM;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( qemukvm => @_ );

  my $qemukvm = {
    active      => $config->{active}  // 0,
    restart     => $config->{restart} // 1,
  };

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
    content => template( "\@default.libvirtd" );

  file "/etc/default/libvirt-guests", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@default.libvirt-guests" );

  my @sysctl = qw/10-forward/;

  for my $file ( @sysctl ) {
    file "/etc/sysctl.d/$file.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/sysctl.conf.$file" ),
      on_change => sub {
        run 'sysctl_reload', timeout => 10,
          command => "sysctl -p /etc/sysctl.d/$file.conf";
      };
  }

  service 'libvirtd', ensure => 'started';
  service 'libvirt-guests', ensure => 'started';
  service 'libvirtd' => "restart" if $qemukvm->{restart};
};

task 'clean' => sub {
  return unless my $qemukvm = config;

};

task 'remove' => sub {
  my $qemukvm = config -force;

  pkg [
    qw/qemu-kvm libvirt-clients libvirt-daemon-system virtinst virt-top/
  ], ensure => 'absent';
};

task 'status' => sub {
  my $qemukvm = config -force;

};

1;

__DATA__

@default.libvirtd
# Start libvirtd to handle qemu/kvm
start_libvirtd="yes"

# Options passed to libvirtd
#libvirtd_opts=""

# Pass in location of kerberos keytab
#export KRB5_KTNAME=/etc/libvirt/libvirt.keytab
@end

@default.libvirt-guests
# URIs to check for running guests
#URIS=default

# Action taken on host boot ( start | ignore )
#ON_BOOT=ignore

# Number of seconds to wait between each guest start
#START_DELAY=0

# Action taken on host shutdown ( suspend | shutdown )
#ON_SHUTDOWN=shutdown

# Shutdown guests concurrently
#PARALLEL_SHUTDOWN=0

# Shutdown guests timeout
#SHUTDOWN_TIMEOUT=300

# Bypass the file system cache
#BYPASS_CACHE=0

# Sync guest time on domain resume
#SYNC_TIME=1
@end

