#!/bin/bash
#
# kvm-setup.sh - Basic KVM/libvirt setup script for Rocky Linux 9
#

set -o pipefail

source kvm-include.sh

print_help() {
    cat <<EOF
This script installs and configures KVM and libvirt for virtualization.
It can also install the optional Cockpit Web UI for web-based VM management.

Usage: $0 <action> [OPTIONS]

Actions:
  install         Install KVM and libvirt
  uninstall       Uninstall KVM and libvirt
  install-webui  Install Cockpit Web UI
  uninstall-webui Uninstall Cockpit Web UI

Options:
  -h, --help     Show this help message and exit

EOF
}

function install_kvm()
{
    log_info "Installing KVM and libvirt packages..."
    sudo dnf install -y qemu-kvm libvirt bridge-utils virt-install virt-viewer libvirt-daemon-kvm

    log_info "Enabling and starting libvirtd service..."
    sudo systemctl enable --now libvirtd

    log_info "Checking KVM hardware support..."
    if grep -qE '(vmx|svm)' /proc/cpuinfo; then
        log_info "KVM hardware acceleration is supported."
    else
        log_warning "No KVM hardware acceleration detected. VMs may run very slowly."
    fi

    log_info "Setup completed."
}

uninstall_kvm()
{
    log_info "Stopping and disabling libvirtd service..."
    sudo systemctl stop libvirtd
    sudo systemctl disable libvirtd

    log_info "Uninstalling KVM and libvirt packages..."
    sudo dnf remove -y qemu-kvm libvirt bridge-utils virt-install virt-viewer libvirt-daemon-kvm

    sudo systemctl daemon-reload

    log_info "KVM and libvirt uninstalled."
}

install_webui()
{
    log_info "Installing Cockpit Web UI..."
    sudo dnf install -y cockpit cockpit-machines

    log_info "Enabling and starting Cockpit service..."
    sudo systemctl enable --now cockpit.socket

    log_info "Cockpit Web UI should now be accessible at:"
    echo "       https://$(hostname -I | awk '{print $1}'):9090/"
}

uninstall_webui()
{
    log_info "Uninstalling Cockpit Web UI..."
    sudo dnf remove -y cockpit cockpit-machines

    log_info "Stopping and disabling Cockpit service..."
    sudo systemctl stop cockpit.socket
    sudo systemctl disable cockpit.socket

    log_info "Cockpit Web UI uninstalled."
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
        install)
            install_kvm "$@"
            return $?
            ;;
        uninstall)
            uninstall_kvm "$@"
            return $?
            ;;
        install-webui)
            install_webui "$@"
            return $?
            ;;
        uninstall-webui)
            uninstall_webui "$@"
            return $?
            ;;
        help|-h|--help)
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

