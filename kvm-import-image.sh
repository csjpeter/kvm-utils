#!/bin/bash

set -o pipefail

MYDIR=$(dirname "$(readlink -f "$0")")

source "$MYDIR/kvm-include.sh"

IMAGE_NAME=""
IMAGE_URL=""

TMP_IMAGE_PATH===

declare -A KNOWN_IMAGES=(
    ["debian11"]="https://cdimage.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
    ["debian12"]="https://cdimage.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
    ["ubuntu20"]="https://cloud-images.ubuntu.com/focal/current/focal-server-cloudimg-amd64.img"
    ["ubuntu22"]="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    ["ubuntu24"]="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    ["centos8"]="https://cloud.centos.org/centos/8/x86_64/images/CentOS-8-GenericCloud-8.4.2105-20210603.0.x86_64.qcow2"
    ["centos9-stream"]="https://cloud.centos.org/altarch/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
    ["rocky8"]="https://dl.rockylinux.org/pub/rocky/8/images/x86_64/Rocky-8-GenericCloud.latest.x86_64.qcow2"
    ["rocky9"]="https://dl.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2"
    ["fedora37"]="https://dl01.fedoraproject.org/pub/archive/fedora/linux/releases/37/Cloud/x86_64/images/Fedora-Cloud-Base-37-1.7.x86_64.qcow2"
    ["fedora38"]="https://dl01.fedoraproject.org/pub/archive/fedora/linux/releases/38/Cloud/x86_64/images/Fedora-Cloud-Base-38-1.6.x86_64.qcow2"
    ["fedora39"]="https://dl01.fedoraproject.org/pub/archive/fedora/linux/releases/39/Cloud/x86_64/images/Fedora-Cloud-Base-39-1.5.x86_64.qcow2"
    ["fedora40"]="https://dl01.fedoraproject.org/pub/archive/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-Generic.x86_64-40-1.14.qcow2"
    #["gentoo"]="https://distfiles.gentoo.org/releases/amd64/autobuilds/20250511T165428Z/stage3-amd64-systemd-20250511T165428Z.tar.xz"
)

print_help()
{
    cat <<EOF
This script imports cloud images into KVM libvirt.

Usage: $0 <name> [url]

Arguments:
    <name>                 Name of the local qcow2 image
    [url]                  URL of the cloud image to import

Known images:
EOF
    for image in "${!KNOWN_IMAGES[@]}"; do
        echo "    $image: ${KNOWN_IMAGES[$image]}"
    done
}

function parse_args()
{
    # No argument is specified
    if [ "$#" -eq 0 ]; then
        print_help
        if [ -x virsh ]; then
            log_info "No action specified. Listing all images."
            sudo virsh image-list --all
        fi
        return 1
    fi

    # Help requested
    if [ "$1" == "help" ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        print_help
        return 0
    fi

    # Argument 1 is the machine name
    IMAGE_NAME=$1
    shift
    if [ "$IMAGE_NAME" == "" ]; then
        log_error "Image name is required"
        return 1
    fi
    log_info "Image name: $IMAGE_NAME"

    # Argument 2 is optionlly the image URL
    IMAGE_URL=$1
    shift
    if [ "$IMAGE_URL" == "" ]; then
        IMAGE_URL=${KNOWN_IMAGES[$IMAGE_NAME]}
    fi
    log_info "Image URL: $IMAGE_URL"
}

function cleanup()
{
    log_info "Cleaning up temporary image file: ${TMP_IMAGE_PATH}"

    rm -f ${TMP_IMAGE_PATH}
    if [ $? -ne 0 ]; then
        log_error "Failed to cleanup temporary image file."
        return 1
    fi
}

function main()
{
    parse_args "$@"
    if [ $? -ne 0 ]; then
        return 1
    fi

    local tpl_image_path="/var/lib/libvirt/images/${IMAGE_NAME}.qcow2"

    if sudo [ -f ${tpl_image_path} ]; then
        echo "Image ${tpl_image_path} already exists. Skipping download."
        return 0
    fi

    # Lets have a temporary file
    TMP_IMAGE_PATH=$(mktemp /tmp/kvm-import-image.XXXXXX)
    if [ $? -ne 0 ]; then
        log_error "Failed to create temporary image file."
        return 1
    fi

    log_info "Downloading image to ${TMP_IMAGE_PATH}."
    wget -q -O ${TMP_IMAGE_PATH} ${IMAGE_URL}
    if [ $? -ne 0 ]; then
        log_error "Failed to download image from ${IMAGE_URL}."
        return 1
    fi
    trap 'cleanup' EXIT

    log_info "Converting image to qcow2 format into ${tpl_image_path}."
    sudo qemu-img convert -f qcow2 -O qcow2 ${TMP_IMAGE_PATH} ${tpl_image_path}
    if [ $? -ne 0 ]; then
        log_error "Failed to convert image to qcow2 format."
        return 1
    fi

    sudo chmod 644 ${tpl_image_path}
    if [ $? -ne 0 ]; then
        log_error "Failed to set permissions on image file."
        return 1
    fi

    sudo chown ${QEMU_GROUP}:kvm ${tpl_image_path}
    if [ $? -ne 0 ]; then
        log_error "Failed to set ownership ${QEMU_GROUP}:kvm on image file ${tpl_image_path}."
        return 1
    fi

    log_info "Image ${tpl_image_path} imported successfully."
}

main "$@"

