package Rex::Malta::MMonit;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

use constant DISTRIB => "https://mmonit.com/dist/mmonit-%s-%s.tar.gz";
use constant ARCHIVE => "/tmp/mmonit-%s-%s.tar.gz";
use constant SCRAPPY => "/tmp/mmonit-%s";

sub config {
  return unless my $config = Rex::Malta::config( mmonit => @_ );

  my $mmonit = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    platform    => $config->{platform}  // "linux-x64",
    version     => $config->{version}   // "3.7.1",
    workdir     => $config->{workdir}   // "/opt/mmonit",
    address     => $config->{address}   // "0.0.0.0",
    port        => $config->{port}      // "3127",
    schema      => $config->{schema}    // "mysql://monit:monit\@127.0.0.1/mmonit",
    owner       => $config->{owner}     // "Unknown",
    license     => $config->{license}   // "none",
  };

  $mmonit->{distrib} = sprintf DISTRIB, @$mmonit{ qw/version platform/ };
  $mmonit->{archive} = sprintf ARCHIVE, @$mmonit{ qw/version platform/ };
  $mmonit->{scrappy} = sprintf SCRAPPY, $mmonit->{version};

  $mmonit->{cert} = "$mmonit->{workdir}/conf/mmonit.pem";

  inspect $mmonit if Rex::Malta::DEBUG;

  set 'mmonit' => $mmonit;
};

task 'setup' => sub {
  return unless my $mmonit = config;

  #pkg [ qw/mysql-client php5-mysql/ ], ensure => 'present';

  unless ( get_gid "mmonit" ) {
    create_group "mmonit", system => 1;
  }

  unless ( get_uid "mmonit" ) {
    create_user "mmonit",
      home => $mmonit->{workdir}, no_create_home => 1,
      groups => [ "mmonit" ], system => 1, shell => "/bin/false",
      comment => "mmonit";
  }

  run 'mmonit_install', timeout => 900,
    command => template( "\@mmonit_install" );

  file "/root/mmonit.log", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => last_command_output;

  file "/etc/security/limits.d/mmonit.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@mmonit.limits.conf" );

  file "/etc/tmpfiles.d/mmonit.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@tmpfiles.mmonit" );

  run 'systemd_tmpfiles', timeout => 10,
    command => "systemd-tmpfiles --create /etc/tmpfiles.d/mmonit.conf";

  file "/etc/systemd/system/mmonit.service", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@mmonit.service" ),
    on_change => sub {
      run 'systemd_restart', timeout => 10,
        command => "systemctl daemon-reload";
    };

  file "$mmonit->{workdir}/conf/server.xml", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/mmonit.conf.server" );

  file "$mmonit->{workdir}/conf/mmonit.pem", ensure => 'present',
    owner => 'mmonit', group => 'mmonit', mode => 600,
    source => "files/mmonit.pem";

  service 'mmonit', ensure => "started";
  service 'mmonit' => "restart" if $mmonit->{restart};
};

task 'clean' => sub {
  return unless my $mmonit = config;

};

task 'remove' => sub {
  my $mmonit = config -force;

# run "kill_mmonit", timeout => 10,
#   command => template( "\@kill_mmonit" );

  delete_user  "mmonit" if get_uid "mmonit";
  delete_group "mmonit" if get_gid "mmonit";

  run 'systemd_tmpfiles', timeout => 10,
    command => "systemd-tmpfiles --remove /etc/tmpfiles.d/mmonit.conf";

  file [ "/etc/systemd/system/mmonit.service" ], ensure => 'absent',
    on_change => sub {
      run 'systemd_restart', timeout => 10,
        command => "systemctl daemon-reload";
    };

  file [ $mmonit->{workdir} ], ensure => 'absent';

  file [
    "/etc/security/limits.d/mmonit.conf",
    "/etc/tmpfiles.d/mmonit.conf", "/root/mmonit.state"
  ], ensure => 'absent';
};

task 'status' => sub {
  my $mmonit = config -force;

  run 'mmonit_status', timeout => 10,
    command => "/usr/sbin/service mmonit status";

  say "MMonit service status:\n", last_command_output;
};

1;

__DATA__

@mmonit_install
[ -f "/root/mmonit.state" ] && exit 100

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

@mmonit.limits.conf
mmonit hard core 100000
@end

@tmpfiles.mmonit
d /run/mmonit 755 mmonit mmonit - -
@end

@mmonit.service
[Unit]
Description=Easy, proactive monitoring of Unix systems
After=network.target

[Service]
User=mmonit
Group=mmonit
WorkingDirectory=<%= $mmonit->{workdir} %>
ExecStart=<%= $mmonit->{workdir} %>/bin/mmonit -i -p /run/mmonit
ExecStop=<%= $mmonit->{workdir} %>/bin/mmonit -p /run/mmonit stop
PIDFile=/run/mmonit/mmonit.pid

[Install]
WantedBy=multi-user.target
@end

@kill_mmonit
/usr/bin/killall -9 --user mmonit
@end
