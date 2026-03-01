#!/bin/bash
#
# kvm-install-webui.sh - Installs Cockpit WebUI for KVM/libvirt on Rocky Linux 9
#

set -o pipefail

MYDIR="$(dirname "$(readlink -f "$0")")"

source "$MYDIR/kvm-include.sh"

print_help() {
    cat <<EOF
This script installs and configures Cockpit WebUI for KVM and libvirt for
virtualization.

Usage: $0 <action> [OPTIONS]

Actions:
  sure            Yes, do install Cockpit WebUI for KVM and libvirt

Options:
  -h, --help     Show this help message and exit

EOF
}

install_webui()
{
    log_info "Installing Cockpit Web UI..."

    sudo dnf install -y cockpit cockpit-machines
    if [ $? -ne 0 ]; then
        log_error "Failed to install Cockpit Web UI."
        return 1
    fi

    log_info "Enabling and starting Cockpit service..."

    sudo systemctl enable --now cockpit.socket
    if [ $? -ne 0 ]; then
        log_error "Failed to enable and start Cockpit service."
        return 1
    fi

    log_info "Cockpit Web UI should now be accessible at:"
    echo "       https://$(hostname -I | awk '{print $1}'):9090/"
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
            install_webui "$@"
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

