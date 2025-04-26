#!/bin/bash

set -euo pipefail

# Color codes
RED='\033[0;31m'
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Logging functions
log_info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*"; }

print_help()
{
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
  --name <network-name>     Name of the libvirt network
  --network <CIDR>          Network in CIDR notation (e.g., 192.168.122.0/24)
  -h, --help                Show this help message and exit

Example:
  $0 --name default --network 192.168.122.0/24
EOF
}

ip_to_mac()
{
    local ip="$1"
    IFS='.' read -r a b c d <<< "$ip"
    export RETURNED_MAC=$(printf '52:54:%02X:%02X:%02X:%02X' $a $b $c $d)
}

cidr_to_netmask()
{
    local cidr_bits=$1
    local mask=""
    local full_octets=$(( cidr_bits / 8 ))
    local partial_bits=$(( cidr_bits % 8 ))

    if [ "$partial_bits" -ne 0 ]; then
        log_fail "CIDR bits must be devisible by 8"
        return 1
    fi


    for ((i=0; i<4; i++)); do
        if [ "$i" -lt "$full_octets" ]; then
            mask+="255"
        else
            mask+="0"
        fi
        [ "$i" -lt 3 ] && mask+="."
    done
    export RETURNED_NETMASK="$mask"
}

destroy_existing_network()
{
    if virsh net-info "$NETWORK_NAME" &>/dev/null; then
        echo "Destroying and undefining existing network: $NETWORK_NAME"
        virsh net-destroy "$NETWORK_NAME" || true
        virsh net-undefine "$NETWORK_NAME"
    fi
}

generate_network_xml()
{
    local xml_file="$1"
    local bridge_name="virbr${NETWORK_NAME}"

    local network_ip=${NETWORK_CIDR%%/*}
    local cidr_bits=${NETWORK_CIDR##*/}
    cidr_to_netmask "$cidr_bits"
    local netmask=${RETURNED_NETMASK}

    IFS='.' read -r o1 o2 o3 _ <<< "$network_ip"
    local ip_prefix="${o1}.${o2}.${o3}."

    local gateway_ip="${ip_prefix}1"
    local dhcp_start="${ip_prefix}2"
    local dhcp_end="${ip_prefix}30"
    ip_to_mac "$gateway_ip"
    local gateway_mac=${RETURNED_MAC}

    cat > "$xml_file" <<EOF
<network>
  <name>${NETWORK_NAME}</name>
  <forward mode='nat'>
    <nat>
      <port start='1024' end='65535'/>
    </nat>
  </forward>
  <bridge name='${bridge_name}' stp='on' delay='0'/>
  <mac address='${gateway_mac}'/>
  <ip address='${gateway_ip}' netmask='${netmask}'>
    <dhcp>
      <range start='${dhcp_start}' end='${dhcp_end}'/>
EOF

    for i in $(seq 2 30); do
        local ip="${ip_prefix}$i"
        ip_to_mac $ip
        echo "      <host mac='${RETURNED_MAC}' name='kvm${i}' ip='${ip}'/>" >> "$xml_file"
    done

    cat >> "$xml_file" <<EOF
    </dhcp>
  </ip>
</network>
EOF
}

define_and_start_network()
{
    local xml_file="$1"
    log_info "Defining new network: $NETWORK_NAME"
    virsh net-define "$xml_file"
    virsh net-autostart "$NETWORK_NAME"
    sudo virsh net-start "$NETWORK_NAME"
}

main()
{
    if [ $# -eq 0 ]; then
        print_help
        exit 1
    fi

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --name)
                NETWORK_NAME="$2"
                shift 2
                ;;
            --network)
                NETWORK_CIDR="$2"
                shift 2
                ;;
            -h|--help)
                print_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_help
                exit 1
                ;;
        esac
    done

    if [[ -z "${NETWORK_NAME:-}" || -z "${NETWORK_CIDR:-}" ]]; then
        log_error "Error: --name and --network are required."
        print_help
        exit 1
    fi

    tmp_xml=$(mktemp)
    trap 'rm -f "$tmp_xml"' EXIT

    generate_network_xml "$tmp_xml"
    cat $tmp_xml
    destroy_existing_network
    define_and_start_network "$tmp_xml"

    log_info "Network '$NETWORK_NAME' configured and started successfully."
}

main "$@"
