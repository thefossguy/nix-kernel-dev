#!/usr/bin/env bash

set -xeu -o pipefail

function kconfigure() {
    set +x
    OPERATIONS=( "$@" )

    for current_operation in "${OPERATIONS[@]}"; do
        operation="$(echo "${current_operation}" | awk -F' ' '{print $1}')"
        config_option="$(echo "${current_operation}" | awk -F' ' '{print $2}')"

        if [[ "${operation}" == '--set-str' ]]; then
            optional_str="$(echo "${current_operation}" | awk -F' ' '{print $3}')"
            ./scripts/config --set-str "${config_option}" "${optional_str:-}"
        else
            ./scripts/config "${operation}" "${config_option}"
        fi
    done
    make olddefconfig

    wrongly_configured_options=0
    for current_operation in "${OPERATIONS[@]}"; do
        operation="$(echo "${current_operation}" | awk -F' ' '{print $1}')"
        config_option="$(echo "${current_operation}" | awk -F' ' '{print $2}')"

        if [[ "${operation}" == '--disable' ]]; then
            str_to_check="# ${config_option} is not set"
        elif [[ "${operation}" == '--enable' ]]; then
            str_to_check="${config_option}=y"
        elif [[ "${operation}" == '--module' ]]; then
            str_to_check="${config_option}=m"
        elif [[ "${operation}" == '--set-str' ]]; then
            optional_str="$(echo "${current_operation}" | awk -F' ' '{print $3}')"
            str_to_check="${config_option}=\"${optional_str:-}\""
        fi

        if ! grep -q "${config_option}" .config; then
            wrongly_configured_options=1
            echo "WARN: missing option '${config_option}'; expected '${str_to_check}'"
        elif ! grep -q "${str_to_check}" .config; then
            wrongly_configured_options=1
            actual_configured_option="$(grep "${config_option}=\|${config_option} " .config)"
            echo "ERROR: misconfigured option '${config_option}'; expected '${str_to_check}'; found '${actual_configured_option}'"
        fi
    done
    if [[ "${wrongly_configured_options}" == '1' ]]; then
        exit 1
    fi
}

function setup_rust_toolchain() {
    RUSTUP_OVERRIDE_DIR_PATH="$(dirname "$(dirname "$PWD")")"
    if [[ "${RUSTUP_OVERRIDE_DIR_PATH}" == *'/nix-kernel-dev' || "${RUSTUP_OVERRIDE_DIR_PATH}" == *'/freax' ]]; then
        RUSTUP_OVERRIDE_SUFFIX="--path ${RUSTUP_OVERRIDE_DIR_PATH}"
    fi

    # shellcheck disable=SC2086
    rustup override set "$(scripts/min-tool-version.sh rustc)" ${RUSTUP_OVERRIDE_SUFFIX}
    rustup component add rust-src rustfmt clippy
    cargo install --locked --version "$(scripts/min-tool-version.sh bindgen)" bindgen-cli

    # shellcheck disable=SC2155
    export RUST_LIB_SRC="$(rustc --print sysroot)/lib/rustlib/src/rust/library"
}

