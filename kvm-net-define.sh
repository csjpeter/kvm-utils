#!/bin/bash

set -o pipefail

MYDIR=$(dirname "$(readlink -f "$0")")

source "$MYDIR/kvm-include.sh"

print_help()
{
    cat <<EOF
This script defines and starts a libvirt network with NAT.

Usage: $0 <network_name> <CIDR>

Arguments:
    <network_name>          Name of the libvirt network
    <CIDR>                  Network in CIDR notation (e.g., 192.168.122.0/24)

Options:
    --bridge-name=<name>    Specify a custom bridge name (default: virbr<network_name>)

Example:
    $0 virbr0 default 192.168.122.0/24

EOF
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

generate_network_xml()
{
    local xml_file="$1"
    local bridge_name="$2"
    local network_name="$3"
    local network_cidr="$4"

    local cidr_bits=${network_cidr##*/}
    cidr_to_netmask "$cidr_bits"
    local netmask=${RETURNED_NETMASK}

    IFS='.' read -r o1 o2 o3 _ <<< "$network_cidr"
    local ip_prefix="${o1}.${o2}.${o3}."

    local gateway_ip="${ip_prefix}1"
    local dhcp_start="${ip_prefix}2"
    local dhcp_end="${ip_prefix}30"
    ip_to_mac "$gateway_ip"
    local gateway_mac=${RETURNED_MAC}

    cat > "$xml_file" <<EOF
<network>
  <name>${network_name}</name>
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

main()
{
    # No argument is specified
    if [ "$#" -eq 0 ]; then
        print_help
        log_info "No action specified. Listing all networks."
        sudo virsh net-list --all
        log_info "Listing network interfaces."
        sudo virsh iface-list --all
        return 1
    fi

    # Help requested
    if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        print_help
        return 0
    fi

    # No enough arguments
    if [ "$#" -lt 2 ]; then
        log_error "Invalid number of arguments"
    fi

    # Argument 1 is the network name
    local network_name=$1
    shift
    if [ "$network_name" == "" ]; then
        log_error "Network name is required"
        return 1
    fi
    log_info "Network name: $network_name"

    # Argument 2 is the network CIDR
    local network_cidr=$1
    shift
    if [ "$network_cidr" == "" ]; then
        log_error "Network CIDR is required"
        return 1
    fi
    log_info "Network CIDR: $network_cidr"

    # Options
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --bridge-name=*)
                local bridge_name="${1#--bridge-name=}"
                if [ "$bridge_name" == "" ]; then
                    log_error "Bridge name cannot be empty"
                    return 1
                fi
                shift
                ;;
            --debug)
                shift
                log_info "Debug mode enabled"
                export DEBUG=yes
                set -x
                trap 'set +x' EXIT
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done

    # Ensuring having a bridge name
    if [ "$bridge_name" == "" ]; then
        local bridge_name="virbr${network_name}"
    fi
    log_info "Bridge name: $bridge_name"

    #
    # Main logic
    #

    if ! sudo virsh net-list --all | grep -w "$network_name" &>/dev/null; then
        local tmp_xml=$(mktemp)
        trap 'rm -f "$tmp_xml"' EXIT

        generate_network_xml "$tmp_xml" "$bridge_name" "$network_name" "$network_cidr"
        cat $tmp_xml

        log_debug "Defining network $network_name"
        sudo virsh net-define "$tmp_xml"
        if [ $? -ne 0 ]; then
            log_error "Failed to define network $network_name"
            return 1
        fi

        log_debug "Starting network $network_name"
        sudo virsh net-autostart "$network_name"
        if [ $? -ne 0 ]; then
            log_error "Failed to set network $network_name to autostart"
            return 1
        fi

        if sudo virsh net-list --all | grep -w "$network_name" | grep -w "inactive" &>/dev/null; then
            log_debug "Starting network $network_name"
            sudo virsh net-start "$network_name"
            if [ $? -ne 0 ]; then
                log_error "Failed to start network $network_name"
                return 1
            fi
        fi
    fi
}

main "$@"
