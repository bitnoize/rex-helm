package Rex::Helm::Monit;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'monit', { };
  return unless $config->{active} or $force;

  my $monit = {
    active      => $config->{active}    // FALSE,
    address     => $config->{address}   || "127.0.0.1",
    port        => $config->{port}      || 2812,
    cert        => $config->{cert}      || undef,
    auth        => $config->{auth}      || "monit:secret",
    mmonit      => $config->{mmonit}    || "",
    confs       => $config->{confs}     || { },
  };

  inspect $monit if Rex::Helm::DEBUG;

  set 'monit' => $monit;
};

task 'setup' => sub {
  return unless my $monit = config;

  my $cert = Rex::Helm::PKI::certificate( $monit->{cert} );
  return Rex::Logger::info( "Monit cert is not ready" => 'warn' ) unless $cert;

  pkg [ qw/monit/ ], ensure => 'present';

  # FIXME find better solution to start monit before network
  if ( is_file "/etc/init.d/monit" ) {
    append_or_amend_line "/etc/init.d/monit",
      regexp => qr/Required-Start/,
      line => "# Required-Start:    \$remote_fs \$network";

    append_or_amend_line "/etc/init.d/monit",
      regexp => qr/Required-Stop/,
      line => "# Required-Stop:     \$remote_fs \$network";
  }

  $monit->{path_fullcert} = "/etc/monit/monit.pem";

  file "/etc/default/monit", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.monit" );

  file "/etc/monit", ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/monit/monitrc", ensure => 'present',
    owner => 'root', group => 'root', mode => 600,
    content => template( "files/monit.conf" );

  my $fullcert = join "\n",
    cat( $cert->{path_crt} ), cat( $cert->{path_key} );

  file $monit->{path_fullcert}, ensure => 'present',
    owner => 'root', group => 'root', mode => 600,
    content => $fullcert;

  for my $name ( keys %{ $monit->{confs} } ) {
    my $conf = $monit->{confs}{ $name };

    $conf->{enabled}  //= FALSE;
    $conf->{name}     ||= $name;

    set conf => $conf;

    file "/etc/monit/conf-available/$conf->{name}", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.$name" );

    if ( $conf->{enabled} ) {
      symlink "/etc/monit/conf-available/$conf->{name}",
        "/etc/monit/conf-enabled/$conf->{name}";
    }

    else {
      unlink "/etc/monit/conf-enabled/$conf->{name}";
    }
  }

  service 'monit', ensure => 'started';
  service 'monit' => 'restart';

  if ( is_installed 'logrotate' ) {
    file "/etc/logrotate.d/monit", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/logrotate.conf.monit" );
  }
};

task 'clean' => sub {
  return unless my $monit = config;

  file [ qw{
    /etc/monit/conf-enabled/top
    /etc/monit/conf-enabled/rsyslog

    /etc/monit/conf-available/top
    /etc/monit/conf-available/apache2
    /etc/monit/conf-available/mdadm
    /etc/monit/conf-available/memcached
    /etc/monit/conf-available/openntpd
    /etc/monit/conf-available/openssh-server
    /etc/monit/conf-available/pdns-recursor
    /etc/monit/conf-available/snmpd
    /etc/monit/conf-available/ping
    /etc/monit/conf-available/rsyslog

    /var/lib/monit/state
  } ], ensure => 'absent';

  service 'monit' => 'restart';
};

task 'remove' => sub {
  my $monit = config -force;

  pkg [ qw/monit/ ], ensure => 'absent';

  file [ qw{
    /etc/default/monit
    /etc/monit
  } ], ensure => 'absent';

  if ( is_installed 'logrotate' ) {
    file "/etc/logrotate.d/monit", ensure => 'absent';
  }
};

task 'status' => sub {
  my $monit = config -force;

  run 'monit_status', command => "/usr/bin/monit status";
  say last_command_output;
};

1;
