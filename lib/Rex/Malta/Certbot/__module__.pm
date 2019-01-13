package Rex::Malta::Certbot;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'certbot', { };
  return unless $config->{active} or $force;

  my $certbot = {
    active      => $config->{active}    // 0,
    options     => $config->{options}   || "--agree-tos",
    certs       => $config->{certs}     || { },
  };

  inspect $certbot if Rex::Malta::DEBUG;

  set 'certbot' => $certbot;
};

task 'setup' => sub {
  return unless my $certbot = config;

  pkg [ qw/certbot/ ], ensure => 'present';

  for my $name ( keys %{ $certbot->{certs} } ) {
    my $cert = $certbot->{certs}{ $name };

    $cert->{enabled}  //= 0;
    $cert->{name}     ||= $name;
    $cert->{options}  ||= "";
    $cert->{domain}   ||= [ ];

    $cert->{domain} = [ $cert->{domain} ]
      unless ref $cert->{domain} eq 'ARRAY';

    set 'certificate' => $cert;

    if ( $cert->{enabled} ) {
      die "Malformed Certbot '$name' domain\n" unless @{ $cert->{domain} };

      run 'certbot_certonly', timeout => 60,
        command => template( "\@certbot_certonly" );

      say last_command_output if $?;
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

  run 'certbot_certificates', timeout => 60,
    command => template( "\@certbot_certificates" );

  say last_command_output;
};

1;

__DATA__

@certbot_certonly
/usr/bin/certbot certonly \
  -n --cert-name <%= $certificate->{name} %> \
  <%= $certificate->{options} %> <%= $certbot->{options} %> \
  <%= join " ", map { "-d $_" } @{ $certificate->{domain} } %>
@end

@certbot_certificates
/usr/bin/certbot certificates
@end

