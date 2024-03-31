#!/usr/bin/env bash

set -xeu -o pipefail

function remove_kernel() {
        kernel_version="${1:-$(make -s kernelrelease)}"
        install_dirs=(
            /boot
            /lib/modules
            /usr
        )
        sudo find /boot/loader/entries -name "*$kernel_version.conf" -type f -print0 | xargs --null sudo rm -vf
        for d in "${install_dirs[@]}"; do
            # shellcheck disable=SC2086
            sudo rm -rvf "$d"/*$kernel_version*
        done
        if command -v kernel-install > /dev/null; then
            sudo kernel-install remove "$kernel_version"
        fi
        $UPDATE_BOOTLOADER
}


function build_kernel() {
    ${PRE_BUILD_SETUP:-}
    # shellcheck disable=SC2086
    make $MAX_PARALLEL_JOBS ${KERNEL_MAKE_TARGET:-all}
}

function install_kernel() {
    if [[ "${INSTALL_ZE_KERNEL}" == '1' ]]; then
        if grep nixos /etc/os-release > /dev/null && [[ "${FORCE_INSTALL_ZE_KERNEL}" == '0' ]]; then
            echo 'NixOS detected. Not installing kernel. Set FORCE_INSTALL_ZE_KERNEL=1 to override.'
        else

            if [[ -n "${KERNEL_INSTALL_COMMAND:-}" ]]; then
                $KERNEL_INSTALL_COMMAND
            else
                if find "arch/$BUILD_ARCH/boot/dts" -name "*.dtb" -print -quit > /dev/null; then
                    DTB_INSTALL='dtbs_install'
                else
                    DTB_INSTALL=''
                fi

                sudo cp .config "/boot/config-$(make -s kernelrelease)"
                # shellcheck disable=SC2086
                $SUDO_ALIAS make $MAX_PARALLEL_JOBS headers_install $DTB_INSTALL modules_install || remove_kernel
                $SUDO_ALIAS make install || remove_kernel
            fi
        fi
    fi
}

if [[ -n "${REMOVE_KERNEL}" ]]; then
    remove_kernel "${REMOVE_KERNEL}"
    exit 0
fi

if [[ -z "${KERNEL_LOCALVERSION}" ]]; then
    # shellcheck disable=SC2016
    echo 'ERROR: cannot proceed without a $KERNEL_LOCALVERSION'
    exit 1
fi

"$(dirname "$0")/configure-kernel.sh"
build_kernel
install_kernel
