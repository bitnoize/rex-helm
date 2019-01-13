package Rex::Malta::Postfix;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'postfix', { };
  return unless $config->{active} or $force;

  my $postfix = {
    active      => $config->{active}    // 0,
    monit       => $config->{monit}     || { },
  };

  $postfix->{monit}{enabled}  //= 0;
  $postfix->{monit}{address}  ||= "127.0.0.1";
  $postfix->{monit}{port}     ||= 25;
  $postfix->{monit}{timeout}  ||= 10;

  inspect $postfix if Rex::Malta::DEBUG;

  set 'postfix' => $postfix;
};

task 'setup' => sub {
  return unless my $postfix = config;

  pkg [ qw/postfix/ ], ensure => 'present';

  Rex::Logger::info( "There is no Postfix configuration yet" => 'warn' );

  service 'postfix', ensure => 'started';
  service 'postfix' => 'restart';
};

task 'clean' => sub {
  return unless my $postfix = config;

};

task 'remove' => sub {
  my $postfix = config -force;

  pkg [ qw/postfix/ ], ensure => 'absent';
};

task 'status' => sub {
  my $postfix = config -force;

  run 'postfix_status',
    command => "/usr/sbin/service postfix status";

  say last_command_output;
};

1;
