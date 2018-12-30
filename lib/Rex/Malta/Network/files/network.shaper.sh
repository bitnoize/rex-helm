#!/bin/bash

#set -x

LINK_HASH=$( printf "%x" <%= $network->{shaper}{link}[0] %> )
LINK_RATE="<%= $network->{shaper}{link}[1] %>"
LINK_CEIL="<%= $network->{shaper}{link}[2] %>"

MAIN_HASH=$( printf "%x" <%= $network->{shaper}{main}[0] %> )
MAIN_RATE="<%= $network->{shaper}{main}[1] %>"
MAIN_CEIL="<%= $network->{shaper}{main}[2] %>"

MISC_HASH=$( printf "%x" <%= $network->{shaper}{misc}[0] %> )
MISC_RATE="<%= $network->{shaper}{misc}[1] %>"
MISC_CEIL="<%= $network->{shaper}{misc}[2] %>"

usage() {
  echo "Usage: $0 -e egress_iface -i ingress_iface COMMAND" >&2

  exit 1;
}

shaper_egress() {
  [[ "$IFACE_ETH" =~ ^eth[0-9]$ ]] || usage

  # Primary discipline with default class
  tc qdisc replace dev $IFACE_ETH root handle 1: htb default $MISC_HASH

  # Primary class with link bandwidth
  tc class replace dev $IFACE_ETH parent 1: classid 1:$LINK_HASH htb \
    rate $LINK_RATE ceil $LINK_CEIL

  # Class for priority server traffic
  tc class replace dev $IFACE_ETH parent 1:$LINK_HASH classid 1:$MAIN_HASH htb \
    rate $MAIN_RATE ceil $MAIN_CEIL prio 1

  # TODO

  # All other traffic class
  tc class replace dev $IFACE_ETH parent 1:$LINK_HASH classid 1:$MISC_HASH htb \
    rate $MISC_RATE ceil $MISC_CEIL prio 9

  # Configure Stochastic Fairness
  tc qdisc replace dev $IFACE_ETH parent 1:$MAIN_HASH handle $MAIN_HASH: sfq perturb 10
  tc qdisc replace dev $IFACE_ETH parent 1:$MISC_HASH handle $MISC_HASH: sfq perturb 10

  # Root filter
  tc filter replace dev $IFACE_ETH parent 1: protocol ip u32
}

shaper_ingress() {
  [[ "$IFACE_IFB" =~ ^ifb[0-9]$ ]] || usage

  ip link set dev $IFACE_IFB up
  ip link set dev $IFACE_IFB qlen 30

  # Mirroring ingress eth to egress ifb
  tc qdisc replace dev $IFACE_ETH handle ffff: ingress
  tc filter replace dev $IFACE_ETH parent ffff: protocol ip u32 \
    match u32 0 0 action mirred egress redirect dev $IFACE_IFB

  # Primary discipline with default class
  tc qdisc replace dev $IFACE_IFB root handle 1: htb default $MISC_HASH

  # Primary class with link bandwidth
  tc class replace dev $IFACE_IFB parent 1: classid 1:$LINK_HASH htb \
    rate $LINK_RATE ceil $LINK_CEIL

  # Class for priority server traffic
  tc class replace dev $IFACE_IFB parent 1:$LINK_HASH classid 1:$MAIN_HASH htb \
    rate $MAIN_RATE ceil $MAIN_CEIL prio 1

  # TODO

  # All other traffic class
  tc class replace dev $IFACE_IFB parent 1:$LINK_HASH classid 1:$MISC_HASH htb \
    rate $MISC_RATE ceil $MISC_CEIL prio 9

  # Configure Stochastic Fairness
  tc qdisc replace dev $IFACE_IFB parent 1:$MAIN_HASH handle $MAIN_HASH: sfq perturb 10
  tc qdisc replace dev $IFACE_IFB parent 1:$MISC_HASH handle $MISC_HASH: sfq perturb 10

  # Root filter
  tc filter replace dev $IFACE_IFB parent 1: protocol ip u32
}

shaper_down() {
  tc qdisc del dev $IFACE_ETH root &> /dev/null
  tc qdisc del dev $IFACE_ETH handle ffff: ingress &> /dev/null

  tc qdisc del dev $IFACE_IFB root &> /dev/null

  ip link set dev $IFACE_IFB down
}

while getopts ":e:i:" opt; do
  case "$opt" in
    e)
      IFACE_ETH="$OPTARG"
      ;;

    i)
      IFACE_IFB="$OPTARG"
      ;;

    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;

    :)
      echo "Option -$OPTARG requires an argument" >&2
      exit 1
      ;;

  esac
done

shift $(( OPTIND-1 ))

# Only root can to this job
[[ "$EUID" -eq 0 ]] || exit 2

case "$1" in
  up)
    shaper_down
    shaper_egress
    shaper_ingress
    ;;

  down)
    shaper_down
    ;;

  *)
    usage
    ;;

esac

exit 0
