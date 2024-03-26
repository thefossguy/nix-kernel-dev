#!/usr/bin/env bash

set -xeu -o pipefail

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
    ./scripts/config --disable CONFIG_LOCALVERSION_AUTO

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

configure_kernel
