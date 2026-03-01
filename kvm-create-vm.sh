#!/bin/bash

set -o pipefail

MYDIR=$(dirname "$(readlink -f "$0")")

source "$MYDIR/kvm-include.sh"

VM_NAME=""
VM_IP=""
VM_IMAGE=""
VCPUS=1
RAM=3072   # stored in MiB for virt-install
DISK_SIZE=20G
ADMIN_USER=$USER
ETHERNET_IFC=""

TMP_CLOUD_INIT_SEED_DIRECTORY="$(mktemp -d /tmp/kvm-create-vm.XXXXXX)"
TMP_CLOUD_INIT_NETWORK_CONFIG_FILE="${TMP_CLOUD_INIT_SEED_DIRECTORY}/network-config"
TMP_CLOUD_INIT_USER_DATA_FILE="${TMP_CLOUD_INIT_SEED_DIRECTORY}/user-data"
TMP_CLOUD_INIT_META_DATA_FILE="${TMP_CLOUD_INIT_SEED_DIRECTORY}/meta-data"
TMP_CLOUD_INIT_SEED_FILE="$(mktemp -u /tmp/kvm-create-vm.XXXXXX-seed.iso)"

declare -A ETHERNET_IFC_ON_IMAGE=(
    ["debian11"]="ens3"
    ["debian12"]="ens3"
    ["ubuntu20"]="ens3"
    ["ubuntu22"]="enp1s0"
    ["ubuntu24"]="enp1s0"
    ["centos8"]="ens3"
    ["centos9-stream"]="ens3"
    ["rocky8"]="ens3"
    ["rocky9"]="ens3"
    ["fedora37"]="ens3"
    ["fedora38"]="ens3"
    ["fedora39"]="ens3"
    ["fedora40"]="ens3"
)

print_help()
{
    cat <<EOF
This script creates KVM virtual machine by libvirt.

Usage: $0 <template_image_name> <name> <ip> [OPTIONS]

Arguments:
    <template_image_name>  Name of a cloud image previously imported with
                           kvm-import-image.sh. Known images and their
                           default ethernet interface names:
EOF
    for image in "${!ETHERNET_IFC_ON_IMAGE[@]}"; do
        local ifc="${ETHERNET_IFC_ON_IMAGE[$image]}"
        echo "                               $image (${ifc})"
    done
cat <<EOF
    <name>                 Name of the virtual machine
    <ip>                   IP address of the virtual machine

Options:
    --vcpus=<size>         Specify the number of vCPUs for the VM (default: 1).
    --ram=<size>           Specify the RAM size for the VM (default: 3G). Accepts M or G suffix (e.g. 512M, 2G) or plain MiB number.
    --disk-size=<size>     Specify the disk size for the VM (default: 20G).
    --admin-user=<name>    Specify the admin user for the VM (default: $USER).
    --ethernet-ifc=<name>  Override the default ethernet interface name.

Example:
    $0 ubuntu24 my-vm 192.168.122.10

EOF
}

function ram_to_mib()
{
    local val="$1"
    if [[ "$val" =~ ^([0-9]+)[Gg]$ ]]; then
        RAM=$(( ${BASH_REMATCH[1]} * 1024 ))
    elif [[ "$val" =~ ^([0-9]+)[Mm]$ ]]; then
        RAM=${BASH_REMATCH[1]}
    elif [[ "$val" =~ ^([0-9]+)$ ]]; then
        RAM=${BASH_REMATCH[1]}
    else
        log_error "Invalid RAM value '$val'. Use a plain MiB number or suffix M/G (e.g. 512M, 2G)."
        return 1
    fi
}

function wait_for_ssh()
{
    local timeout=120
    local interval=3

    log_info "Waiting at most $timeout seconds for SSH to be available for user ${ADMIN_USER} on $VM_NAME ($VM_IP)."

    local start_time
    start_time=$(date +%s)

    while true; do
        local old_set_options=$(set +o)
        set +e +o pipefail

        ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=quiet "${ADMIN_USER}@$VM_IP" -- true
        ret=$?

        eval "$old_set_options"

        if [ $ret -eq 0 ]; then
            log_info "SSH is now available on $VM_NAME ($VM_IP)."
            return 0
        fi

        local current_time elapsed_time
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))
        if [ $elapsed_time -ge "$timeout" ]; then
            log_error "Timed out waiting for SSH on $VM_NAME after $timeout seconds."
            return 1
        fi

        sleep "$interval"

        echo -ne "\rElapsed time: $elapsed_time seconds"
    done
}

