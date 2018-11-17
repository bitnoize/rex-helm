package Rex::Malta::RBLCheck;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  return unless my $config = Rex::Malta::config( rblcheck => @_ );

  my $rblcheck = {
    active      => $config->{active}    // 0,
    hosts       => $config->{hosts}     || [ qw/127.0.0.1/ ],
    lists       => $config->{lists}     || [ qw/zen.spamhaus.org/ ],
    monit       => $config->{monit}     || { },
  };

  $rblcheck->{monit}{enabled}  //= 0;
  $rblcheck->{monit}{timeout}  ||= 60;

  inspect $rblcheck if Rex::Malta::DEBUG;

  set 'rblcheck' => $rblcheck;
};

task 'setup' => sub {
  return unless my $rblcheck = config;

  pkg [ qw/rblcheck-ng/ ], ensure => 'present';

  Rex::Logger::info( "There are no RBL hosts defined" => 'warn' )
    unless @{ $rblcheck->{hosts} };

  Rex::Logger::info( "There are no RBL lists defined" => 'warn' )
    unless @{ $rblcheck->{lists} };

  file "/etc/rblcheck/hosts.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/rblcheck.conf.hosts" );

  file "/etc/rblcheck/lists.conf", ensure => 'present',
    owner => 'root', group => 'root', mode => 644,
    content => template( "files/rblcheck.conf.lists" );

  if ( is_dir "/etc/monit" ) {
    file "/etc/monit/conf-available/rblcheck", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.rblcheck" );

    if ( $rblcheck->{monit}{enabled} ) {
      symlink "/etc/monit/conf-available/rblcheck",
        "/etc/monit/conf-enabled/rblcheck";
    }

    else {
      unlink "/etc/monit/conf-enabled/rblcheck";
    }
  }
};

task 'clean' => sub {
  return unless my $rblcheck = config;

  pkg [ qw/rblcheck/ ], ensure => 'absent';

  file [
    "/usr/local/bin/rblcheck",
    "/etc/rblcheck/rbls.conf",
    "/etc/rblcheck/rbls.conf.dpkg-dist",
    "/etc/rblcheck/hosts.conf.dpkg-dist",
    "/etc/rblcheck/lists.conf.dpkg-dist",
  ], ensure => 'absent';
};

task 'remove' => sub {
  my $rblcheck = config -force;

  pkg [ qw/rblcheck-ng/ ], ensure => "absent";

  file [
    "/etc/rblcheck",
    "/etc/monit/conf-available/rblcheck",
    "/etc/monit/conf-enabled/rblcheck",
  ], ensure => 'absent';
};

task 'status' => sub {
  my $rblcheck = config -force;

  run 'rblcheck', timeout => 60,
    command => "rblcheck";

  say "RBLCheck status:\n", last_command_output;
};

1;
