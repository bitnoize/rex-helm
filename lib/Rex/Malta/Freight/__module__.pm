package Rex::Malta::Freight;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'freight', { };
  return unless $config->{active} or $force;

  my $freight = {
    active      => $config->{active}    // 0,
    libdir      => $config->{libdir}    || "/var/lib/freight",
    cachedir    => $config->{cachedir}  || "/var/www/freight",
    origin      => $config->{origin}    || "extradebs",
    label       => $config->{label}     || "Extradebs",
    gpgkey      => $config->{gpgkey}    || "build\@extradebs",
  };

  inspect $freight if Rex::Malta::DEBUG;

  set 'freight' => $freight;
};

task 'setup' => sub {
  return unless my $freight = config;

  pkg [ qw/freight/ ], ensure => 'present';

  file [
    $freight->{libdir}, $freight->{cachedir},
  ], ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/freight.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/freight.conf" );

  file "/var/www/freight", ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;
};

task 'clean' => sub {
  return unless my $freight = config;

  file [ "/etc/freight.conf.example" ], ensure => 'absent',
};

task 'remove' => sub {
  my $freight = config -force;

  pkg [ qw/freight/ ], ensure => 'absent';

  # Do NOT remove /var/lib/freight

  file [
    "/etc/freight.conf", "/var/www/freight"
  ], ensure => 'absent';
};

task 'status' => sub {
  my $freight = config -force;

};

1;
