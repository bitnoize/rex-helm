package Rex::Malta::System;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'system', { };
  return unless $config->{active} or $force;

  my %info = get_system_information;

  my $system = {
    active      => $config->{active}    // 0,
    rootpw      => $config->{rootpw}    || "",
    grubcmd     => $config->{grubcmd}   || "",
    timezone    => $config->{timezone}  || "Etc/UTC",
    release     => $config->{release}   || "unknown",
    kernver     => $config->{kernver}   || "",
    paranoid    => $config->{paranoid}  // 0,
    aptproxy    => $config->{aptproxy}  || "http://127.0.0.1:9080",
    backports   => $config->{backports} // 0,
    extradebs   => $config->{extradebs} // 0,
    extralink   => $config->{extralink} || "",
    packages    => $config->{packages}  || [ ],
    sysctl      => $config->{sysctl}    || { },
    swapfile    => $config->{swapfile}  || "/swap",
    swapsize    => $config->{swapsize}  || "1024k"
  };

  $system->{hostname} = $info{hostname};

  my @release = qw/debian-jessie debian-stretch kali-rolling/;

  die "Invalid system release: '$system->{release}'\n"
    unless grep { $_ eq $system->{release} } @release;

  inspect $system if Rex::Malta::DEBUG;

  set 'system' => $system;
};

task 'stamp', sub {
  # Target hostname may be set wrong and cmdb doesn't attached
  # so do not use config in this task.

  my $system = {
    hostname  => param_lookup( 'hostname' ),
    address   => param_lookup( 'address' ),
  };

  die "Both of --hostname and --address are required\n"
    unless $system->{hostname} and $system->{address};

  inspect $system if Rex::Malta::DEBUG;

  file "/etc/hostname", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => $system->{hostname};

  file "/etc/hosts", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/hosts", system => $system );

  run 'update_hostname', timeout => 10,
    command => "hostname -F /etc/hostname";
};

task 'setup', sub {
  return unless my $system = config;

  if ( $system->{rootpw} ) {
    my $passwd = join ':', 'root', $system->{rootpw};

    run 'rootpw_chpasswd', timeout => 10,
      command => sprintf "echo '%s' | chpasswd", $passwd;
  }

  if ( is_dir "/boot/grub" ) {
    file "/etc/default/grub", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/default.grub" );

    run 'grub_update', timeout => 10,
      command => "update-grub";
  }

  file "/etc/timezone", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => $system->{timezone};

  run 'tzdata_configure', timeout => 10,
    command => "dpkg-reconfigure -f noninteractive tzdata";

  my $banner = LOCAL {
    run 'banner_figlet', timeout => 10,
      command => sprintf "figlet -k %s", $system->{hostname};
  };

  file "/etc/motd", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/motd", banner => $banner );

  file "/etc/apt/apt.conf.d/10norecommends", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/apt_conf.10norecommends" );

  my $apt_sources = sprintf "files/apt_sources.%s", $system->{release};

  file "/etc/apt/sources.list", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( $apt_sources );

  if ( $system->{kernver} ) {
    file "/etc/apt/preferences.d/90kernel", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/apt_preferences.90kernel" );
  }

  else {
    file "/etc/apt/preferences.d/90kernel", ensure => 'absent';
  }

  if ( $system->{paranoid} ) {
    file "/etc/apt/apt.conf.d/50proxy", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/apt_conf.50proxy" );
  }

  else {
    file "/etc/apt/apt.conf.d/50proxy", ensure => 'absent';
  }

  if ( $system->{backports} ) {
    file "/etc/apt/preferences.d/60backports", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/apt_preferences.60backports" );

    my $apt_sources_backports =
      sprintf "files/apt_sources.backports.%s", $system->{release};

    file "/etc/apt/sources.list.d/backports.list", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( $apt_sources_backports );
  }

  else {
    file [
      "/etc/apt/preferences.d/60backports",
      "/etc/apt/sources.list.d/backports.list",
    ], ensure => 'absent';
  }

  if ( $system->{extradebs} ) {
    file "/etc/apt/apt.conf.d/70extradebs", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/apt_conf.70extradebs" );

    file "/etc/apt/preferences.d/70extradebs", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/apt_preferences.70extradebs" );

    my $apt_sources_extradebs =
      sprintf "files/apt_sources.extradebs.%s", $system->{release};

    file "/etc/apt/sources.list.d/extradebs.list", ensure => 'present',
      owner => 'root', group => 'root', mode => 600,
      content => template( $apt_sources_extradebs );

    file "/etc/apt/trusted.gpg.d/extradebs.gpg", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      source => "files/apt_trusted.extradebs";
  }

  else {
    file [
      "/etc/apt/apt.conf.d/70extradebs",
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

  file "/etc/sysctl.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/sysctl.conf" ),
    on_change => sub {
    };

  symlink "/etc/sysctl.conf", "/etc/sysctl.d/99-sysctl.conf";

  my $sysctl = $system->{sysctl};

  for my $name ( keys %$sysctl ) {
    my $enabled = $sysctl->{ $name };

    if ( $enabled ) {
      file "/etc/sysctl.d/$name.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/sysctl.conf.$name" );
    }

    else {
      unlink "/etc/sysctl.d/$name.conf";
    }

    run 'sysctl_reload', timeout => 10,
      command => "sysctl --system";
  }
};

