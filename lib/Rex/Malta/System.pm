package Rex::Malta::System;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( system => @_ );

  my %info = get_system_information;

  my $system = {
    active      => $config->{active}    // 0,
    rootpw      => $config->{rootpw}    // "",
    grubcmd     => $config->{grubcmd}   // "",
    timezone    => $config->{timezone}  // "Etc/UTC",
    kernver     => $config->{kernver}   // "",
    paranoid    => $config->{paranoid}  // 0,
    aptproxy    => $config->{aptproxy}  // "http://127.0.0.1:9080",
    backports   => $config->{backports} // 0,
    extradebs   => $config->{extradebs} // 0,
    extralink   => $config->{extralink} // "http://debs:secret\@debs.test.net",
    packages    => $config->{packages}  // [ ],
    swapfile    => $config->{swapfile}  // "/swap",
    swapsize    => $config->{swapsize}  // "1024k"
  };

  $system->{hostname} = $info{hostname};

  inspect $system if Rex::Malta::DEBUG;

  set 'system' => $system;
};

task 'stamp', sub {
  # Target hostname may be set wrong and cmdb doesn't attached
  # so do not use config in this task.

  my $name = param_lookup 'name';
  my $addr = param_lookup 'addr';

  die "Specify --name and --addr params\n" unless $name and $addr;

  inspect { name => $name, addr => $addr } if Rex::Malta::DEBUG;

  file "/etc/hostname", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => $name,
    on_change => sub {
      run "hostname -F /etc/hostname"
    };

  file "/etc/hosts", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/hosts",
      name => $name, addr => $addr );
};

task 'setup', sub {
  return unless my $system = config;

  if ( $system->{rootpw} ) {
    my $passwd = join ':', 'root', $system->{rootpw};

    run 'rootpw_chpasswd', timeout => 10,
      command => "echo '$passwd' | chpasswd";
  }

  if ( is_dir "/boot/grub" ) {
    file "/etc/default/grub", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "\@default.grub" ),
      on_change => sub {
        run 'grub_update',
          command => "update-grub";
      };
  }

  file "/etc/timezone", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => $system->{timezone},
    on_change => sub {
      run 'tzdata_configure',
        command => "dpkg-reconfigure -f noninteractive tzdata";
    };

  my $banner = LOCAL {
    run 'banner_figlet', timeout => 10,
      command => "figlet -k $system->{hostname}";
  };

  file "/etc/motd", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/motd", banner => $banner );

  file "/etc/sysctl.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/sysctl.conf" ),
    on_change => sub {
      run 'sysctl_reload', timeout => 10,
        command => "sysctl -p /etc/sysctl.conf";
    };

  symlink "/etc/sysctl.conf", "/etc/sysctl.d/99-sysctl.conf";

  file "/etc/apt/apt.conf.d/10norecommends", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@apt.conf.10norecommends" );

  file "/etc/apt/sources.list", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/apt.sources" );

  if ( $system->{kernver} ) {
    file "/etc/apt/preferences.d/90kernel", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "\@apt.preferences.90kernel" );
  }

  else {
    file [ "/etc/apt/preferences.d/90kernel" ], ensure => 'absent';
  }

  if ( $system->{paranoid} ) {
    file "/etc/apt/apt.conf.d/50proxy", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "\@apt.conf.50proxy" );
  }

  else {
    file [ "/etc/apt/apt.conf.d/50proxy" ], ensure => 'absent';
  }

  if ( $system->{backports} ) {
    file "/etc/apt/preferences.d/60backports", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "\@apt.preferences.60backports" );

    file "/etc/apt/sources.list.d/backports.list", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/apt.sources.backports" );
  }

  else {
    file [
      "/etc/apt/preferences.d/60backports",
      "/etc/apt/sources.list.d/backports.list",
    ], ensure => 'absent';
  }

  if ( $system->{extradebs} ) {
    pkg [ "apt-transport-https" ], ensure => 'present';

#   file "/etc/apt/apt.conf.d/90extradebs", ensure => 'present',
#     owner => 'root', group => 'root', mode => 644,
#     content => template( "files/apt.conf.90extradebs" );

    file "/etc/apt/preferences.d/70extradebs", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "\@apt.preferences.70extradebs" );

    file "/etc/apt/sources.list.d/extradebs.list", ensure => 'present',
      owner => 'root', group => 'root', mode => 600,
      content => template( "files/apt.sources.extradebs" );

    file "/etc/apt/trusted.gpg.d/extradebs.gpg", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      source => "files/apt.trusted.extradebs";
  }

  else {
    file [
      "/etc/apt/apt.conf.d/90extradebs",
      "/etc/apt/preferences.d/70extradebs",
      "/etc/apt/sources.list.d/extradebs.list",
      "/etc/apt/trusted.gpg.d/extradebs.gpg",
    ], ensure => 'absent';
  }

  update_package_db;

  my @packages = (
    qw/procps psmisc sysfsutils attr tzdata aptitude htop/,
    qw/sudo vim curl wget git netcat-openbsd rsync/,
    qw/bash-completion dnsutils/
  );

  push @packages, @{ $system->{packages} };

  pkg [ @packages ], ensure => 'present';

  file "/root/.aptitude", ensure => 'directory',
    owner => 'root', group => 'root', mode => 700;

  file "/root/.aptitude/config", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/aptitude.config" );

  file "/etc/sudoers.new", ensure => 'present',
    owner => 'root', group => 'root', mode => 440,
    content => template( "files/sudoers" );

  rename "/etc/sudoers.new" => "/etc/sudoers";
};

