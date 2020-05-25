package Rex::Helm::PKI;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'pki', { };
  return unless $config->{active} or $force;

  my $pki = {
    active      => $config->{active}  // FALSE,
    legacy      => $config->{legacy}  // FALSE,
    options     => $config->{options} || "",
    certs       => $config->{certs}   || { },
  };

  inspect $pki if Rex::Helm::DEBUG;

  set 'pki' => $pki;
}

sub certificate {
  my ( $name ) = @_;

  return unless $name and is_readable "/etc/certificates";

  my @lines = grep { $_ !~ /^\s*(#.*)?$/ }
    split qr/\n/, cat( "/etc/certificates" ) || "";

  my ( $first ) = grep { $_ =~ qr/^$name/ } @lines;
  return unless $first;

  my @cert = map { split qr/:/, $_, 4 } $first;
  return unless $cert[0] and $cert[1] and $cert[2] and $cert[3];

  my $cert = {
    name        => $cert[0],
    path_crt    => $cert[1],
    path_key    => $cert[2],
    path_chain  => $cert[3]
  };

  set 'certificate' => $cert;
}

task 'setup' => sub {
  return unless my $pki = config;

  pkg [ qw/ssl-cert/ ], ensure => 'present';

  if ($pki->{legacy}) {
    pkg [ qw/certbot/ ], ensure => 'absent';

    run 'certbot_legacy', timeout => 300, auto_die => TRUE,
      command => template( "\@certbot_legacy" );
  }

  else {
    pkg [ qw/certbot/ ], ensure => 'present';
  }

  file "/etc/cron.d/certbot", ensure => 'present',
    owner => 'root', group => 'root', mode => 755,
    content => template( "files/crontab.certbot" );

  file "/etc/certificates", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/certificates" ),
    no_overwrite => 1;

  for my $name ( keys %{ $pki->{certs} } ) {
    my $cert = $pki->{certs}{ $name };

    $cert->{enabled}  //= FALSE;
    $cert->{name}     ||= $name;
    $cert->{source}   ||= 'ssl-cert';
    $cert->{options}  ||= $pki->{options};
    $cert->{domain}   ||= [ ];

    $cert->{domain} = [ $cert->{domain} ]
      unless ref $cert->{domain} eq 'ARRAY';

    set 'certificate' => $cert;

    case $cert->{source}, {
      'certbot' => sub {
        $cert->{path_crt}   = "/etc/letsencrypt/live/$cert->{name}/fullchain.pem";
        $cert->{path_key}   = "/etc/letsencrypt/live/$cert->{name}/privkey.pem";
        $cert->{path_chain} = "/etc/letsencrypt/live/$cert->{name}/chain.pem";

        if ( $cert->{enabled} ) {
          run 'certbot_certonly', timeout => 60, auto_die => FALSE,
            command => template( "\@certbot_certonly" );

          unless ( $? ) {
            append_or_amend_line "/etc/certificates",
              line => join( ':', @$cert{ qw/name path_crt path_key path_chain/ } ),
              regexp => qr/^$cert->{name}/;
          }

          else {
            Rex::Logger::info( "PKI certbot certonly exit code: $?" => 'error' );
            say last_command_output;

            delete_lines_matching "/etc/certificates", matching => qr/^$cert->{name}/;
          }
        }

        else {
          run 'certbot_delete', timeout => 60, auto_die => FALSE,
            command => template( "\@certbot_delete" );

          delete_lines_matching "/etc/certificates", matching => qr/^$cert->{name}/;
        }
      },

      'ssl-cert' => sub {
        $cert->{path_crt}   = "/etc/ssl/certs/$cert->{name}.crt";
        $cert->{path_key}   = "/etc/ssl/private/$cert->{name}.key";
        $cert->{path_chain} = "/etc/ssl/certs/ca-certificates.crt";

        if ( $cert->{enabled} ) {
          file $cert->{path_crt}, ensure => 'present',
            owner => 'root', group => 'www-data', mode => 644,
            source => "files/certificate.$name.crt";

          file $cert->{path_key}, ensure => 'present',
            owner => 'root', group => 'www-data', mode => 640,
            source => "files/certificate.$name.key";

          append_or_amend_line "/etc/certificates",
            line => join( ':', @$cert{ qw/name path_crt path_key path_chain/ } ),
            regexp => qr/^$cert->{name}/;
        }

        else {
          file [
            "/etc/ssl/certs/$cert->{name}.crt",
            "/etc/ssl/private/$cert->{name}.key",
          ], ensure => 'absent';

          delete_lines_matching "/etc/certificates", matching => qr/^$cert->{name}/;
        }
      },

      'default' => sub { die "PKI cert has unknown source\n" }
    }
  }
};

task 'clean' => sub {
  return unless my $certbot = config;

};

task 'remove' => sub {
  my $certbot = config -force;

  pkg [ qw/certbot/ ], ensure => 'absent';
};

task 'status' => sub {
  my $certbot = config -force;

  run 'certbot_certificates',
    command => template( "\@certbot_certificates" );

  say last_command_output;
};

1;

__DATA__

@certbot_legacy
curl -q "https://dl.eff.org/certbot-auto" > /usr/local/bin/certbot
chmod 755 /usr/local/bin/certbot
certbot -n --os-packages-only
certbot -n --install-only
@end

@certbot_certonly
[ <%= scalar @{ $certificate->{domain} } %> -gt 0 ] || exit 10

certbot certonly -n \
  --cert-name <%= $certificate->{name} %> <%= $certificate->{options} %> \
  <%= join " ", map { "-d $_" } @{ $certificate->{domain} } %>
@end

@certbot_delete
certbot delete -n --cert-name <%= $certificate->{name} %>
@end

@certbot_certificates
certbot certificates
@end

