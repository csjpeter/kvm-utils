#!/bin/bash
#
# kvm-share.sh - Manage virtiofs host-to-guest directory shares
#

set -o pipefail

MYDIR=$(dirname "$(readlink -f "$0")")

source "$MYDIR/kvm-include.sh"

VM_NAME=""
HOST_DIR=""
TAG=""
RESTART=false
ACTION=""

print_help()
{
    cat <<EOF
This script manages virtiofs host-to-guest directory shares for KVM VMs.
Shares are added to the persistent VM configuration. Changes take effect
after the next VM restart. Use --restart to restart the VM immediately.

Usage: $0 <action> [OPTIONS]

Actions:
    attach <vm-name> <host-dir> <tag>   Share a host directory with a VM
    detach <vm-name> <tag>              Remove a shared directory from a VM
    list   <vm-name>                    List all shares configured for a VM
    help                                Show this help message

Options (attach, detach):
    --restart   Restart the VM after applying the change

Requirements:
    - virtiofsd must be installed (provided by qemu-kvm or virtiofsd package)
    - Guest must mount the share, e.g. in /etc/fstab:
          <tag>  <mountpoint>  virtiofs  defaults  0  0

Example:
    $0 attach my-vm /home/user/shared-dir myshare
    $0 attach my-vm /home/user/other-dir  othershare
    $0 attach my-vm /home/user/last-dir   lastshare --restart
    $0 detach my-vm myshare --restart
    $0 list my-vm

EOF
}

function restart_vm()
{
    local vm="$1"
    local state
    state=$(sudo virsh domstate "$vm" 2>/dev/null || echo "unknown")

    if [ "$state" = "running" ]; then
        log_info "Shutting down $vm..."
        sudo virsh shutdown "$vm"
        if [ $? -ne 0 ]; then
            log_warning "Graceful shutdown failed — forcing off $vm"
            sudo virsh destroy "$vm"
        else
            local t=0
            while [ $t -lt 30 ]; do
                state=$(sudo virsh domstate "$vm" 2>/dev/null || echo "unknown")
                [ "$state" != "running" ] && break
                sleep 1
                ((t++))
            done
            if [ "$state" = "running" ]; then
                log_warning "Shutdown timed out — forcing off $vm"
                sudo virsh destroy "$vm"
            fi
        fi
    fi

    log_info "Starting $vm..."
    sudo virsh start "$vm"
    if [ $? -ne 0 ]; then
        log_error "Failed to start $vm."
        return 1
    fi
}

function ensure_memory_backing()
{
    local vm="$1"
    if sudo virsh dumpxml --inactive "$vm" 2>/dev/null | grep -q "source type='memfd'"; then
        log_info "Shared memory backing already configured on $vm."
        return 0
    fi
    log_info "Configuring shared memory backing for virtiofs on $vm..."
    sudo virt-xml "$vm" --edit --memorybacking source.type=memfd,access.mode=shared --define
    if [ $? -ne 0 ]; then
        log_error "Failed to configure memory backing on $vm."
        return 1
    fi
}

function attach_share()
{
    if ! sudo virsh dominfo "$VM_NAME" &>/dev/null; then
        log_error "VM '$VM_NAME' not found."
        return 1
    fi

    if [ ! -d "$HOST_DIR" ]; then
        log_error "Host directory '$HOST_DIR' does not exist."
        return 1
    fi

    if sudo virsh dumpxml --inactive "$VM_NAME" 2>/dev/null \
            | grep -q "target dir='${TAG}'"; then
        log_info "Share '$TAG' is already attached to $VM_NAME."
        return 0
    fi

    ensure_memory_backing "$VM_NAME"
    if [ $? -ne 0 ]; then
        return 1
    fi

    log_info "Attaching $HOST_DIR as '$TAG' to $VM_NAME..."
    sudo virt-xml "$VM_NAME" --add-device --define \
        --filesystem "source.dir=${HOST_DIR},target.dir=${TAG},accessmode=passthrough,driver.type=virtiofs"
    if [ $? -ne 0 ]; then
        log_error "Failed to attach share '$TAG' to $VM_NAME."
        return 1
    fi

    if [ "$RESTART" = "true" ]; then
        restart_vm "$VM_NAME"
        if [ $? -ne 0 ]; then
            return 1
        fi
        log_info "Share '$TAG' attached and VM restarted."
    else
        log_info "Share '$TAG' configured. Restart the VM for it to take effect."
    fi
}

