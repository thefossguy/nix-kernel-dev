#!/usr/bin/env bash

# **DON'T DISABLE PATHNAME EXPANSION WITH `set -f`**
set -xeu -o pipefail

# TODO
# 1. Verify options' state(s)
# 2. UKI

# Exit codes:
# 1: $KERNEL_LOCALVERSION unset
# 2: unsupported arch
# 3: couldn't find a config to base the current build off off
# 4: building with rust not possible

BUILD_WITH_RUST="${BUILD_WITH_RUST:-0}"
CLEAN_BUILD="${CLEAN_BUILD:-0}"
INSTALL_ZE_KERNEL="${INSTALL_ZE_KERNEL:-1}"
FORCE_INSTALL_ZE_KERNEL="${FORCE_INSTALL_ZE_KERNEL:-0}"
KERNEL_CONFIG="${KERNEL_CONFIG:-}"
KERNEL_LOCALVERSION="${KERNEL_LOCALVERSION:-}"
MAX_PARALLEL_JOBS="-j ${MAX_PARALLEL_JOBS:-$(( $(nproc) + 2 ))}"
SUDO_ALIAS='sudo --preserve-env=PATH env' # use this alias for su-do-ing binaries provided by Nix

REMOVE_KERNEL="${REMOVE_KERNEL:-}"

# could be done with the case statement but I don't like the syntax
# feels _wrong_
machine_uname="$(uname -m)"
if [[ "${machine_uname}" == 'aarch64' ]]; then
    kernel_arch='arm64'
elif [[ "${machine_uname}" == 'riscv64' ]]; then
    kernel_arch='riscv'
elif [[ "${machine_uname}" == 'x86_64' ]]; then
    kernel_arch='x86'
else
    echo 'ERROR: unsupported arch'
    exit 2
fi

if grep 'debian' /etc/os-release > /dev/null; then
    UPDATE_BOOTLOADER='sudo grub-mkconfig -o /boot/grub/grub.cfg'
elif grep 'fedora' /etc/os-release > /dev/null; then
    UPDATE_BOOTLOADER='sudo grub2-mkconfig -o /boot/grub2/grub.cfg'
fi


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

function setup_rust_toolchain() {
     rustup override set "$(scripts/min-tool-version.sh rustc)"
     rustup component add rust-src rustfmt clippy
     cargo install --locked --version "$(scripts/min-tool-version.sh bindgen)" bindgen-cli

     # shellcheck disable=SC2155
     export RUST_LIB_SRC="$(rustc --print sysroot)/lib/rustlib/src/rust/library"
}
function enable_rust_config() {
    if [[ "${BUILD_WITH_RUST}" == '1' ]] && [[ "${LLVM:-0}" == '1' ]]; then
        setup_rust_toolchain

        make rustavailable
        make rust.config

        if ! grep 'CONFIG_RUST=y' .config > /dev/null; then
            echo 'ERROR: building with Rust does not seem to be possible'
            exit 4
        fi

    else
        # shellcheck disable=SC2016
        echo 'WARNING: $BUILD_WITH_RUST or $LLVM is unset, not building with Rust'
    fi
}
function modify_kernel_config() {
    # start with a "useful" base config
    make olddefconfig

    # built-in kernel config
    ./scripts/config --enable CONFIG_IKCONFIG
    ./scripts/config --enable CONFIG_IKCONFIG_PROC
    # built-in kernel headers
    ./scripts/config --enable CONFIG_IKHEADERS

    # "de-branding" and "re-branding"
    ./scripts/config --set-str CONFIG_BUILD_SALT ''
    ./scripts/config --set-str CONFIG_LOCALVERSION "${KERNEL_LOCALVERSION}"

    # no need to have these keys, not a prod kernel
    ./scripts/config --set-str CONFIG_SYSTEM_TRUSTED_KEYS ''
    ./scripts/config --set-str CONFIG_SYSTEM_REVOCATION_KEYS ''

    # disable AEGIS-128 (ARM{,64} NEON})
    # https://github.com/NixOS/nixpkgs/issues/74744
    # plus, this kernel won't run in "prod", so this isn't even a "nice to have"
    ./scripts/config --disable CONFIG_CRYPTO_AEGIS128_SIMD

    # sched_ext
    ./scripts/config --disable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT
    ./scripts/config --enable CONFIG_DEBUG_INFO_DWARF5
    ./scripts/config --enable CONFIG_PAHOLE_HAS_BTF_TAG
    ./scripts/config --enable CONFIG_SCHED_CLASS_EXT

    # enable Rust, conditionally
    enable_rust_config

    # final config rebuild before kernel build
    make olddefconfig
}
function configure_kernel() {
    if [[ "${CLEAN_BUILD}" == '1' ]]; then
        rm -vf .config*
        $SUDO_ALIAS make distclean
    fi

    if [[ -z "${KERNEL_CONFIG}" ]]; then
        # $KERNEL_CONFIG is empty, meaning, use the current kernel's config

        # in-built kernel config is always the trusted source
        # remember, /boot/config-$(uname -r) can be modified by the root user
        if [[ -f '/proc/config.gz' ]]; then
            zcat /proc/config.gz > .config
        elif [[ -f "/boot/config-$(uname -r)" ]]; then
            cp "/boot/config-$(uname -r)" .config
        else
            echo 'ERROR: could not find the config for the current kernel'
            exit 3
        fi

    # maybe the user has a specific kernel config to use
    elif [[ -f "${KERNEL_CONFIG}" ]]; then
        cp "${KERNEL_CONFIG}" .config

    else
        # **build** a kernel config
        # e.g. `make defconfig`
        make "${KERNEL_CONFIG}"

    fi

    # add my own modifications
    modify_kernel_config
}

function build_kernel() {
    # shellcheck disable=SC2086
    make $MAX_PARALLEL_JOBS all
}

function install_kernel() {
    if [[ "${INSTALL_ZE_KERNEL}" == '1' ]]; then
        if grep nixos /etc/os-release > /dev/null && [[ "${FORCE_INSTALL_ZE_KERNEL}" == '0' ]]; then
            echo 'NixOS detected. Not installing kernel. Set FORCE_INSTALL_ZE_KERNEL=1 to override.'
        else

        if find "arch/$kernel_arch/boot/dts" -name "*.dtb" -print -quit > /dev/null; then
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

configure_kernel
build_kernel
install_kernel
