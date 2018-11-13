package Rex::Malta::CollectdWeb;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

use Rex::Commands::SCM;

use constant DISTRIB => "https://github.com/httpdss/collectd-web.git";

sub config {
  return unless my $config = Rex::Malta::config( collectdweb => @_ );

  my $collectdweb = {
    active      => $config->{active}  // 0,
    distrib     => $config->{distrib} // DISTRIB,
    workdir     => $config->{workdir} // "/var/www/collectd-web",
  };

  inspect $collectdweb if Rex::Malta::DEBUG;

  set 'collectdweb' => $collectdweb;
};

task 'setup' => sub {
  return unless my $collectdweb = config;

  pkg [ qw/fcgiwrap/ ], ensure => 'present';

  pkg [
    qw/librrds-perl libconfig-general-perl libhtml-parser-perl/,
    qw/libregexp-common-perl liburi-perl libjson-perl libcgi-pm-perl/,
  ], ensure => 'present';

  set repository => "collectd-web", url => $collectdweb->{distrib};

  checkout "collectd-web", path => $collectdweb->{workdir};
};

task 'clean' => sub {
  return unless my $collectdweb = config;

};

task 'remove' => sub {
  my $collectdweb = config -force;

};

task 'status' => sub {
  my $collectdweb = config -force;

};

1;
