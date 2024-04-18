#!/usr/bin/env bash

# **DON'T DISABLE PATHNAME EXPANSION WITH `set -f`**
set -xeu -o pipefail

function build_kernel() {
    grep -q 'BuildRequires' scripts/package/kernel.spec && \
        sed -i '/BuildRequires.*/d' scripts/package/kernel.spec
    grep -q '_smp_mflags %{nil}' scripts/Makefile.package && \
        sed -i "s/_smp_mflags %{nil}/_smp_mflags ${MAX_PARALLEL_JOBS}/g" scripts/Makefile.package

    time make binrpm-pkg
}

function install_kernel() {
    if [[ "${INSTALL_ZE_KERNEL}" == '1' ]]; then
        sudo dnf localinstall --assumeyes "rpmbuild/RPMS/$(uname -m)"/*."$(uname -m).rpm"
    fi
}


if [[ -z "${1:-}" ]]; then
    "$(dirname "$0")/configure-kernel.sh"
    build_kernel
    install_kernel
else
    # shellcheck disable=SC2046
    sudo dnf remove --assumeyes $(rpm -qa | grep '^kernel' | grep "$1")
fi
