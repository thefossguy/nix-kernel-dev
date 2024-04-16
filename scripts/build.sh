#!/usr/bin/env dash

set -x


if [ "$(uname -m)" = 'aarch64' ]; then
    BUILD_ARCH='arm64'
elif [ "$(uname -m)" = 'riscv64' ]; then
    BUILD_ARCH='riscv'
elif [ "$(uname -m)" = 'x86_64' ]; then
    BUILD_ARCH='x86'
else
    echo 'ERROR: unsupported architecture.'
    exit 1
fi

if [ -n "${BUILD_WITH_RUST:-}" ]; then
    LOCALVERSION_SUFFIX='-rust'
else
    LOCALVERSION_SUFFIX=''
fi

CLEAN_BUILD="${CLEAN_BUILD:-0}"
KERNEL_CONFIG="${KERNEL_CONFIG:-}"
KERNEL_LOCALVERSION="-$(date +%Y.%m.%d.%H%M)${LOCALVERSION_SUFFIX}"
BUILD_WITH_RUST="${BUILD_WITH_RUST:-0}"
INSTALL_ZE_KERNEL="${INSTALL_ZE_KERNEL:-1}"
FORCE_INSTALL_ZE_KERNEL="${FORCE_INSTALL_ZE_KERNEL:-0}"
MAX_PARALLEL_JOBS="-j${MAX_PARALLEL_JOBS:-$(( $(nproc) + 2 ))}"
SUDO_ALIAS='sudo --preserve-env=PATH env' # use this alias for su-do-ing binaries provided by Nix
REMOVE_KERNEL="${REMOVE_KERNEL:-}"

export BUILD_ARCH CLEAN_BUILD KERNEL_CONFIG KERNEL_LOCALVERSION BUILD_WITH_RUST INSTALL_ZE_KERNEL FORCE_INSTALL_ZE_KERNEL MAX_PARALLEL_JOBS SUDO_ALIAS REMOVE_KERNEL

if grep -q 'debian' /etc/os-release; then
    prefix='debian'
elif grep -q 'fedora' /etc/os-release; then
    prefix='fedora'
else
    prefix='raw'
fi
ze_script="$(dirname "$0")/$prefix-build-kernel-and-install.sh"


if [ -z "${REMOVE_KERNEL}" ]; then
    $ze_script 2>&1 | tee "build-$(make -s kernelversion)${KERNEL_LOCALVERSION}.log"
else
    $ze_script "${1:-$(make -s kernelrelease)}"
fi
