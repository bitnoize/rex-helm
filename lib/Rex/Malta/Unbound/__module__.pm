package Rex::Malta::Unbound;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( unbound => @_ );

  my $unbound = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    resolver    => $config->{resolver}  // 0,
    address     => $config->{address}   || [ "127.0.0.1" ],
    port        => $config->{port}      || 53,
    allowed     => $config->{allowed}   || [ "127.0.0.0/8" ],
    conf        => $config->{conf}      || { },
    monit       => $config->{monit}     || { },
  };

  my @nameserver = map {
    # Add port number only if non standart one
    int $unbound->{port} == 53 ? $_ : join ':', $_, $unbound->{port}
  } @{ $unbound->{address} };

  $unbound->{nameserver} = [ @nameserver ];

  $unbound->{monit}{enabled}  //= 0;
  $unbound->{monit}{address}  ||= $unbound->{address}[0];
  $unbound->{monit}{port}     ||= $unbound->{port};
  $unbound->{monit}{timeout}  ||= 10;

  inspect $unbound if Rex::Malta::DEBUG;

  set 'unbound' => $unbound;
};

task 'setup' => sub {
  return unless my $unbound = config;

  pkg [ qw/unbound/ ], ensure => 'present';

  file "/etc/default/unbound", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.unbound" );

  file "/etc/unbound/unbound.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/unbound.conf" );

  my $conf = $unbound->{conf};

  for my $name ( keys %$conf ) {
    my $enabled = $conf->{ $name };

    if ( $enabled ) {
      file "/etc/unbound/unbound.conf.d/$name.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/unbound.conf.$name" );
    }

    else {
      unlink "/etc/unbound/unbound.conf.d/$name.conf";
    }
  }

  service 'unbound', ensure => "started";
  service 'unbound' => "restart" if $unbound->{restart};

  if ( $unbound->{resolver} ) {
    file "/etc/resolv.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/resolv.conf.unbound" );
  }

  if ( is_dir "/etc/monit" ) {
    file "/etc/monit/conf-available/unbound", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.unbound" );

    if ( $unbound->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/unbound",
        "/etc/monit/conf-enabled/unbound";
    }

    else {
      unlink "/etc/monit/conf-enabled/unbound";
    }
  }
};

task 'clean' => sub {
  return unless my $unbound = config;

  file [ "/etc/resolvconf" ], ensure => 'absent';
};

task 'remove' => sub {
  my $unbound = config -force;

  pkg [ qw/unbound/ ], ensure => 'absent';

  file [
    "/etc/default/unbound",
    "/etc/unbound",
    "/var/lib/unbound",
    "/etc/monit/conf-available/unbound",
    "/etc/monit/conf-enabled/unbound",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $unbound = config -force;

  run 'unbound_status', timeout => 10,
    command => "/usr/sbin/service unbound status";

  say "Unbound service status:\n", last_command_output;
};

1;
