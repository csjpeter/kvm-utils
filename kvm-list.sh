#!/bin/bash
#
# kvm-list.sh - List KVM virtual machines
#

set -o pipefail

MYDIR="$(dirname "$(readlink -f "$0")")"
source "$MYDIR/kvm-include.sh"

print_help() {
    cat <<EOF
This script lists all KVM virtual machines on the specified remote server.

Usage: $0 <remote> [OPTIONS]

Options:
  -h, --help     Show this help message and exit

EOF
}

function parse_args()
{
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -h|--help)
                shift
                print_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                exit 1
                ;;
        esac
    done
}

function list_vms()
{
    sudo virsh list --all
    if [ $? -ne 0 ]; then
        log_error "Failed to list virtual machines."
        return 1
    fi
}

function main()
{
    parse_args "$@"
    if [ $? -ne 0 ]; then
        log_error "Failed to parse arguments."
        exit 1
    fi

    list_vms
    if [ $? -ne 0 ]; then
        log_error "Failed to list VMs on remote server."
        exit 1
    fi
}

main "$@"

