#!/usr/bin/env bash

# **DON'T DISABLE PATHNAME EXPANSION WITH `set -f`**
set -xeu -o pipefail

function build_kernel() {
    # shellcheck disable=SC1003
    grep 'dpkg-buildpackage \\' scripts/Makefile.package && \
        sed -i 's/dpkg-buildpackage \\/dpkg-buildpackage -d \\/g' scripts/Makefile.package
    # shellcheck disable=SC2086
    make $MAX_PARALLEL_JOBS bindeb-pkg
}

function install_kernel() {
    if [[ "${INSTALL_ZE_KERNEL}" == '1' ]]; then
        sudo dpkg -i ../linux*"$(make -s kernelrelease)"*.deb
    fi
}


if [[ -z "${1:-}" ]]; then
    "$(dirname "$0")/configure-kernel.sh"
    build_kernel
    install_kernel
else
    dpkg -l | grep "$1" | awk '{print $2}' | xargs sudo dpkg -r
fi
