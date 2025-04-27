#!/bin/bash

set -euo pipefail

MYDIR=$(dirname "$(readlink -f "$0")")

source "$MYDIR/kvm-include.sh"

print_help()
{
    cat <<EOF
Usage: $0 [OPTIONS]

This script manages KVM networks using libvirt.
It can create, destroy, and list networks.

Actions:
    define                   Define and start a new network
    undefine                 Destroy and undefine an existing network
    redefine                 Destroy and redefine a network
    help                     Show this help message and exit

EOF
}

main()
{
    if [ "$#" -eq 0 ]; then
        print_help
        log_info "No action specified. Listing all networks."
        sudo virsh net-list --all
        log_info "Listing network interfaces."
        sudo virsh iface-list --all
        return 1
    fi

    local action="$1"
    shift
    case "$action" in
        "")
            ;;
        define)
            ${MYDIR}/kvm-net-define.sh "$@"
            return $?
            ;;
        undefine)
            ${MYDIR}/kvm-net-undefine.sh "$@"
            return $?
            ;;
        redefine)
            if [ "$#" -gt 1 ]; then
                ${MYDIR}/kvm-net-undefine.sh "$1" "$2"
                if [ $? -ne 0 ]; then
                    return 1
                fi
            else
                ${MYDIR}/kvm-net-undefine.sh help
                return 1
            fi
            ${MYDIR}/kvm-net-define.sh "$@"
            return $?
            ;;
        help)
            print_help
            return 0
            ;;
        *)
            log_error "Unknown action: $action"
            return 1
            ;;
    esac
}

main "$@"