function create_metadata()
{
    cat > "${TMP_CLOUD_INIT_META_DATA_FILE}" <<EOF
instance-id: ${VM_NAME}-kvm
local-hostname: ${VM_NAME}
EOF
}

function create_network_config() {
    log_info "Creating cloud-init network-config."
    cat >${TMP_CLOUD_INIT_NETWORK_CONFIG_FILE} <<EOF
ethernets:
    ${ETHERNET_IFC}:
        dhcp4: true
version: 2
EOF
    cat ${TMP_CLOUD_INIT_NETWORK_CONFIG_FILE}
}

function create_user_data()
{
    local public_key

    # Path to the current user's default public keys
    local rsa_public_key_file="/home/$USER/.ssh/id_rsa.pub"
    local ed25519_public_key_file="/home/$USER/.ssh/id_ed25519.pub"

    # Select which public key to use (prioritize id_ed25519 if both exist)
    if [[ -f "$ed25519_public_key_file" ]]; then
        public_key=$(cat "$ed25519_public_key_file")
    elif [[ -f "$rsa_public_key_file" ]]; then
        public_key=$(cat "$rsa_public_key_file")
    else
        log_error "No SSH public key found."
        return 1
    fi

    log_info "Creating cloud-init user-data."
    cat >${TMP_CLOUD_INIT_USER_DATA_FILE} <<EOF
#cloud-config
hostname: ${VM_NAME}
users:
  - name: ${ADMIN_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: ${ADMIN_USER},users
    primary_group: ${ADMIN_USER}
    shell: /bin/bash
    lock_passwd: false
    expiredate: '2100-01-01'
    ssh-authorized-keys:
      - $public_key
    plain_text_passwd: pwd
disable_root: true

runcmd:
  - mkdir -p /home/${ADMIN_USER}/.ssh
  - ssh-keygen -t rsa -b 4096 -f /home/${ADMIN_USER}/.ssh/id_rsa -N ""
  - chown -R ${ADMIN_USER}:${ADMIN_USER} /home/${ADMIN_USER}/.ssh
  - chmod 700 /home/${ADMIN_USER}/.ssh
  - chmod 600 /home/${ADMIN_USER}/.ssh/id_rsa
  - chmod 644 /home/${ADMIN_USER}/.ssh/id_rsa.pub
EOF
    cat ${TMP_CLOUD_INIT_USER_DATA_FILE}

    log_info "Validating cloud-init user-data."
    sudo cloud-init schema --config-file ${TMP_CLOUD_INIT_USER_DATA_FILE}
    if [ $? -ne 0 ]; then
        log_error "Failed to validate user-data."
        return 1
    else
        log_info "User-data validation passed."
    fi
}

function create_cloud_init_seed()
{
    log_info "Creating cloud-init seed image for VM $VM_NAME."

    create_metadata
    if [ $? -ne 0 ]; then
        log_error "Failed to create metadata."
        return 1
    fi

    create_network_config
    if [ $? -ne 0 ]; then
        log_error "Failed to create network config."
        return 1
    fi

    create_user_data
    if [ $? -ne 0 ]; then
        log_error "Failed to create user data."
        return 1
    fi

    log_info "Creating cloud-init seed image."
    xorriso -as mkisofs -volid CIDATA -rock \
        -output ${TMP_CLOUD_INIT_SEED_FILE} \
        ${TMP_CLOUD_INIT_USER_DATA_FILE} \
        ${TMP_CLOUD_INIT_META_DATA_FILE} \
        ${TMP_CLOUD_INIT_NETWORK_CONFIG_FILE}
    if [ $? -ne 0 ]; then
        log_error "Failed to create cloud-init seed image."
        return 1
    fi

    sudo chmod 644 ${TMP_CLOUD_INIT_SEED_FILE}
    if [ $? -ne 0 ]; then
        log_error "Failed to set permissions on cloud-init seed image."
        return 1
    fi

    sudo chown ${QEMU_GROUP}:kvm ${TMP_CLOUD_INIT_SEED_FILE}
    if [ $? -ne 0 ]; then
        log_error "Failed to change ownership of cloud-init seed image."
        return 1
    fi
}

function create_vm()
{
    # Check if the VM already exists
    if sudo virsh list --all | grep -q "$VM_NAME"; then
        log_error "Virtual machine $VM_NAME already exists."
        return 1
    fi

    ip_to_mac "$VM_IP"
    if [ $? -ne 0 ]; then
        log_error "Failed to convert IP address to MAC address."
        return 1
    fi
    local mac=${RETURNED_MAC}
    log_info "MAC address: $mac"

    find_nic_by_vm_ip "$VM_IP"
    if [ $? -ne 0 ]; then
        log_error "Failed to find network interface for IP address $VM_IP."
        return 1
    fi
    local bridge=${RETURNED_BRIDGE_NAME}
    log_info "Bridge name: $bridge"

    find_libvirt_network_by_bridge "$bridge"
    if [ $? -ne 0 ]; then
        log_error "Failed to find libvirt network for ip address $VM_IP."
        return 1
    fi
    local network=${RETURNED_NETWORK_NAME}
    log_info "Network name: $network"
    if [ -z "$network" ]; then
        log_error "No libvirt network found for ip ${VM_IP}. Use kvm-net.sh to create a network."
        return 1
    fi

    # if ethernet interfaces is not specified, pick a default from
    # the ETHERNET_IFC_ON_IMAGE array
    if [ -z "$ETHERNET_IFC" ]; then
        ETHERNET_IFC=${ETHERNET_IFC_ON_IMAGE[$VM_IMAGE]}
        if [ -z "$ETHERNET_IFC" ]; then
            log_error "No ethernet interface found for image $VM_IMAGE."
            return 1
        fi
    fi

    local tpl_image_path="/var/lib/libvirt/images/${VM_IMAGE}.qcow2"
    local vm_image_path="/var/lib/libvirt/images/${VM_NAME}.qcow2"

    create_cloud_init_seed
    if [ $? -ne 0 ]; then
        log_error "Failed to create cloud-init seed image."
        return 1
    fi

    log_info "Creating disk image for the new virtual machine."
    sudo qemu-img create -F qcow2 -b ${tpl_image_path} -f qcow2 ${vm_image_path} ${DISK_SIZE}
    if [ $? -ne 0 ]; then
        log_error "Failed to create disk image for virtual machine $VM_NAME."
        return 1
    fi

    # Create the VM using virt-install
    sudo virt-install \
        --virt-type kvm \
        --name "$VM_NAME" \
        --ram "$RAM" \
        --vcpus "$VCPUS" \
        --disk path="${vm_image_path},device=disk" \
        --cdrom ${TMP_CLOUD_INIT_SEED_FILE} \
        --network network="${network}",model=virtio,mac="$mac" \
        --osinfo detect=on,name=linux2016 \
        --cloud-init user-data=${TMP_CLOUD_INIT_USER_DATA_FILE} \
        --os-variant ubuntu24.04 \
        --graphics none \
        --console pty,target_type=serial \
        --noautoconsole
    if [ $? -ne 0 ]; then
        log_error "Failed to create virtual machine $VM_NAME."
        return 1
    fi
        #,meta-data=meta-data \

    echo "Checking ip address:"
    sudo virsh domifaddr ${VM_NAME}

    echo "Checking VM status:"
    sudo virsh list --all

    echo "Checking VM network interfaces:"
    sudo virsh domiflist ${VM_NAME}

    echo "Checking IP address:"
    sudo virsh domifaddr ${VM_NAME} --interface ${ETHERNET_IFC}

    log_info "Adding $VM_NAME ($VM_IP) to /etc/hosts."
    sudo sed -i "/ ${VM_NAME}$/d" /etc/hosts
    echo "${VM_IP} ${VM_NAME}" | sudo tee -a /etc/hosts > /dev/null
    if [ $? -ne 0 ]; then
        log_error "Failed to add $VM_NAME to /etc/hosts."
        return 1
    fi

    wait_for_ssh
    if [ $? -ne 0 ]; then
        log_error "Failed to connect to VM $VM_NAME via SSH."
        return 1
    fi

    echo "SSH is available on the VM."

    echo "Dropping obsolete keys from known_hosts for ${VM_NAME} (${VM_IP})."
    ssh-keygen -R "${VM_IP}"
    ssh-keygen -R "${VM_NAME}"

    echo "Adding the host keys of ${VM_NAME} (${VM_IP}) to known_hosts."
    ssh-keyscan "${VM_IP}" "${VM_NAME}" >> ~/.ssh/known_hosts

    log_info "Virtual machine $VM_NAME created successfully."
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
    if [ "$#" -lt 3 ]; then
        log_error "Invalid number of arguments"
    fi

    # Argument 1 is the template image name
    VM_IMAGE=$1
    shift
    if [ "$VM_IMAGE" == "" ]; then
        log_error "Template image name is required"
        return 1
    fi
    log_info "Template image name: $VM_IMAGE"

    # Argument 2 is the machine name
    VM_NAME=$1
    shift
    if [ "$VM_NAME" == "" ]; then
        log_error "Virtual machine name is required"
        return 1
    fi
    log_info "Virtual machine name: $VM_NAME"

    # Argument 3 is the IP address
    VM_IP=$1
    shift
    if [ "$VM_IP" == "" ]; then
        log_error "IP address is required"
        return 1
    fi
    log_info "IP address: $VM_IP"

    # Options
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --vcpus=*)
                VCPUS="${1#--vcpus=}"
                if [ "$VCPUS" == "" ]; then
                    log_error "Number of vCPUs cannot be empty"
                    return 1
                fi
                shift
                ;;
            --ram=*)
                RAM="${1#--ram=}"
                if [ "$RAM" == "" ]; then
                    log_error "RAM size cannot be empty"
                    return 1
                fi
                ram_to_mib "$RAM"
                if [ $? -ne 0 ]; then
                    return 1
                fi
                shift
                ;;
            --disk-size=*)
                DISK_SIZE="${1#--disk-size=}"
                if [ "$DISK_SIZE" == "" ]; then
                    log_error "Disk size cannot be empty"
                    return 1
                fi
                shift
                ;;
            --admin-user=*)
                ADMIN_USER="${1#--admin-user=}"
                if [ "$ADMIN_USER" == "" ]; then
                    log_error "Admin user cannot be empty"
                    return 1
                fi
                shift
                ;;
            --ethernet-ifc=*)
                ETHERNET_IFC="${1#--ethernet-ifc=}"
                if [ "$ETHERNET_IFC" == "" ]; then
                    log_error "Ethernet interface cannot be empty"
                    return 1
                fi
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                return 1
                ;;
        esac
    done
}

