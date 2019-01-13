package Rex::Malta::Logrotate;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'logrotate', { };
  return unless $config->{active} or $force;

  my $logrotate = {
    active      => $config->{active}    // 0,
    confs       => $config->{confs}     || { },
  };

  inspect $logrotate if Rex::Malta::DEBUG;

  set logrotate => $logrotate;
}

task 'setup' => sub {
  return unless my $logrotate = config;

  pkg [ qw/logrotate/ ], ensure => 'present';

  file "/etc/logrotate.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/logrotate.conf" );

  for my $name ( keys %{ $logrotate->{confs} } ) {
    my $conf = $logrotate->{confs}{ $name };

    $conf->{enabled}  //= 0;
    $conf->{name}     ||= $name;

    set conf => $conf;

    if ( $conf->{enabled} ) {
      file "/etc/logrotate.d/$conf->{name}", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/logrotate.conf.$name" );
    }

    else {
      file "/etc/logrotate.d/$conf->{name}", ensure => 'absent';
    }
  }
};

task 'rotate' => sub {
  return unless my $logrotate = config;

  run 'logrotate_rotate', timeout => 60,
    command => "/usr/sbin/logrotate -f /etc/logrotate.conf";
};

task 'clean' => sub {
  return unless my $logrotate = config;

};

task 'remove' => sub {
  my $logrotate = config -force;

  # Do NOT remove logrotate
};

task 'status' => sub {
  my $logrotate = config -force;

};

1;
