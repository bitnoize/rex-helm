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
    certs       => $config->{certs}     || { },
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
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/nginx.dhparam.pem" );

  for my $name ( keys %{ $nginx->{conf} } ) {
    my $conf = $nginx->{conf}{ $name };

    $conf->{enabled}    //= 0;
    $conf->{name}       ||= $name;

    set 'conf' => $conf;

    if ( $conf->{enabled} ) {
      file "/etc/nginx/conf.d/$conf->{name}.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/nginx.conf.$name" );
    }

    else {
      file "/etc/nginx/conf.d/$conf->{name}.conf", ensure => 'absent';
    }
  }

  for my $name ( keys %{ $nginx->{snippets} } ) {
    my $snippet = $nginx->{snippets}{ $name };

    $snippet->{enabled}   //= 0;
    $snippet->{name}      ||= $name;

    set 'snippet' => $snippet;

    if ( $snippet->{enabled} ) {
      file "/etc/nginx/snippets/$snippet->{name}.conf", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/nginx.snippet.$name" );
    }

    else {
      file "/etc/nginx/snippets/$snippet->{name}.conf", ensure => 'absent';
    }
  }

  my ( @secrets, @certs );

  for my $name ( keys %{ $nginx->{secrets} } ) {
    my $secret = $nginx->{secrets}{ $name };

    $secret->{enabled}  //= 0;
    $secret->{name}     ||= $name;
    $secret->{source}   ||= 'native';

    set 'secret' => $secret;

    case $secret->{source}, {
      native => sub {
        if ( $secret->{enabled} ) {
          file "/etc/nginx/$secret->{name}.secrets", ensure => 'present',
            owner => 'root', group => 'www-data', mode => 640,
            content => template( "files/nginx.secrets.$name" );

          push @secrets, $name;
        }

        else {
          file "/etc/nginx/$secret->{name}.secrets", ensure => 'absent';
        }
      },

      default => sub {
        die "Unknown Nginx secret source\n";
      }
    }
  }

  for my $name ( keys %{ $nginx->{certs} } ) {
    my $cert = $nginx->{certs}{ $name };

    $cert->{enabled}    //= 0;
    $cert->{name}       ||= $name;
    $cert->{source}     ||= 'native';

    set 'certificate' => $cert;

    case $cert->{source}, {
      native => sub {
        if ( $cert->{enabled} ) {
          file "/etc/ssl/certs/$cert->{name}.crt", ensure => 'present',
            owner => 'root', group => 'www-data', mode => 644,
            source => "files/nginx.cert.$name.crt";
     
          file "/etc/ssl/private/$cert->{name}.key", ensure => 'present',
            owner => 'root', group => 'www-data', mode => 640,
            source => "files/nginx.cert.$name.key";

          push @certs, $name;
        }

        else {
          file "/etc/ssl/certs/$cert->{name}.crt", ensure => 'absent';
          file "/etc/ssl/private/$cert->{name}.key", ensure => 'absent';
        }
      },

      certbot => sub {
        if ( $cert->{enabled} ) {
          push @certs, $name if is_dir "/etc/letsencrypt/live/$cert->{name}";
        }
      },

      default => sub {
        die "Unknown Nginx certificate source\n";
      }
    }
  }

  file "/var/www/default", ensure => 'directory',
    owner => 'root', group => 'www-data', mode => 755;

  for my $name ( keys %{ $nginx->{sites} } ) {
    my $site = $nginx->{sites}{ $name };

    $site->{enabled}    //= 0;
    $site->{name}       ||= $name;
    $site->{domain}     ||= "\"\"";
    $site->{address}    ||= "127.0.0.1";
    $site->{port}       ||= 80;
    $site->{ssl_port}   ||= 443;
    $site->{secret}     ||= "";
    $site->{cert}       ||= "";

    for ( qw/domain address/ ) {
      $site->{ $_ } = [ $site->{ $_ } ]
        unless ref $site->{ $_ } eq 'ARRAY';
    }

    set 'site' => $site;

    if ( $site->{enabled} ) {
      Rex::Logger::info( "Install Nginx site '$site->{name}'" );

      file "/etc/nginx/sites-available/$site->{name}", ensure => 'present',
        owner => 'root', group => 'root', mode => 644,
        content => template( "files/nginx.site.$name" );

      my $site_ready = 1;

      if ( $site->{secret} ) {
        unless ( grep { $_ eq $site->{secret} } @secrets ) {
          Rex::Logger::info( "Nginx secret $site->{secret} not ready" => 'warn' );

          $site_ready = 0;
        }
      }

      if ( $site->{cert} ) {
        unless ( grep { $_ eq $site->{cert} } @certs ) {
          Rex::Logger::info( "Nginx cert $site->{cert} not ready" => 'warn' );

          $site_ready = 0;
        }
      }

      if ( $site_ready ) {
        symlink "/etc/nginx/sites-available/$site->{name}",
          "/etc/nginx/sites-enabled/$site->{name}";
      }

      else {
        unlink "/etc/nginx/sites-enabled/$site->{name}";
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

  run 'nginx_status',
    command => "/usr/sbin/service nginx status";

  say last_command_output;
};

1;
