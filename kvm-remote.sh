#!/bin/bash
#
# kvm-setup.sh - Basic KVM/libvirt setup script for Rocky Linux 9
#

set -o pipefail

MYDIR="$(dirname "$(readlink -f "$0")")"

source $MYDIR/kvm-include.sh

print_help() {
    cat <<EOF
This script copies the necessary kvm utility script to a remote server
and executes it there with the arguments passed to this script.

Usage: $0 <remote> <action> [arguments to pass to the remote script]

Actions:
  install         Installs or uninstalls KVM and libvirt.
  remove          Removes KVM and libvirt.
  install-webui   Installs Cockpit WebUI for KVM.
  uninstall-webui Uninstalls Cockpit WebUI for KVM.
  net             Configure network bridge for KVM with libvirt.
  import          Import a cloud image into KVM.
  create          Create a new virtual machine.
  delete          Delete a virtual machine.
  list            List all virtual machines.

Options:
  -h, --help     Show this help message and exit

EOF
}

# param 1: remote server
# param 2...: list of scripts to copy
function install_utility_to_remote()
{
    local remote="$1"
    shift
    if [ -z "$remote" ]; then
        log_error "Remote server not specified"
        return 1
    fi

    while [ "$#" -gt 0 ]; do
        local script="$MYDIR/$1"
        shift

        ssh "$remote" "mkdir -p $MYDIR"
        if [ $? -ne 0 ]; then
            log_error "Failed to create directory on '$remote'."
            return 1
        fi

        #log_info "Copying '$script' to '$remote'."
        scp "$script" "$remote:$script" > /dev/null
        if [ $? -ne 0 ]; then
            log_error "Failed to copy $script to $remote"
            return 1
        fi
    done
}

# param 1: remote server
# param ...: list of arguments to pass to the remote script
function execute_utility_on_remote()
{
    local remote="$1"
    shift
    if [ -z "$remote" ]; then
        log_error "Remote server not specified"
        return 1
    fi

    local script="$MYDIR/$1"
    shift
    if [ -z "$script" ]; then
        log_error "Script not specified"
        return 1
    fi
    if [ ! -f "$script" ]; then
        log_error "Script '$script' not found"
        return 1
    fi

    #log_info "Executing $'script' on '$remote'"
    ssh "$remote" -- $script "$@"
    if [ $? -ne 0 ]; then
        #log_error "Failed $script on $remote"
        return 1
    fi

    return 0
}

main()
{
    if [ "$#" -eq 0 ]; then
        print_help
        return 1
    fi

    local remote="$1"
    shift
    if [ -z "$remote" ]; then
        log_error "Remote server not specified"
        return 1
    fi
    if ! ping -c 1 "$remote" &> /dev/null; then
        log_error "Remote server '$remote' is not reachable"
        return 1
    fi

    local action="$1"
    shift
    if [ -z "$action" ]; then
        log_error "Action not specified"
        return 1
    fi

    case "$action" in
        install)
            install_utility_to_remote "$remote" kvm-include.sh kvm-install.sh
            execute_utility_on_remote "$remote" kvm-install.sh "$@"
            return $?
            ;;
        remove)
            install_utility_to_remote "$remote" kvm-include.sh kvm-uninstall.sh
            execute_utility_on_remote "$remote" kvm-uninstall.sh "$@"
            return $?
            ;;
        install-webui)
            install_utility_to_remote "$remote" kvm-include.sh kvm-install-webui.sh
            execute_utility_on_remote "$remote" kvm-install-webui.sh "$@"
            return $?
            ;;
        uninstall-webui)
            install_utility_to_remote "$remote" kvm-include.sh kvm-uninstall-webui.sh
            execute_utility_on_remote "$remote" kvm-uninstall-webui.sh "$@"
            return $?
            ;;
        net)
            install_utility_to_remote "$remote" kvm-include.sh kvm-net.sh kvm-net-define.sh kvm-net-undefine.sh
            execute_utility_on_remote "$remote" kvm-net.sh "$@"
            return $?
            ;;
        import)
            install_utility_to_remote "$remote" kvm-include.sh kvm-import-image.sh
            execute_utility_on_remote "$remote" kvm-import-image.sh "$@"
            return $?
            ;;
        create)
            install_utility_to_remote "$remote" kvm-include.sh kvm-create-vm.sh
            execute_utility_on_remote "$remote" kvm-create-vm.sh "$@"
            return $?
            ;;
        delete)
            install_utility_to_remote "$remote" kvm-include.sh kvm-delete-vm.sh
            execute_utility_on_remote "$remote" kvm-delete-vm.sh "$@"
            return $?
            ;;
        list)
            install_utility_to_remote "$remote" kvm-include.sh kvm-list.sh
            execute_utility_on_remote "$remote" kvm-list.sh "$@"
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

