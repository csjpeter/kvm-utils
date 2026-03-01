#!/bin/bash
#
# kvm-setup.sh - Basic KVM/libvirt setup script for Rocky Linux 9
#

set -o pipefail

MYDIR="$(dirname "$(readlink -f "$0")")"

source "$MYDIR/kvm-include.sh"

print_help() {
    cat <<EOF
This script installs and configures KVM and libvirt for virtualization.

Usage: $0 <action> [OPTIONS]

Actions:
  sure            Yes, do install KVM and libvirt

Options:
  -h, --help     Show this help message and exit

EOF
}

function install_kvm()
{
    log_info "Installing KVM and libvirt packages..."

    sudo dnf install -y --nobest qemu-kvm libvirt bridge-utils virt-install virt-viewer libvirt-daemon-kvm xorriso cloud-init guestfs-tools
    if [ $? -ne 0 ]; then
        log_error "Failed to install KVM and libvirt packages."
        return 1
    fi

    log_info "Enabling and starting libvirtd service..."

    sudo systemctl enable --now libvirtd
    if [ $? -ne 0 ]; then
        log_error "Failed to enable and start libvirtd service."
        return 1
    fi

    log_info "Checking KVM hardware support..."

    if grep -qE '(vmx|svm)' /proc/cpuinfo; then
        log_info "KVM hardware acceleration is supported."
    else
        log_warning "No KVM hardware acceleration detected. VMs may run very slowly."
    fi

    log_info "Setup completed."
}

main()
{
    if [ "$#" -eq 0 ]; then
        print_help
        return 1
    fi

    local action="$1"
    shift
    case "$action" in
        sure)
            install_kvm "$@"
            return $?
            ;;
        -h|--help|help)
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

