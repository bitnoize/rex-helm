package Rex::Malta::Nginx;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( nginx => @_ );

  my $nginx = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
    confs       => $config->{confs}     // [ ],
    snippets    => $config->{snippets}  // [ ],
    secrets     => $config->{secrets}   // [ ],
    sites       => $config->{sites}     // { },
  };

  inspect $nginx if Rex::Malta::DEBUG;

  set 'nginx' => $nginx;
};

task 'setup' => sub {
  return unless my $nginx = config;

  pkg [ qw/nginx/ ], ensure => 'present';

  file "/etc/default/nginx", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "\@default.nginx" );

  file [ "/etc/nginx" ], ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/nginx/nginx.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/nginx.conf" );

  file "/etc/nginx/dhparam.pem", ensure => 'present',
    owner => 'root', group => 'www-data', mode => 640,
    source => "files/nginx.dhparam.pem";

  my $confs = $nginx->{confs};

  for my $name ( @$confs ) {
    file "/etc/nginx/conf.d/$name.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      source => "files/nginx.conf.$name";
  }

  my $snippets = $nginx->{snippets};

  for my $name ( @$snippets ) {
    file "/etc/nginx/snippets/$name.conf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      source => "files/nginx.snippet.$name";
  }

  my $secrets = $nginx->{secrets};

  for my $name ( @$secrets ) {
    file "/etc/nginx/$name.secrets", ensure => 'present',
      owner => 'root', group => 'www-data', mode => 640,
      source => "files/nginx.secrets.$name";
  }

  file [ "/var/www/default" ], ensure => 'directory',
    owner => 'root', group => 'www-data', mode => 755;

  my $sites = $nginx->{sites};

  for my $name ( keys %$sites ) {
    my $site = $sites->{ $name };

    $site->{enabled}  //= 0;
    $site->{domain}   //= [ "_" ];
    $site->{address}  //= [ "127.0.0.1" ];
    $site->{port}     //= 80;
    $site->{sslport}  //= 443;
    $site->{cert}     //= '';

    set site => $site;

    file "/etc/nginx/sites-available/$name", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/nginx.site.$name" );

    if ( $site->{enabled} ) {
      symlink "/etc/nginx/sites-available/$name",
        "/etc/nginx/sites-enabled/$name";
    }

    else {
      unlink "/etc/nginx/sites-enabled/$name";
    }

    if ( $site->{cert} ) {
      file "/etc/ssl/certs/$site->{cert}.crt", ensure => 'present',
        owner => 'root', group => 'www-data', mode => 644,
        source => "files/nginx.cert.$site->{cert}.crt";

      file "/etc/ssl/private/$site->{cert}.key", ensure => 'present',
        owner => 'root', group => 'www-data', mode => 640,
        source => "files/nginx.cert.$site->{cert}.key";
    }
  }

  service 'nginx', ensure => "started";
  service 'nginx' => "restart" if $nginx->{restart};

  file "/var/www/default/index.html", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/nginx.index.html" );

  file "/etc/logrotate.d/nginx", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/logrotate.conf.nginx" );
};

task 'clean' => sub {
  return unless my $nginx = config;

  file [
    "/etc/nginx/secrets", "/etc/nginx/secret",
    "/etc/nginx/confs", "/etc/nginx/auths", "/etc/nginx/certs",
    "/etc/nginx/fastcgi.conf", "/var/www/html",
    "/etc/nginx/koi-win", "/etc/nginx/koi-utf", "/etc/nginx/win-utf"
  ], ensure => 'absent';

  service 'nginx' => "restart" if $nginx->{restart};
};

task 'remove' => sub {
  my $nginx = config -force;

  pkg [ qw/nginx/ ], ensure => 'absent';

  file [
    "/etc/logrotate.d/nginx",
    "/var/cache/nginx", "/var/log/nginx",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $nginx = config -force;

  run 'nginx_status', timeout => 10,
    command => "/usr/sbin/service nginx status";

  say "Nginx service status:\n", last_command_output;
};

1;

__DATA__

@default.nginx
# Set the ulimit variable if you need defaults to change
#ULIMIT="-n 4096"

# Define the stop schedule for nginx
#STOP_SCHEDULE="QUIT/5/TERM/5/KILL/5"
@end

