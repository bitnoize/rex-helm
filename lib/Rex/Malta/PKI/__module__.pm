package Rex::Malta::PKI;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'pki', { };
  return unless $config->{active} or $force;

  my $pki = {
    active      => $config->{active}  // 0,
    options     => $config->{options} || "",
    certs       => $config->{certs}   || { },
  };

  inspect $pki if Rex::Malta::DEBUG;

  set 'pki' => $pki;
}

sub certificate {
  my ( $name ) = @_;

  return unless $name;

  my @lines = grep { $_ !~ /^\s*(#.*)?$/ }
    split qr/\n/, cat "/etc/certificates";

  my ( $first ) = grep { $_ =~ qr/^$name/ } @lines;
  return unless my @cert = map { split qr/:/, $_, 3 } $first;
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

    $cert->{enabled}  //= 0;
    $cert->{name}     ||= $name;
    $cert->{source}   ||= "";
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
          die "PKI cert '$name' malformed options\n"  unless $cert->{options};
          die "PKI cert '$name' malformed domain\n"   unless @{ $cert->{domain} };

          run 'certbot_certonly', timeout => 60,
            command => template( "\@certbot_certonly" );

          unless ( $? ) {
            append_or_amend_line "/etc/certificates",
              line => join( ':', $name, @$cert{ qw/path_crt path_key/ } ),
              regexp => qr/^$name/;
          }

          else {
            Rex::Logger::info( "PKI cert '$name' certbot failed: $?" => 'error' );

            if ( Rex::Malta::DEBUG ) {
              say template( "\@certbot_certonly" );
              say last_command_output;
            }

            delete_lines_matching "/etc/certificates", matching => qr/^$name/;
          }
        }

        else {
          run 'certbot_delete', timeout => 60,
            command => template( "\@certbot_delete" );

          delete_lines_matching "/etc/certificates", matching => qr/^$name/;
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
        }

        else {
          file [
            "/etc/ssl/certs/$cert->{name}.crt",
            "/etc/ssl/private/$cert->{name}.key",
          ], ensure => 'absent';
        }
      },

      'default' => sub {
        die "PKI cert '$name' unknown source '$cert->{source}'\n";
      }
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

