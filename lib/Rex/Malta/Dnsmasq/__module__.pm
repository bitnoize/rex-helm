package Rex::Malta::Dnsmasq;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'dnsmasq', { };
  return unless $config->{active} or $force;

  my $dnsmasq = {
    active      => $config->{active}    // 0,
    interface   => $config->{interface} || "lo",
    address     => $config->{address}   || "127.0.0.1",
    port        => $config->{port}      || 53,
    upstream    => $config->{upstream}  || [ qw/8.8.8.8 8.8.4.4/ ],
    conf        => $config->{conf}      || { },
    monit       => $config->{monit}     || { },
  };

  for ( qw/interface address upstream/ ) {
    $dnsmasq->{ $_ } = [ $dnsmasq->{ $_ } ]
      unless ref $dnsmasq->{ $_ } eq 'ARRAY';
  }

  my @nameserver = map {
    # Add port number only if non standart one
    int $dnsmasq->{port} == 53 ? $_ : join ':', $_, $dnsmasq->{port}
  } @{ $dnsmasq->{address} };

  $dnsmasq->{nameserver} = [ @nameserver ];

  $dnsmasq->{monit}{enabled}  //= 0;
  $dnsmasq->{monit}{address}  ||= $dnsmasq->{address}[0];
  $dnsmasq->{monit}{port}     ||= $dnsmasq->{port};
  $dnsmasq->{monit}{timeout}  ||= 10;

  inspect $dnsmasq if Rex::Malta::DEBUG;

  set 'dnsmasq' => $dnsmasq;
};

task 'setup' => sub {
  return unless my $dnsmasq = config;

  pkg [ qw/dnsmasq/ ], ensure => 'present';

  file "/etc/default/dnsmasq", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.dnsmasq" );

  file "/etc/dnsmasq.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/dnsmasq.conf" );

  my $conf = $dnsmasq->{conf};

  for my $name ( keys %$conf ) {
    my $enabled = $conf->{ $name };

    if ( $enabled ) {
      file "/etc/dnsmasq.d/$name", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/dnsmasq.conf.$name" );
    }

    else {
      unlink "/etc/dnsmasq.d/$name";
    }
  }

  service 'dnsmasq', ensure => 'started';
  service 'dnsmasq' => 'restart';

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/dnsmasq", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.dnsmasq" );

    if ( $dnsmasq->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/dnsmasq",
        "/etc/monit/conf-enabled/dnsmasq";
    }

    else {
      unlink "/etc/monit/conf-enabled/dnsmasq";
    }

    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $dnsmasq = config;

};

task 'remove' => sub {
  my $dnsmasq = config -force;

  pkg [ qw/dnsmasq/ ], ensure => 'absent';

  file [ qq{
    /etc/default/dnsmasq
    /etc/dnsmasq.conf
    /etc/dnsmasq.d
  } ], ensure => 'absent';

  if ( is_installed 'monit' ) {
    file [ qq{
      /etc/monit/conf-available/dnsmasq
      /etc/monit/conf-enabled/dnsmasq
    } ], ensure => 'absent';

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $dnsmasq = config -force;

  run 'dnsmasq_status', timeout => 10,
    command => "/usr/sbin/service dnsmasq status";

  say "Dnsmasq service status:\n", last_command_output;
};

1;
