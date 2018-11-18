# Rexfile

use Rex -feature => [ '1.4' ];
use Rex::CMDB;
use Rex::Group::Lookup::INI;

logging to_file => "rex.log";

# Execute tasks in parallel
parallelism 5;

#
# Keep configuration as simple as posible
#

set 'exec_autodie' => 1;

set 'cmdb' => {
  type => 'YAML',
  path => [
    "cmdb/{hostname}.yml",
    "cmdb/default.yml",
  ]
};

set 'path_map' => {
  "files/" => [
    "files/{hostname}/",
  ]
};

environment 'live' => sub {
  user "root";

  groups_file "cmdb/live.ini";
};

environment 'test' => sub {
  user "root";

  groups_file "cmdb/test.ini";
};

set 'modules' => [
  'System',     # Basic system stuff
  'Network',    # Network configuration
  'Firewall',   # Iptables rules
  'Shaper',     # Traffic control

  'Monit',      # Service monitoring
  'Collectd',   # Collect and visualize various metrics
  'Syslog',     # Syslog facility
  'Cron',       # Cron scheduler
  'OpenSSH',    # OpenSSH service
  'NTP',        # Network Time Protocol
  'Iperf',      # Network bandwidth test
  'QemuKVM',    # Virtualize environment on KVM

  'Dnsmasq',    # Dnsmasq daemon
  'Unbound',    # Unbound daemon
  'Nginx',      # Nginx fase web server
  'MySQL',      # MySQL service
  'Redis',      # Redis in-memory storage
  'Postfix',    # Postfix mailer

  'RBLCheck',   # RBLCheck script
  'Freight',    # Deb repositories for busy people
  'Rsync',      # Remote sync
  'MMonit',     # Monit combiner
  'CollectdWeb',# Collectd combiner
  'Gitweb',     # Gitweb service
];

require Rex::Malta;

1;
