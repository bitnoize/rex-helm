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

  my @cert = map { split qr/:/, $_, 3 } $first;
  return unless $cert[0] and $cert[1] and $cert[2];

  my $cert = { name => $cert[0], path_crt => $cert[1], path_key => $cert[2] };

  set 'certificate' => $cert;
}

task 'setup' => sub {
  return unless my $pki = config;

  pkg [ qw/certbot ssl-cert/ ], ensure => 'present';

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
        $cert->{path_crt} = "/etc/letsencrypt/live/$cert->{name}/fullchain.pem";
        $cert->{path_key} = "/etc/letsencrypt/live/$cert->{name}/privkey.pem";

        if ( $cert->{enabled} ) {
          run 'certbot_certonly', timeout => 60, auto_die => FALSE,
            command => template( "\@certbot_certonly" );

          unless ( $? ) {
            append_or_amend_line "/etc/certificates",
              line => join( ':', @$cert{ qw/name path_crt path_key/ } ),
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
        $cert->{path_crt} = "/etc/ssl/certs/$cert->{name}.crt";
        $cert->{path_key} = "/etc/ssl/private/$cert->{name}.key";

        if ( $cert->{enabled} ) {
          file $cert->{path_crt}, ensure => 'present',
            owner => 'root', group => 'www-data', mode => 644,
            source => "files/certificate.$name.crt";

          file $cert->{path_key}, ensure => 'present',
            owner => 'root', group => 'www-data', mode => 640,
            source => "files/certificate.$name.key";

          append_or_amend_line "/etc/certificates",
            line => join( ':', @$cert{ qw/name path_crt path_key/ } ),
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

@certbot_certonly
[ <%= scalar @{ $certificate->{domain} } %> -gt 0 ] || exit 10

/usr/bin/certbot certonly -n \
  --cert-name <%= $certificate->{name} %> <%= $certificate->{options} %> \
  <%= join " ", map { "-d $_" } @{ $certificate->{domain} } %>
@end

@certbot_delete
/usr/bin/certbot delete -n --cert-name <%= $certificate->{name} %>
@end

@certbot_certificates
/usr/bin/certbot certificates
@end

