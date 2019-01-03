#!/bin/bash

#set -x

LINK_HASH=$( printf "%x" 1 )
LINK_RATE="<%= $network->{shaper}{link}[0] %>"
LINK_CEIL="<%= $network->{shaper}{link}[1] %>"

MAIN_HASH=$( printf "%x" 10 )
MAIN_RATE="<%= $network->{shaper}{main}[0] %>"
MAIN_CEIL="<%= $network->{shaper}{main}[1] %>"

MISC_HASH=$( printf "%x" 90 )
MISC_RATE="<%= $network->{shaper}{misc}[0] %>"
MISC_CEIL="<%= $network->{shaper}{misc}[1] %>"

usage() {
  echo "Usage: $0 -e egress_iface -i ingress_iface COMMAND" >&2

  exit 1;
}

shaper_up() {
  #
  # Egress traffic
  #

  # Primary discipline with default class
  tc qdisc replace dev "$IFACE_ETH" root handle 1: htb default "$MISC_HASH"

  # Primary class with link bandwidth
  tc class replace dev "$IFACE_ETH" parent 1: \
    classid "1:${LINK_HASH}" htb rate "$LINK_RATE" ceil "$LINK_CEIL"

  # Class for priority server traffic
  tc class replace dev "$IFACE_ETH" parent "1:${LINK_HASH}" \
    classid "1:${MAIN_HASH}" htb rate "$MAIN_RATE" ceil "$MAIN_CEIL" prio 1

  # All other traffic class
  tc class replace dev "$IFACE_ETH" parent "1:${LINK_HASH}" \
    classid "1:${MISC_HASH}" htb rate "$MISC_RATE" ceil "$MISC_CEIL" prio 9

  # Configure Stochastic Fairness
  tc qdisc replace dev "$IFACE_ETH" parent "1:${MAIN_HASH}" \
   handle "${MAIN_HASH}:" sfq perturb 10

  tc qdisc replace dev "$IFACE_ETH" parent "1:${MISC_HASH}" \
    handle "${MISC_HASH}:" sfq perturb 10

  # Root filter
  tc filter replace dev "$IFACE_ETH" parent 1: protocol ip u32

  # SSH
  tc filter replace dev "$IFACE_ETH" parent 1: protocol ip prio 10 u32 \
    match ip protocol 6 0xff match ip sport 22 0xffff flowid 1:10

  # HTTPS
  tc filter replace dev "$IFACE_ETH" parent 1: protocol ip prio 10 u32 \
    match ip protocol 6 0xff match ip sport 443 0xffff flowid 1:10

  #
  # Ingress traffic
  #

  ip link set dev "$IFACE_IFB" up
  ip link set dev "$IFACE_IFB" qlen 30

  # Mirroring ingress eth to egress ifb
  tc qdisc replace dev "$IFACE_ETH" handle ffff: ingress
  tc filter replace dev "$IFACE_ETH" parent ffff: protocol ip u32 \
    match u32 0 0 action mirred egress redirect dev "$IFACE_IFB"

  # Primary discipline with default class
  tc qdisc replace dev "$IFACE_IFB" root handle 1: htb default "$MISC_HASH"

  # Primary class with link bandwidth
  tc class replace dev "$IFACE_IFB" parent 1: \
    classid "1:${LINK_HASH}" htb rate "$LINK_RATE" ceil "$LINK_CEIL"

  # Class for priority server traffic
  tc class replace dev "$IFACE_IFB" parent "1:${LINK_HASH}" \
    classid "1:${MAIN_HASH}" htb rate "$MAIN_RATE" ceil "$MAIN_CEIL" prio 1

  # All other traffic class
  tc class replace dev "$IFACE_IFB" parent "1:${LINK_HASH}" \
    classid "1:${MISC_HASH}" htb rate "$MISC_RATE" ceil "$MISC_CEIL" prio 9

  # Configure Stochastic Fairness
  #tc qdisc replace dev "$IFACE_IFB" parent "1:${MAIN_HASH}" \
  # handle "${MAIN_HASH}:" sfq perturb 10

  tc qdisc replace dev "$IFACE_IFB" parent "1:${MISC_HASH}" \
    handle "${MISC_HASH}:" sfq perturb 10

  # Root filter
  tc filter replace dev "$IFACE_IFB" parent 1: protocol ip u32

  # SSH
  tc filter replace dev "$IFACE_ETH" parent 1: protocol ip prio 10 u32 \
    match ip protocol 6 0xff match ip dport 22 0xffff flowid 1:10

  # HTTPS
  tc filter replace dev "$IFACE_ETH" parent 1: protocol ip prio 10 u32 \
    match ip protocol 6 0xff match ip dport 443 0xffff flowid 1:10
}

shaper_down() {
  #
  # Egress traffic
  #

  tc qdisc del dev "$IFACE_ETH" root &> /dev/null

  #
  # Ingress traffic
  #

  tc qdisc del dev "$IFACE_ETH" handle ffff: ingress &> /dev/null

  tc qdisc del dev "$IFACE_IFB" root &> /dev/null

  ip link set dev "$IFACE_IFB" down
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
      echo "Invalid option: -${OPTARG}" >&2
      exit 1
      ;;

    :)
      echo "Option -${OPTARG} requires an argument" >&2
      exit 1
      ;;

  esac
done

shift $(( OPTIND-1 ))

[[ "$IFACE_ETH" =~ ^tun[0-9]$ ]] || usage
[[ "$IFACE_IFB" =~ ^ifb[0-9]$ ]] || usage

# Only root can to this job
[[ "$EUID" -eq 0 ]] || exit 2

COMMAND="$1"

case "$COMMAND" in
  up)
    shaper_down
    shaper_up
    ;;

  down)
    shaper_down
    ;;

  *)
    usage
    ;;

esac

exit 0
