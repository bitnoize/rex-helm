package Rex::Malta::Nginx;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'nginx', { };
  return unless $config->{active} or $force;

  my $nginx = {
    active      => $config->{active}    // 0,
    conf        => $config->{conf}      || { },
    snippets    => $config->{snippets}  || { },
    secrets     => $config->{secrets}   || { },
    sites       => $config->{sites}     || { },
    monit       => $config->{monit}     || { },
  };

  $nginx->{monit}{enabled}  //= 0;
  $nginx->{monit}{address}  ||= "127.0.0.1";
  $nginx->{monit}{port}     ||= 80;
  $nginx->{monit}{timeout}  ||= 10;

  inspect $nginx if Rex::Malta::DEBUG;

  set 'nginx' => $nginx;
};

task 'setup' => sub {
  return unless my $nginx = config;

  pkg [ qw/nginx/ ], ensure => 'present';

  file "/etc/default/nginx", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.nginx" );

  file [ "/etc/nginx" ], ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/nginx/nginx.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/nginx.conf" );

  file "/etc/nginx/dhparam.pem", ensure => 'present',
    owner => 'root', group => 'www-data', mode => 640,
    source => "files/nginx.dhparam.pem";

  my $conf = $nginx->{conf};

  for my $name ( keys %$conf ) {
    my $enabled = $conf->{ $name };

    if ( $enabled ) {
      file "/etc/nginx/conf.d/$name.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        source => "files/nginx.conf.$name";
    }

    else {
      unlink "/etc/nginx/conf.d/$name.conf";
    }
  }

  my $snippets = $nginx->{snippets};

  for my $name ( keys %$snippets ) {
    my $enabled = $snippets->{ $name };

    if ( $enabled ) {
      file "/etc/nginx/snippets/$name.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        source => "files/nginx.snippet.$name";
    }

    else {
      unlink "/etc/nginx/snippets/$name.conf";
    }
  }

  my $secrets = $nginx->{secrets};

  for my $name ( keys %$secrets ) {
    my $enabled = $secrets->{ $name };

    if ( $enabled ) {
      file "/etc/nginx/$name.secrets", ensure => 'present',
        owner => 'root', group => 'www-data', mode => 640,
        source => "files/nginx.secrets.$name";
    }

    else {
      unlink "/etc/nginx/$name.secrets";
    }
  }

  file "/var/www/default", ensure => 'directory',
    owner => 'root', group => 'www-data', mode => 755;

  my $sites = $nginx->{sites};

  for my $name ( keys %$sites ) {
    my $site = $sites->{ $name };
    $site->{name} = $name;

    $site->{enabled}  //= 0;
    $site->{sample}   ||= "default";
    $site->{domain}   ||= "_";
    $site->{address}  ||= "127.0.0.1";
    $site->{port}     ||= 80;
    $site->{sslport}  ||= 443;
    $site->{cert}     ||= "";

    for ( qw/domain address/ ) {
      $site->{ $_ } = [ $site->{ $_ } ]
        unless ref $site->{ $_ } eq 'ARRAY';
    }

    set site => $site;

    file "/etc/nginx/sites-available/$name", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/nginx.site.$site->{sample}" );

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

  service 'nginx', ensure => 'started';
  service 'nginx' => 'restart';

  file "/var/www/default/index.html", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/nginx.index.html" );

  if ( is_installed 'logrotate' ) {
    file "/etc/logrotate.d/nginx", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/logrotate.conf.nginx" );
  }

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/nginx", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.nginx" );

    if ( $nginx->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/nginx",
        "/etc/monit/conf-enabled/nginx";
    }

    else {
      unlink "/etc/monit/conf-enabled/nginx";
    }

    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $nginx = config;

  file [ qq{
    /etc/nginx/secrets
    /etc/nginx/secret
    /etc/nginx/confs
    /etc/nginx/auths
    /etc/nginx/certs
    /etc/nginx/fastcgi.conf
    /etc/nginx/koi-win
    /etc/nginx/koi-utf
    /etc/nginx/win-utf
    /var/www/html
  } ], ensure => 'absent';

  service 'nginx' => 'restart';
};

task 'remove' => sub {
  my $nginx = config -force;

  pkg [
    qw/nginx nginx-full nginx-light nginx-extras/
  ], ensure => 'absent';

  file [ qw{
    /etc/default/nginx
    /etc/nginx
    /var/cache/nginx
    /var/log/nginx
    /etc/logrotate.d/nginx
    /etc/monit/conf-available/nginx
    /etc/monit/conf-enabled/nginx
  } ], ensure => 'absent';
};

task 'status' => sub {
  my $nginx = config -force;

  run 'nginx_status', timeout => 10,
    command => "/usr/sbin/service nginx status";

  say "Nginx service status:\n", last_command_output;
};

1;
