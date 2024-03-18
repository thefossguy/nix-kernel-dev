#!/usr/bin/env dash

set -x
KERNEL_LOCALVERSION="-$(date +%Y.%m.%d.%H%M)"
export KERNEL_LOCALVERSION

if [ -z "${REMOVE_KERNEL}" ]; then
    "$(dirname "$0")/unwrapped-build-kernel-and-install.sh" 2>&1 | tee "build-$(make -s kernelversion)${KERNEL_LOCALVERSION}.log"
else
    "$(dirname "$0")/unwrapped-build-kernel-and-install.sh"
fi