task 'clean' => sub {
  my $system = config;

  file [
    "/etc/default/rex",
    "/etc/default/grub.ucf-dist",

    "/etc/apt/apt.conf.d/10norecommend",
    "/etc/apt/apt.conf.d/90extradebs",

    "/etc/sudoers.d/90-cloud-init-users",
    "/etc/sysctl.d/10-forward.conf",
  ], ensure => 'absent';
};

task 'remove' => sub {
  my $system = config;

};

task 'status' => sub {
  my $system = config;

};

task 'monit' => sub {
  my $system = config;

  die "Monit is not installed\n" unless is_installed 'monit';

  run 'monit_system_status', timeout => 10,
    command => sprintf "monit status %s", $system->{hostname};

  say last_command_output;
};

task 'swapon' => sub {
  my $system = config;

  append_if_no_such_line "/etc/fstab",
    line => "$system->{swapfile} none swap sw 0 0",
    regexp => qr/$system->{swapfile}/;

  return Rex::Logger::info( "Swap $system->{swapfile} exists" => 'warn' )
    if is_file $system->{swapfile};

  run 'swapon' => timeout => 300,
    command => template( "\@swapon" );

  say last_command_output if Rex::Malta::DEBUG;
};

task 'swapoff' => sub {
  my $system = config;

  delete_lines_matching "/etc/fstab",
    regexp => qr/$system->{swapfile}/;

  return Rex::Logger::info( "Swap $system->{swapfile} missing" => 'warn' )
    unless is_file $system->{swapfile};

  run 'swapoff', timeout => 300,
    command => template( "\@swapoff" );

  say last_command_output if Rex::Malta::DEBUG;
};

task 'sensors' => sub {
  my $system = config;

  pkg [ qw/lm-sensors/ ], ensure => 'present';

  file "/etc/modules-load.d/sensors.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/modules-load.conf.sensors" );

  service 'lm-sensors', ensure => "started";
};

task 'firsttime' => sub {
  my $system = config -force;

  run 'firsttime', timeout => 900,
    command => template( "\@firsttime" );
};

1;

__DATA__

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

@firsttime
# There are a lot of shit on default Debian installation

apt-get -y --purge remove \
  acpi-support-base acpid \
  task-english task-ssh-server xauth rblcheck strace  \
  eject laptop-detect resolvconf vim-tiny netcat-traditional  \
  aptitude-doc-en apt-listchanges python-apt python-apt-common  \
  debconf-utils installation-report reportbug python-reportbug  \
  debian-faq doc-debian docutils-doc info install-info texinfo  \
  bc dc nano emacsen-common mutt gnupg2 w3m krb5-locales  \
  nfs-common rpcbind host ftp telnet iproute tcpd python-debian \
  dictionaries-common iamerican ibritish ienglish-common wamerican  \
  exim4 exim4-base exim4-config exim4-daemon-light bsd-mailx procmail \
  lockfile-progs rename xdg-user-dirs hicolor-icon-theme \
  libcgi-fast-perl libcgi-pm-perl libfcgi-perl \
  libclass-accessor-perl libclass-c3-perl libclass-c3-xs-perl libclass-isa-perl \
  libalgorithm-c3-perl libdata-optlist-perl libdata-section-perl \
  libhtml-form-perl libhtml-format-perl libhtml-parser-perl libhtml-tagset-perl \
  libhtml-tree-perl libhttp-cookies-perl libhttp-daemon-perl libhttp-date-perl \
  libhttp-message-perl libhttp-negotiate-perl \
  libio-html-perl libio-string-perl \
  libio-socket-ip-perl libio-socket-ssl-perl \
  liblog-message-perl liblog-message-simple-perl \
  libmodule-build-perl libmodule-pluggable-perl libmodule-signature-perl \
  libpackage-constants-perl libparams-util-perl \
  libfile-listing-perl libparse-debianchangelog-perl \
  libpod-latex-perl libpod-readme-perl \
  libregexp-common-perl libsoftware-license-perl \
  libsub-exporter-perl libsub-install-perl libsub-name-perl \
  libtext-soundex-perl libtext-template-perl \
  liblwp-mediatypes-perl liblwp-protocol-https-perl \
  libwww-perl liburi-perl libwww-robotrules-perl \
  libnet-http-perl libnet-smtp-ssl-perl libnet-ssleay-perl \
  libmailtools-perl \
  libtimedate-perl \
  libauthen-sasl-perl \
  libperl4-corelibs-perl \
  libswitch-perl \
  libterm-ui-perl \
  libmro-compat-perl \
  libfont-afm-perl \
  libencode-locale-perl \
  libcpan-meta-perl \
  libarchive-extract-perl

@end