function detach_share()
{
    if ! sudo virsh dominfo "$VM_NAME" &>/dev/null; then
        log_error "VM '$VM_NAME' not found."
        return 1
    fi

    if ! sudo virsh dumpxml --inactive "$VM_NAME" 2>/dev/null \
            | grep -q "target dir='${TAG}'"; then
        log_info "Share '$TAG' is not attached to $VM_NAME."
        return 0
    fi

    local fs_xml
    fs_xml=$(sudo virsh dumpxml --inactive "$VM_NAME" \
        | xmllint --xpath "//filesystem[target/@dir='${TAG}']" - 2>/dev/null)
    if [ -z "$fs_xml" ]; then
        log_error "Could not extract filesystem XML for tag '$TAG'."
        return 1
    fi

    log_info "Detaching share '$TAG' from $VM_NAME..."
    echo "$fs_xml" | sudo virsh detach-device "$VM_NAME" /dev/stdin --persistent
    if [ $? -ne 0 ]; then
        log_error "Failed to detach share '$TAG' from $VM_NAME."
        return 1
    fi

    if [ "$RESTART" = "true" ]; then
        restart_vm "$VM_NAME"
        if [ $? -ne 0 ]; then
            return 1
        fi
        log_info "Share '$TAG' detached and VM restarted."
    else
        log_info "Share '$TAG' removed. Restart the VM for it to take effect."
    fi
}

function list_shares()
{
    if ! sudo virsh dominfo "$VM_NAME" &>/dev/null; then
        log_error "VM '$VM_NAME' not found."
        return 1
    fi

    local xml
    xml=$(sudo virsh dumpxml --inactive "$VM_NAME" 2>/dev/null)

    local count
    count=$(echo "$xml" | xmllint --xpath "count(//filesystem)" - 2>/dev/null || echo 0)
    count=${count%.*}  # trim any decimal point

    if [ "$count" -eq 0 ]; then
        log_info "No shares configured on $VM_NAME."
        return 0
    fi

    printf "%-20s %-40s %s\n" "TAG" "HOST DIR" "TYPE"
    printf "%-20s %-40s %s\n" "---" "--------" "----"

    local i tag src drv
    for i in $(seq 1 "$count"); do
        tag=$(echo "$xml" | xmllint --xpath "string(//filesystem[$i]/target/@dir)" - 2>/dev/null)
        src=$(echo "$xml" | xmllint --xpath "string(//filesystem[$i]/source/@dir)" - 2>/dev/null)
        drv=$(echo "$xml" | xmllint --xpath "string(//filesystem[$i]/driver/@type)" - 2>/dev/null)
        printf "%-20s %-40s %s\n" "$tag" "${src:-n/a}" "${drv:-path}"
    done
}

function parse_args()
{
    if [ "$#" -eq 0 ]; then
        print_help
        return 1
    fi

    if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        print_help
        return 0
    fi

    ACTION="$1"
    shift

    case "$ACTION" in
        attach)
            if [ "$#" -lt 3 ]; then
                log_error "attach requires: <vm-name> <host-dir> <tag>"
                return 1
            fi
            VM_NAME="$1"
            HOST_DIR="$2"
            TAG="$3"
            shift 3
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --restart) RESTART=true ;;
                    *) log_error "Unknown option: $1"; return 1 ;;
                esac
                shift
            done
            log_info "VM: $VM_NAME  host-dir: $HOST_DIR  tag: $TAG"
            ;;
        detach)
            if [ "$#" -lt 2 ]; then
                log_error "detach requires: <vm-name> <tag>"
                return 1
            fi
            VM_NAME="$1"
            TAG="$2"
            shift 2
            while [ "$#" -gt 0 ]; do
                case "$1" in
                    --restart) RESTART=true ;;
                    *) log_error "Unknown option: $1"; return 1 ;;
                esac
                shift
            done
            log_info "VM: $VM_NAME  tag: $TAG"
            ;;
        list)
            if [ "$#" -lt 1 ]; then
                log_error "list requires: <vm-name>"
                return 1
            fi
            VM_NAME="$1"
            ;;
        *)
            log_error "Unknown action: $ACTION"
            return 1
            ;;
    esac
}

function main()
{
    parse_args "$@"
    if [ $? -ne 0 ]; then
        return 1
    fi

    case "$ACTION" in
        attach) attach_share ;;
        detach) detach_share ;;
        list)   list_shares ;;
    esac
    return $?
}

main "$@"
