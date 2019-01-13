package Rex::Malta::Unbound;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'unbound', { };
  return unless $config->{active} or $force;

  my $unbound = {
    active      => $config->{active}    // 0,
    address     => $config->{address}   || "127.0.0.1",
    port        => $config->{port}      || 53,
    allowed     => $config->{allowed}   || "127.0.0.0/8",
    conf        => $config->{conf}      || { },
    monit       => $config->{monit}     || { },
  };

  for ( qw/address allowed/ ) {
    $unbound->{ $_ } = [ $unbound->{ $_ } ]
      unless ref $unbound->{ $_ } eq 'ARRAY';
  }

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

  for my $name ( keys %{ $unbound->{conf} } ) {
    my $conf = $unbound->{conf}{ $name };

    $conf->{enabled}  //= 0;
    $conf->{name}     ||= $name;

    set conf => $conf;

    if ( $conf->{enabled} ) {
      file "/etc/unbound/unbound.conf.d/$conf->{name}.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/unbound.conf.$name" );
    }

    else {
      file "/etc/unbound/unbound.conf.d/$conf->{name}.conf", ensure => 'absent';
    }
  }

  service 'unbound', ensure => 'started';
  service 'unbound' => 'restart';

  if ( is_installed 'monit' ) {
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
  
    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $unbound = config;

  file [ "/etc/resolvconf" ], ensure => 'absent';
};

task 'remove' => sub {
  my $unbound = config -force;

  pkg [ qw/unbound/ ], ensure => 'absent';

  file [ qw{
    /etc/default/unbound
    /etc/unbound
    /var/lib/unbound
  } ], ensure => 'absent';

  if ( is_installed 'monit' ) {
    file [ qw{
      /etc/monit/conf-available/unbound
      /etc/monit/conf-enabled/unbound
    } ], ensure => 'absent';

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $unbound = config -force;

  run 'unbound_status',
    command => "/usr/sbin/service unbound status";

  say last_command_output;
};

1;
