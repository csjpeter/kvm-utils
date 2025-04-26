#!/bin/bash
#
# kvm-setup.sh - Basic KVM/libvirt setup script for Rocky Linux 9
#

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

print_help() {
    cat <<EOF
Usage: $0 [OPTION]

Options:
  --webui        Install optional Cockpit Web UI (web-based VM management)
  -h, --help     Show this help message and exit

This script installs and configures KVM and libvirt for virtualization.
By default, it installs only console tools (no GUI desktop tools).
EOF
}

main() {
    local packages=(
        qemu-kvm
        libvirt
        bridge-utils
        virt-install
        virt-viewer
        libvirt-daemon-kvm
    )

    case "${1:-}" in
        -h|--help)
            print_help
            exit 0
            ;;
        --webui)
            install_webui="yes"
            ;;
        "" )
            install_webui="no"
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage."
            exit 1
            ;;
    esac

    log_info "Installing KVM and libvirt packages..."
    sudo dnf install -y "${packages[@]}"

    log_info "Enabling and starting libvirtd service..."
    sudo systemctl enable --now libvirtd

    log_info "Checking if user is in 'libvirt' group..."
    if ! id -nG "$USER" | grep -qw "libvirt"; then
        log_info "Adding user '$USER' to 'libvirt' group..."
        sudo usermod -aG libvirt "$USER"
        log_warning "You must log out and back in (or use 'newgrp libvirt') for group changes to take effect."
    else
        log_info "User '$USER' is already in 'libvirt' group."
    fi

    log_info "Checking KVM hardware support..."
    if grep -qE '(vmx|svm)' /proc/cpuinfo; then
        log_info "KVM hardware acceleration is supported."
    else
        log_warning "No KVM hardware acceleration detected. VMs may run very slowly."
    fi

    if [[ "$install_webui" == "yes" ]]; then
        setup_webui
    fi

    log_info "Setup completed."
}

setup_webui() {
    log_info "Installing Cockpit Web UI..."
    sudo dnf install -y cockpit cockpit-machines

    log_info "Enabling and starting Cockpit service..."
    sudo systemctl enable --now cockpit.socket

    log_info "Cockpit Web UI should now be accessible at:"
    echo "       https://$(hostname -I | awk '{print $1}'):9090/"
}

main "$@"