function main()
{
    #
    # Main logic
    #

    parse_args "$@"
    if [ $? -ne 0 ]; then
        return 1
    fi
    create_vm
    if [ $? -ne 0 ]; then
        return 1
    fi
}

function cleanup()
{
    if [ -f ${TMP_CLOUD_INIT_NETWORK_CONFIG_FILE} ]; then
        sudo rm -f ${TMP_CLOUD_INIT_NETWORK_CONFIG_FILE}
        if [ $? -ne 0 ]; then
            log_error "Failed to remove temporary cloud-init network-config file."
        fi
    fi
    if [ -f ${TMP_CLOUD_INIT_USER_DATA_FILE} ]; then
        sudo rm -f ${TMP_CLOUD_INIT_USER_DATA_FILE}
        if [ $? -ne 0 ]; then
            log_error "Failed to remove temporary cloud-init user-data file."
        fi
    fi
    if [ -f ${TMP_CLOUD_INIT_META_DATA_FILE} ]; then
        sudo rm -f ${TMP_CLOUD_INIT_META_DATA_FILE}
        if [ $? -ne 0 ]; then
            log_error "Failed to remove temporary cloud-init meta-data file."
        fi
    fi
    if [ -d ${TMP_CLOUD_INIT_SEED_DIRECTORY} ]; then
        sudo rmdir ${TMP_CLOUD_INIT_SEED_DIRECTORY}
        if [ $? -ne 0 ]; then
            log_error "Failed to remove temporary cloud-init seed directory."
        fi
    fi
    if [ -f ${TMP_CLOUD_INIT_SEED_FILE} ]; then
        sudo rm -f ${TMP_CLOUD_INIT_SEED_FILE}
        if [ $? -ne 0 ]; then
            log_error "Failed to remove temporary cloud-init seed file."
        fi
    fi
}

main "$@"
ret=$?
cleanup
exit $ret
