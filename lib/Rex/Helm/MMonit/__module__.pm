package Rex::Helm::MMonit;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

use constant DISTRIB => "https://mmonit.com/dist/mmonit-%s-%s.tar.gz";
use constant ARCHIVE => "/tmp/mmonit-%s-%s.tar.gz";
use constant SCRAPPY => "/tmp/mmonit-%s";

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'mmonit', { };
  return unless $config->{active} or $force;

  my $mmonit = {
    active      => $config->{active}    // FALSE,
    platform    => $config->{platform}  || "linux-x64",
    version     => $config->{version}   || "3.7.2",
    workdir     => $config->{workdir}   || "/opt/mmonit",
    address     => $config->{address}   || "0.0.0.0",
    port        => $config->{port}      || "3127",
    cert        => $config->{cert}      || undef,
    schema      => $config->{schema}    || "postgresql://monit:monit\@127.0.0.1/mmonit",
    owner       => $config->{owner}     || "Unknown",
    license     => $config->{license}   || "none",
  };

  $mmonit->{distrib} = sprintf DISTRIB, @$mmonit{ qw/version platform/ };
  $mmonit->{archive} = sprintf ARCHIVE, @$mmonit{ qw/version platform/ };
  $mmonit->{scrappy} = sprintf SCRAPPY, $mmonit->{version};

  inspect $mmonit if Rex::Helm::DEBUG;

  set 'mmonit' => $mmonit;
};

task 'setup' => sub {
  return unless my $mmonit = config;

  my $cert = Rex::Helm::PKI::certificate( $mmonit->{cert} );
  return Rex::Logger::info( "MMonit cert is not ready" => 'warn' ) unless $cert;

  unless ( get_gid 'mmonit' ) {
    create_group 'mmonit', system => 1;
  }

  unless ( get_uid 'mmonit' ) {
    create_user 'mmonit',
      home => $mmonit->{workdir}, no_create_home => 1,
      groups => [ 'mmonit' ], system => 1, shell => "/bin/false",
      comment => "mmonit";
  }

  file "/etc/tmpfiles.d/mmonit.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/tmpfiles.mmonit" );

  run 'tmpfiles_create', command => template( "\@tmpfiles_create" );

  file "/etc/systemd/system/mmonit.service", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/mmonit.service" ),
    on_change => sub {
      run 'systemd_reload',
        command => "/bin/systemctl daemon-reload";
    };

  run 'mmonit_install', timeout => 300, auto_die => TRUE,
    command => template( "\@mmonit_install" );

  $mmonit->{path_fullcert}    = "$mmonit->{workdir}/conf/mmonit.pem";
  $mmonit->{path_conf_server} = "$mmonit->{workdir}/conf/server.xml";

  my $fullcert = join "\n",
    cat( $cert->{path_crt} ), cat( $cert->{path_key} );

  file $mmonit->{path_fullcert}, ensure => 'present',
    owner => 'mmonit', group => 'mmonit', mode => 600,
    content => $fullcert;

  file "$mmonit->{path_conf_server}", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/mmonit.conf.server" );

  service 'mmonit', ensure => 'started';
  service 'mmonit' => 'restart';
};

task 'clean' => sub {
  return unless my $mmonit = config;

  file [ qw{
    /etc/security/limits.d/mmonit.conf
    /root/mmonit.log
  } ], ensure => 'absent';
};

task 'remove' => sub {
  my $mmonit = config -force;

  run "kill_mmonit", command => template( "\@kill_mmonit" );

  delete_user  'mmonit' if get_uid 'mmonit';
  delete_group 'mmonit' if get_gid 'mmonit';

  run 'tmpfiles_remove', command => template( "\@tmpfiles_remove" );

  file "/etc/systemd/system/mmonit.service", ensure => 'absent',
    on_change => sub {
      run 'systemd_reload',
        command => "/bin/systemctl daemon-reload";
    };

  file [ qw{
    /etc/security/limits.d/mmonit.conf
    /etc/tmpfiles.d/mmonit.conf
    /root/mmonit.state
  } ], ensure => 'absent';

  file $mmonit->{workdir}, ensure => 'absent';
};

task 'status' => sub {
  my $mmonit = config -force;

};

1;

__DATA__

@tmpfiles_create
/bin/systemd-tmpfiles --create "/etc/tmpfiles.d/mmonit.conf"
@end

@tmpfiles_remove
/bin/systemd-tmpfiles --remove "/etc/tmpfiles.d/mmonit.conf"
@end

@mmonit_install
[ -f "/root/mmonit.state" ] && exit 0

echo "Drop previous MMonit installation"
rm -rf \
  "<%= $mmonit->{workdir} %>" \
  "<%= $mmonit->{archive} %>" \
  "<%= $mmonit->{scrappy} %>"

echo "Downloading and installing MMonit"
curl -k -q "<%= $mmonit->{distrib} %>" > "<%= $mmonit->{archive} %>"

tar -xzf "<%= $mmonit->{archive} %>" \
  -C "$( dirname "<%= $mmonit->{scrappy} %>" )"

mv "<%= $mmonit->{scrappy} %>" "<%= $mmonit->{workdir} %>"

chmod +r "<%= $mmonit->{workdir} %>/conf/mmonit.pem"
chown -R mmonit:mmonit "<%= $mmonit->{workdir} %>/logs"

echo "Done MMonit install"
echo "$( date +%s )" > "/root/mmonit.state"
@end

@kill_mmonit
/usr/bin/killall -9 --user mmonit
@end

