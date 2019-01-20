package Rex::Helm::Iperf;

use strict;
use warnings;

use Rex -feature => [ '1.4' ];

sub config {
  my ( $force ) = @_;

  my $config = param_lookup 'iperf', { };
  return unless $config->{active} or $force;

  my $iperf = {
    active      => $config->{active}    // FALSE,
    server      => $config->{server}    // FALSE,
    address     => $config->{address}   || "0.0.0.0",
    port        => $config->{port}      || 5281,
    targets     => $config->{targets}   || [ ],
    monit       => $config->{monit}     || { },
  };

  $iperf->{monit}{enabled}  //= 0;
  $iperf->{monit}{timeout}  ||= 10;

  inspect $iperf if Rex::Helm::DEBUG;

  set 'iperf' => $iperf;
};

task 'setup' => sub {
  return unless my $iperf = config;

  pkg [ qw/iperf/ ], ensure => 'present';

  file [ "/etc/iperf", "/var/lib/iperf" ], ensure => 'directory',
    owner => 'root', group => 'nogroup', mode => 755;

  file "/etc/iperf/targets.conf", ensure => 'present',
    owner => 'root', group => 'nogroup', mode => 644,
    content => template( "files/iperf.conf.targets" );

  if ( $iperf->{server} ) {
    file "/etc/default/iperf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/default.iperf" );

    file "/etc/systemd/system/iperf.service", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/iperf.service" ),
      on_change => sub {
        run 'systemd_restart', command => "/bin/systemctl daemon-reload";
      };

    service 'iperf', ensure => 'started';
    service 'iperf' => 'restart';

    Rex::Logger::info( "Iperf configured as server" => 'info' );
  }

  else {
    file [
      "/etc/default/iperf",
      "/etc/systemd/system/iperf.service",
    ], ensure => 'absent';

    run 'systemd_restart', command => "/bin/systemctl daemon-reload";
  }

  file "/usr/local/bin/speedtest", ensure => 'present',
    owner => 'root', group => 'root', mode => 755,
    content => template( "\@speedtest" );

  file "/usr/local/bin/speedtest.run", ensure => 'present',
    owner => 'root', group => 'root', mode => 755,
    content => template( "\@speedtest.run" );

  if ( is_installed 'monit' ) {
    file "/etc/monit/conf-available/iperf", ensure => 'present',
      owner => 'root', group => 'root', mode => 644,
      content => template( "files/monit.conf.iperf" );

    if ( $iperf->{monit}{enabled} and $iperf->{server} ) {
      symlink "/etc/monit/conf-available/iperf",
        "/etc/monit/conf-enabled/iperf";
    }

    else {
      unlink "/etc/monit/conf-enabled/iperf";
    }

    service 'monit' => 'restart';
  }
};

task 'clean' => sub {
  return unless my $iperf = config;

};

task 'remove' => sub {
  my $iperf = config -force;

  pkg [ qw/iperf/ ], ensure => 'absent';

  # Do NOT remove /var/lib/iperf

  file [ qw{
    /etc/default/iperf
    /etc/iperf
    /etc/systemd/system/iperf.service
    /usr/local/bin/speedtest
    /usr/local/bin/speedtest.run
  } ], ensure => 'absent';

  run 'systemd_restart', command => "/bin/systemctl daemon-reload";

  if ( is_installed 'monit' ) {
    file [ qw{
      /etc/monit/conf-available/iperf
      /etc/monit/conf-enabled/iperf
    } ], ensure => 'absent';

    service 'monit' => 'restart';
  }
};

task 'speedtest' => sub {
  return unless my $iperf = config;

  run 'speedtest', timeout => 3600, auto_die => TRUE,
    command => "/usr/local/bin/speedtest";
};

task 'status' => sub {
  my $iperf = config -force;

  return say "There is no iperf data found"
    unless is_readable( "/var/lib/iperf/last" );

  my $map = [
    { id => 0, format => "%-10s", field => "Time"      },
    { id => 1, format => "%-8s",  field => "Name"      },
    { id => 2, format => "%-16s", field => "Address"   },
    { id => 3, format => "%-5s",  field => "Port"      },
    { id => 6, format => "%-10s", field => "Bandwidth" },
  ];

  my $last = file_read "/var/lib/iperf/last";

  Rex::Helm::table( $map, ":", $last->read_all );
};

task 'fetch' => sub {
  my $iperf = config -force;

  my $save = "/tmp/iperf";

  LOCAL { rmdir $save; mkdir $save };

  map { download "/var/lib/iperf/$_", $save }
    grep { /\d+/ } list_files "/var/lib/iperf";
};

1;

__DATA__

@speedtest
#!/bin/bash

#
# Run speedtest each target host
#

set -e

IPERF_TARGETS="${IPERF_TARGETS:-/etc/iperf/targets.conf}"
IPERF_STORAGE="${IPERF_STORAGE:-/var/lib/iperf}"

[ -f $IPERF_TARGETS ] || exit 10
[ -d $IPERF_STORAGE ] || exit 20

[ -x "$( which speedtest.run )" ] || exit 10

# Round-up to 16 minutes
stamp="$( date +%s )"
(( stamp /= 1000, stamp *= 1000 ))

rm -f "$IPERF_STORAGE/$stamp" "$IPERF_STORAGE/last";

while read -r target; do
  # Skip empty lines and comments
  [[ -z "$target" || "$target" =~ ^#.*$ ]] && continue

  # Skip self IP addresses
  address=$( echo "$target" | egrep -o '([0-9]{1,3}\.){3}[0-9]{1,3}' )
  [[ $( hostname -I ) =~ "$address" ]] && continue

  # Process target test
  echo "$target" | speedtest.run >> "$IPERF_STORAGE/$stamp"
done < "$IPERF_TARGETS"

ln -sf "$IPERF_STORAGE/$stamp" "$IPERF_STORAGE/last"
find "$IPERF_STORAGE" -mtime +7 -type f -delete

exit 0
@end

@speedtest.run
#!/usr/bin/env perl

#
# Execute and parse output
#

use v5.16;
use strict;
use warnings;

sub parse {
  my ( $name, $output ) = @_;
  return unless $output;

  my @output = split ",", $output;

  my $address   = $output[3] || "0.0.0.0";
  my $port      = $output[4] || 0;
  my $interval  = $output[6] || 0;
  my $transfer  = sprintf "%.2f", ( int $output[7] || 0 ) / 1024 / 1024;
  my $bandwidth = sprintf "%.2f", ( int $output[8] || 0 ) / 1024 / 1024;

  say join ":", time, $name,
    $address, $port, 5, $transfer, $bandwidth;
}

while ( my $target = <> ) {
  chomp $target; next unless $target;

	my ( $name, $address, $port ) = split ":", $target;
	next unless $name and $address and $port;

  parse( $name, `/usr/bin/iperf -c $address -p $port -t 5 -y C` );
}

exit 0;
@end

