#!/bin/bash

set -o pipefail

MYDIR=$(dirname "$(readlink -f "$0")")

source "$MYDIR/kvm-include.sh"

VM_NAME=""

declare -A ETHERNET_IFC_ON_IMAGE=(
    ["ubuntu22"]="enp1s0"
    ["ubuntu24"]="enp1s0"
)

print_help()
{
    cat <<EOF
This script removes a KVM virtual machine by libvirt.

Usage: $0 <name>

Arguments:
    <name>                 Name of the virtual machine

EOF
}

function delete_vm()
{
    # Check if the VM exists
    if ! sudo virsh dominfo ${VM_NAME} &>/dev/null; then
        log_warning "Virtual machine ${VM_NAME} does not exist"
        return 0
    fi

    # Check if the VM is running
    if sudo virsh domstate ${VM_NAME} | grep -q "running"; then
        log_info "Stopping virtual machine ${VM_NAME}"
        sudo virsh destroy ${VM_NAME}
        if [ $? -ne 0 ]; then
            log_error "Failed to stop virtual machine ${VM_NAME}"
            return 1
        fi
    fi

    sudo virsh undefine ${VM_NAME}
    if [ $? -ne 0 ]; then
        log_error "Failed to undefine virtual machine ${VM_NAME}"
        return 1
    fi

    sudo virsh vol-delete --pool images ${VM_NAME}.qcow2
    if [ $? -ne 0 ]; then
        log_error "Failed to delete virtual machine ${VM_NAME} volume"
        return 1
    fi

    log_info "Removing ${VM_NAME} from /etc/hosts."
    sudo sed -i "/ ${VM_NAME}$/d" /etc/hosts
    if [ $? -ne 0 ]; then
        log_error "Failed to remove ${VM_NAME} from /etc/hosts."
        return 1
    fi
}

function parse_args()
{
    # No argument is specified
    if [ "$#" -eq 0 ]; then
        print_help
        if [ -x virsh ]; then
            log_info "No action specified. Listing all virtual machines."
            sudo virsh list --all
        fi
        return 1
    fi

    # Help requested
    if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        print_help
        return 0
    fi

    # No enough arguments
    if [ "$#" -lt 1 ]; then
        log_error "Invalid number of arguments"
    fi

    # Argument 1 is the machine name
    VM_NAME=$1
    shift
    if [ "$VM_NAME" == "" ]; then
        log_error "Virtual machine name is required"
        return 1
    fi
    log_info "Virtual machine name: $VM_NAME"
}

function main()
{
    parse_args "$@"
    if [ $? -ne 0 ]; then
        return 1
    fi
    delete_vm ${VM_NAME}
    if [ $? -ne 0 ]; then
        return 1
    fi
}

main "$@"
