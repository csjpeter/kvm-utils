#!/bin/bash

set -o pipefail

MYDIR=$(dirname "$(readlink -f "$0")")

source "$MYDIR/kvm-include.sh"

print_help()
{
    cat <<EOF
This script destroys and undefines a libvirt bridge network.

Usage: $0 <network_name>

Arguments:
    <network_name>          Name of the libvirt network

Options:
    --bridge-name=<name>    Specify a custom bridge name (default: virbr<network_name>)

Example:
    $0 virbr0 default

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

    # Help is requested
    if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        print_help
        return 0
    fi

    # No enough arguments
    if [ "$#" -lt 1 ]; then
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

    if sudo virsh net-list --all | grep -w "$network_name" > /dev/null; then
        if sudo virsh net-list --all | grep -w "$network_name" | grep -w "active" > /dev/null; then
            sudo virsh net-destroy "$network_name"
            if [ $? -ne 0 ]; then
                log_error "Failed to destroy network $network_name"
                return 1
            fi
        fi

        sudo virsh net-undefine "$network_name"
        if [ $? -ne 0 ]; then
            log_error "Failed to undefine network $network_name"
            return 1
        fi
    fi

    if sudo virsh iface-list --all | grep -w "$bridge_name" > /dev/null; then
        if sudo virsh iface-list --all | grep -w "$bridge_name" | grep -w "active" > /dev/null; then
            sudo virsh iface-destroy "$bridge_name"
            if [ $? -ne 0 ]; then
                log_error "Failed to destroy interface $bridge_name"
                return 1
            fi
        fi

        sudo virsh iface-unbridge "$bridge_name"
        if [ $? -ne 0 ]; then
            log_error "Failed to unbridge interface $bridge_name"
            return 1
        fi
    fi
}

main "$@"
