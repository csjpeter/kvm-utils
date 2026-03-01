#!/bin/bash
#
# kvm-uninstall-webui.sh - Uninstalls Cockpit WebUI for KVM/libvirt on Rocky Linux 9
#

set -o pipefail

MYDIR="$(dirname "$(readlink -f "$0")")"

source "$MYDIR/kvm-include.sh"

print_help() {
    cat <<EOF
This script uninstalls Cockpit WebUI for KVM and libvirt.

Usage: $0 <action> [OPTIONS]

Actions:
  sure            Yes, do remove Cockpit WebUI for KVM and libvirt

Options:
  -h, --help     Show this help message and exit

EOF
}

uninstall_webui()
{
    log_info "Stopping and disabling Cockpit service..."

    sudo systemctl stop cockpit.socket
    if [ $? -ne 0 ]; then
        log_error "Failed to stop Cockpit service."
        return 1
    fi

    sudo systemctl disable cockpit.socket
    if [ $? -ne 0 ]; then
        log_error "Failed to disable Cockpit service."
        return 1
    fi

    log_info "Uninstalling Cockpit Web UI..."

    sudo dnf remove -y cockpit cockpit-machines
    if [ $? -ne 0 ]; then
        log_error "Failed to uninstall Cockpit Web UI."
        return 1
    fi

    sudo systemctl daemon-reload
    if [ $? -ne 0 ]; then
        log_error "Failed to reload systemd daemon."
        return 1
    fi

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
        sure)
            uninstall_webui "$@"
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

