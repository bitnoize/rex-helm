package Rex::Helm::Nginx;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'nginx', { };
  return unless $config->{active} or $force;

  my $nginx = {
    active      => $config->{active}    // FALSE,
    address     => $config->{address}   || "0.0.0.0",
    port        => $config->{port}      || 80,
    ssl_port    => $config->{ssl_port}  || 443,
    conf        => $config->{conf}      || { },
    snippets    => $config->{snippets}  || { },
    secrets     => $config->{secrets}   || { },
    sites       => $config->{sites}     || { },
    monit       => $config->{monit}     || { },
  };

  $nginx->{monit}{enabled}  //= FALSE;
  $nginx->{monit}{timeout}  ||= 10;

  inspect $nginx if Rex::Helm::DEBUG;

  set 'nginx' => $nginx;
};

task 'setup' => sub {
  return unless my $nginx = config;

  pkg [ qw/nginx/ ], ensure => 'present';

  file "/etc/default/nginx", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/default.nginx" );

  file "/etc/nginx", ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/nginx/conf.d", ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/nginx/snippets", ensure => 'directory',
    owner => 'root', group => 'root', mode => 755;

  file "/etc/nginx/secrets", ensure => 'directory',
    owner => 'root', group => 'www-data', mode => 750;

  file "/etc/nginx/certs", ensure => 'directory',
    owner => 'root', group => 'www-data', mode => 750;

  file "/etc/nginx/nginx.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/nginx.conf" );

  run 'openssl_dhparam', timeout => 3600, auto_die => TRUE,
    command => "/usr/bin/openssl dhparam -out /etc/nginx/certs/dhparam.pem 2048",
    unless => "test -f /etc/nginx/certs/dhparam.pem";

  for my $name ( keys %{ $nginx->{conf} } ) {
    my $enabled = $nginx->{conf}{ $name };

    if ( $enabled ) {
      file "/etc/nginx/conf.d/$name.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/nginx.conf.$name" );
    }

    else {
      file "/etc/nginx/conf.d/$name.conf", ensure => 'absent';
    }
  }

  for my $name ( keys %{ $nginx->{snippets} } ) {
    my $enabled = $nginx->{snippets}{ $name };

    if ( $enabled ) {
      file "/etc/nginx/snippets/$name.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/nginx.snippet.$name" );
    }

    else {
      file "/etc/nginx/snippets/$name.conf", ensure => 'absent';
    }
  }

  for my $name ( keys %{ $nginx->{secrets} } ) {
    my $enabled = $nginx->{secrets}{ $name };

    if ( $enabled ) {
      file "/etc/nginx/secrets/$name.passwd", ensure => 'present',
        owner => 'root', group => 'www-data', mode => 640,
        content => template( "files/nginx.secrets.$name" );
    }

    else {
      file "/etc/nginx/secrets/$name.passwd", ensure => 'absent';
    }
  }

  file "/var/www/default", ensure => 'directory',
    owner => 'root', group => 'www-data', mode => 755;

  for my $name ( keys %{ $nginx->{sites} } ) {
    my $site = $nginx->{sites}{ $name };

    $site->{enabled}    //= FALSE;
    $site->{name}       ||= $name;
    $site->{domain}     ||= "\"\"";
    $site->{address}    ||= $nginx->{address};
    $site->{port}       ||= $nginx->{port};
    $site->{ssl_port}   ||= $nginx->{ssl_port};
    $site->{cert}       ||= undef;

    for ( qw/domain address/ ) {
      $site->{ $_ } = [ $site->{ $_ } ]
        unless ref $site->{ $_ } eq 'ARRAY';
    }

    set 'site' => $site;

    if ( $site->{enabled} ) {
      file "/etc/nginx/sites-available/$site->{name}", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/nginx.site.$name" );

      my $site_ready = 1;

      if ( $site->{cert} ) {
        my $cert = Rex::Helm::PKI::certificate( $site->{cert} );

        if ( $cert ) {
          symlink $cert->{path_crt}, "/etc/nginx/certs/$site->{cert}.crt"
            unless is_readable "/etc/nginx/certs/$site->{cert}.crt";

          symlink $cert->{path_key}, "/etc/nginx/certs/$site->{cert}.key"
            unless is_readable "/etc/nginx/certs/$site->{cert}.key";
        }

        else { $site_ready = 0 }
      }

      if ( $site_ready ) {
        symlink "/etc/nginx/sites-available/$site->{name}",
          "/etc/nginx/sites-enabled/$site->{name}";

        Rex::Logger::info( "Nginx site '$site->{name}' successfully done" );
      }

      else {
        unlink "/etc/nginx/sites-enabled/$site->{name}";

        Rex::Logger::info( "Nginx site '$site->{name}' not ready" => 'warn' );
      }
    }

    else {
      file [
        "/etc/nginx/sites-available/$site->{name}",
        "/etc/nginx/sites-enabled/$site->{name}",
      ], ensure => 'absent';
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

  file [ qw{
    /etc/nginx/secret
    /etc/nginx/confs
    /etc/nginx/auths
    /etc/nginx/fastcgi.conf
    /etc/nginx/koi-win
    /etc/nginx/koi-utf
    /etc/nginx/win-utf
    /var/www/html
    /etc/nginx/dhparam.pem
    /etc/nginx/debs.secrets
    /etc/nginx/team.secrets
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
  } ], ensure => 'absent';

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/nginx", ensure => 'absent';
    unlink "/etc/monit/conf-enabled/nginx";

    service 'monit' => 'restart';
  }
};

task 'status' => sub {
  my $nginx = config -force;

};

1;
