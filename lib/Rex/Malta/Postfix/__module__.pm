package Rex::Malta::Postfix;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( postfix => @_ );

  my $postfix = {
    active      => $config->{active}    // 0,
    restart     => $config->{restart}   // 1,
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

  service 'postfix', ensure => "started";
  service 'postfix' => "restart" if $postfix->{restart};
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

  run 'postfix_status', timeout => 10,
    command => "/usr/sbin/service postfix status";

  say "Postfix service status:\n", last_command_output;
};

1;