function modify_kernel_config() {
    # start with a "useful" base config
    make olddefconfig

    # "de-branding" and "re-branding"
    DEBRAND_CONFIG=(
        '--disable CONFIG_LOCALVERSION_AUTO'
        '--set-str CONFIG_BUILD_SALT'
        "--set-str CONFIG_LOCALVERSION ${KERNEL_LOCALVERSION}"
    )

    # built-in kernel config+headers
    IK_CONFIG=(
        '--enable CONFIG_IKCONFIG'
        '--enable CONFIG_IKCONFIG_PROC'
        '--enable CONFIG_IKHEADERS'
    )

    # defconfig does not enable these
    DEFCONFIG_ADD_ONS=(
        '--module CONFIG_XFS_FS'
        '--module CONFIG_ZRAM'
    )

    # no need to have these keys, not a prod kernel
    SIGNING_REMOVAL=(
        '--disable CONFIG_SYSTEM_REVOCATION_LIST'
        '--set-str CONFIG_SYSTEM_TRUSTED_KEYS'
    )
    if grep -q 'debian' /etc/os-release; then
        SIGNING_REMOVAL+=(
            '--set-str CONFIG_SYSTEM_REVOCATION_KEYS'
        )
    elif grep -q 'fedora' /etc/os-release; then
        SIGNING_REMOVAL+=(
            #'--disable CONFIG_MODULE_SIG'
            '--disable CONFIG_MODULE_SIG_ALL'
            '--set-str CONFIG_MODULE_SIG_KEY'
        )
    fi

    # disable AEGIS-128 (ARM{,64} NEON})
    # https://github.com/NixOS/nixpkgs/issues/74744
    # plus, this kernel won't run in "prod", so this isn't even a "nice to have"
    ARM_SIMD_DISABLE=(
        '--disable CONFIG_CRYPTO_AEGIS128_SIMD'
    )

    if [[ "${BUILD_WITH_RUST:-0}" == '1' ]] && [[ "${LLVM:-0}" == '1' ]]; then
        setup_rust_toolchain
        make rustavailable
        RUST_CONFIG=(
            '--enable CONFIG_RUST'
            '--enable CONFIG_RUST_OVERFLOW_CHECKS'
            '--enable CONFIG_RUST_BUILD_ASSERT_ALLOW'
        )

    else
        # shellcheck disable=SC2016
        echo 'WARNING: $BUILD_WITH_RUST or $LLVM is unset, not building with Rust'
    fi

    # sched_ext
    if [[ -n "${COMPILING_SCHED_EXT:-}" ]]; then
        SCHED_EXT_CONFIG=(
            '--disable CONFIG_DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT'
            '--enable CONFIG_DEBUG_INFO_DWARF5'
            '--enable CONFIG_PAHOLE_HAS_BTF_TAG'
            '--enable CONFIG_SCHED_CLASS_EXT'
        )
    else
        SCHED_EXT_CONFIG=()
    fi

    # debug options
    DEBUG_CONFIG=(
        '--enable CONFIG_ARCH_WANT_FRAME_POINTERS'
        '--enable CONFIG_DEBUG_BUGVERBOSE'
        '--enable CONFIG_DEBUG_DRIVER'
        '--enable CONFIG_DEBUG_FS'
        '--enable CONFIG_DEBUG_FS_ALLOW_ALL'
        '--enable CONFIG_DEBUG_INFO'
        '--enable CONFIG_DEBUG_KERNEL'
        '--enable CONFIG_DEBUG_MISC'
        '--enable CONFIG_DYNAMIC_DEBUG'
        '--enable CONFIG_DYNAMIC_DEBUG_CORE'
        '--enable CONFIG_FRAME_POINTER'
        '--enable CONFIG_GDB_SCRIPTS'
        '--enable CONFIG_KALLSYMS'
        '--enable CONFIG_KASAN'
        '--enable CONFIG_KGDB'
        '--enable CONFIG_KGDB_KDB'
        '--enable CONFIG_KGDB_SERIAL_CONSOLE'
        '--enable CONFIG_KASAN'
        '--enable CONFIG_LOCK_TORTURE_TEST'
        '--enable CONFIG_LOCKDEP'
        '--enable CONFIG_LOCKUP_DETECTOR'
        '--enable CONFIG_PRINTK_CALLER'
        '--enable CONFIG_PRINTK_TIME'
        '--enable CONFIG_PROVE_LOCKING'
        '--enable CONFIG_STRICT_KERNEL_RWX'
        '--enable CONFIG_UBSAN'
    )
    if [[ "$(uname -m)" == 'x86_64' ]]; then
        DEBUG_CONFIG+=(
            '--enable CONFIG_STACK_VALIDATION'
        )
    fi

    CUSTOM_CONFIG=(
        "${DEBRAND_CONFIG[@]}"
        "${IK_CONFIG[@]}"
        "${DEFCONFIG_ADD_ONS[@]}"
        "${SIGNING_REMOVAL[@]}"
        "${ARM_SIMD_DISABLE[@]}"
        "${RUST_CONFIG[@]}"
        "${SCHED_EXT_CONFIG[@]}"
        "${DEBUG_CONFIG[@]}"
    )
    kconfigure "${CUSTOM_CONFIG[@]}"
}

function configure_kernel() {
    if [[ "${CLEAN_BUILD}" == '1' ]]; then
        rm -vf .config*
        if [[ "$(git rev-parse --is-inside-work-tree)" == 'true' ]]; then
            git clean -x -d -f
        fi
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
