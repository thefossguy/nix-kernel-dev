#!/usr/bin/env bash

set -xeuf -o pipefail

# unless specified, use stable since bootstrapping sid **has** resulted in failed bootstraps
VERSION_CODENAME="${1:-stable}"
BOOTSTRAP_DIR='bootstrap.tmp'
IMAGE_NAME="debian-$(uname -m)-${VERSION_CODENAME}-$(TZ='Asia/Kolkata' date +%Y%m%d).img"
IMAGE_SIZE='10240M'
export VERSION_CODENAME BOOTSTRAP_DIR IMAGE_NAME IMAGE_SIZE PKGS

function errr() {
    # 1. unmount
    # 2. rmdir bootstrap_dir
    # 3. detach from loopback
    # 4. rm image
    if mount | grep -q "${BOOTSTRAP_DIR}"; then
        sudo umount -R "${BOOTSTRAP_DIR}"
    fi
    rmdir "${BOOTSTRAP_DIR}"

    if losetup --list --all | grep -q "${LOOP_DEV}"; then
        sudo losetup -d "${LOOP_DEV}"
    fi
    rm "${IMAGE_NAME}"
}
trap errr ERR

if [[ -f "${IMAGE_NAME}" ]]; then
    echo 'Image already exists, no need to run this script.'
    exit 0
fi

# create img and bootstrap_dir
truncate -s "${IMAGE_SIZE}" "${IMAGE_NAME}"
mkdir -p "${BOOTSTRAP_DIR}"

# format
# mount to loopback
# mount loopback to bootstrap_dir
mkfs.ext4 "${IMAGE_NAME}"
LOOP_DEV="$(sudo losetup --find --partscan --show "${IMAGE_NAME}")"
export LOOP_DEV
sudo mount "${LOOP_DEV}" "${BOOTSTRAP_DIR}"

# bootstrap and set empty password for root
# shellcheck disable=SC2046
sudo $(command -v debootstrap) "${VERSION_CODENAME}" "${BOOTSTRAP_DIR}"
sudo cp chroot-script.sh "${BOOTSTRAP_DIR}/root/chroot-script.sh"
sudo chroot "${BOOTSTRAP_DIR}" bash -c 'bash /root/chroot-script.sh'

# "cleanup"
sudo umount -R "${BOOTSTRAP_DIR}"
rmdir "${BOOTSTRAP_DIR}"