task 'clean' => sub {
  return unless my $system = config;

  file [
    "/etc/apt/apt.conf.d/10norecommend",
    "/etc/apt/apt.conf.d/90extradebs",
  ], ensure => 'absent';
};

task 'remove' => sub {
  my $system = config -force;

};

task 'status' => sub {
  my $system = config -force;

};

task 'swapon' => sub {
  return unless my $system = config;

  append_if_no_such_line "/etc/fstab",
    line => "$system->{swapfile} none swap sw 0 0",
    regexp => qr/$system->{swapfile}/;

  return Rex::Logger::info( "Swap $system->{swapfile} exists" => 'warn' )
    if is_file $system->{swapfile};

  run 'swapon' => timeout => 900,
    command => template( "\@swapon" );
};

task 'swapoff' => sub {
  return unless my $system = config;

  delete_lines_matching "/etc/fstab",
    regexp => qr/$system->{swapfile}/;

  return Rex::Logger::info( "Swap $system->{swapfile} missing" => 'warn' )
    unless is_file $system->{swapfile};

  run 'swapoff', timeout => 900,
    command => template( "\@swapoff" );
};

task 'sensors' => sub {
  return unless my $system = config;

  pkg [ qw/lm-sensors/ ], ensure => 'present';

  file "/etc/modules-load.d/sensors.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/modules-load.conf.sensors" );

  service 'lm-sensors', ensure => "started";
};

task 'firsttime' => sub {
  my $system = config -force;

  pkg [
    qw/task-english task-ssh-server xauth rblcheck strace/,
    qw/eject laptop-detect resolvconf vim-tiny netcat-traditional/,
    qw/aptitude-doc-en apt-listchanges python-apt python-apt-common/,
    qw/debconf-utils installation-report reportbug python-reportbug/,
    qw/debian-faq doc-debian docutils-doc info install-info/,
    qw/bc dc nano emacsen-common mutt gnupg2 w3m krb5-locales/,
    qw/nfs-common rpcbind host ftp telnet iproute tcpd/,
    qw/dictionaries-common iamerican ibritish ienglish-common wamerican/,
  ], ensure => 'absent';
};

1;

__DATA__

@default.grub
GRUB_DEFAULT=0
GRUB_TIMEOUT=1
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash net.ifnames=0 biosdevname=0"
GRUB_CMDLINE_LINUX=""

# Text mode
GRUB_TERMINAL=console

# Graphics mode
#GRUB_GFXMODE="800x600x32"

# Don't pass "root=UUID=xxx" to kernel
#GRUB_DISABLE_LINUX_UUID="true"

# Disable generation of recovery mode menu
#GRUB_DISABLE_RECOVERY="true"
@end

@swapon
dd if=/dev/zero of=<%= $system->{swapfile} %> bs=1024 count=<%= $system->{swapsize} %>
chown root:root <%= $system->{swapfile} %>
chmod 600 <%= $system->{swapfile} %>
mkswap <%= $system->{swapfile} %>
swapon <%= $system->{swapfile} %>
@end

@swapoff
swapoff <%= $system->{swapfile} %>
rm -f <%= $system->{swapfile} %>
@end

@apt.conf.10norecommends
APT::Install-Recommends "0";
APT::Install-Suggests "0";
@end

@apt.conf.50proxy
Acquire::http::proxy "<%= $system->{aptproxy} %>";
@end

@apt.preferences.60backports
Package: *
Pin: release o=Debian Backports
Pin-Priority: 600
@end

@apt.preferences.70extradebs
Package: *
Pin: release o=extradebs
Pin-Priority: 700
@end

@apt.preferences.90kernel
Package: linux-image-*
Pin: version <%= $system->{kernver} %>*
Pin-Priority: 1001
@end

