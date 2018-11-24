package Rex::Malta::Gitweb;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $global = Rex::Malta::config( 'global' );
  my $config = Rex::Malta::config( 'gitweb' );

  return unless $force or $config->{active};

  my $gitweb = {
    active      => $config->{active}      // 0,
    projectroot => $config->{projectroot} || "/var/lib/git",
    site_name   => $config->{site_name}   || "Gitweb",
  };

  inspect $gitweb if Rex::Malta::DEBUG;

  set 'gitweb' => $gitweb;
};

task 'setup' => sub {
  return unless my $gitweb = config;

  pkg [ qw/gitweb fcgiwrap highlight/ ], ensure => 'present';

  file [ $gitweb->{projectroot} ], ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/gitweb.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/gitweb.conf" );
};

task 'clean' => sub {
  return unless my $gitweb = config;

  #file [ "/etc/apache2" ], ensure => 'absent';
};

task 'remove' => sub {
  my $gitweb = config -force;

  pkg [ qw/gitweb highlight/ ], ensure => 'absent';

  # Do NOT remove projectroot directory

  file [ "/etc/gitweb.conf", ], ensure => 'absent';
};

task 'status' => sub {
  my $gitweb = config -force;

};

1;
