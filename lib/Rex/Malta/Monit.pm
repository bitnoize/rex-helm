package Rex::Malta::Monit;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( monit => @_ );

  my $monit = {
    active      => $config->{active}  // 0,
    restart     => $config->{restart} // 1,
    address     => $config->{address} // "0.0.0.0",
    port        => $config->{port}    // 2812,
    auth        => $config->{auth}    // "monit:secret",
    mmonit      => $config->{mmonit}  //
                      "https://monit:secret\@monit.test.net:3127/collector",
    confs       => $config->{confs}   // { },
  };

  $monit->{cert} = "/etc/monit/monit.pem";

  inspect $monit if Rex::Malta::DEBUG;

  set 'monit' => $monit;
};

task 'setup' => sub {
  return unless my $monit = config;

  pkg [ qw/monit/ ], ensure => 'present';

  file "/etc/default/monit", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@default.monit" );

  # FIXME find better solution to start monit before network
  if ( is_file "/etc/init.d/monit" ) {
    append_or_amend_line "/etc/init.d/monit",
      regexp => qr/Required-Start/,
      line => "# Required-Start:    \$remote_fs \$network";

    append_or_amend_line "/etc/init.d/monit",
      regexp => qr/Required-Stop/,
      line => "# Required-Stop:     \$remote_fs \$network";
  }

  file "/etc/monit", ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/monit/monitrc", ensure => 'present',
    owner => 'root', group => 'root', mode => 600,
    content => template( "files/monit.conf" );

  file $monit->{cert}, ensure => 'present',
    owner => 'root', group => 'root', mode => 600,
    source => "files/monit.pem";

  my $confs = $monit->{confs};

  for my $name ( keys %$confs ) {
    my $conf = $confs->{ $name };

    $conf->{enabled} ||= 0;

    set conf => $conf;

    file "/etc/monit/conf-available/$name", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.$name" );

    if ( $conf->{enabled} ) {
      symlink "/etc/monit/conf-available/$name",
        "/etc/monit/conf-enabled/$name";
    }

    else {
      unlink "/etc/monit/conf-enabled/$name";
    }
  }

  service 'monit', ensure => "started";
  service 'monit' => "restart" if $monit->{restart};

  file "/etc/logrotate.d/monit", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/logrotate.conf.monit" );
};

task 'clean' => sub {
  return unless my $monit = config;

  file [
    "/etc/monit/conf-enabled/top",
    "/etc/monit/conf-enabled/rsyslog",

    "/etc/monit/conf-available/top",
    "/etc/monit/conf-available/apache2",
    "/etc/monit/conf-available/mdadm",
    "/etc/monit/conf-available/memcached",
    "/etc/monit/conf-available/openntpd",
    "/etc/monit/conf-available/openssh-server",
    "/etc/monit/conf-available/pdns-recursor",
    "/etc/monit/conf-available/snmpd",
    "/etc/monit/conf-available/ping",
    "/etc/monit/conf-available/rsyslog",

    "/var/lib/monit/state"
  ], ensure => 'absent';

  service 'monit' => 'restart' if $monit->{restart};
};

task 'remove' => sub {
  my $monit = config -force;

  pkg [ qw/monit/ ], ensure => 'absent';

  file [ "/etc/monit", "/var/lib/monit" ], ensure => 'absent';
};

task 'status' => sub {
  my $monit = config -force;

  run 'monit_status', timeout => 10,
    command => "/usr/bin/monit status";

  say "Monit service status:\n", last_command_output;
};

1;

__DATA__

@default.monit
# Set START to yes to start the monit
START="yes"

# Options to pass to monit
#MONIT_OPTS=""
@end

