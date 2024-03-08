#!/usr/bin/env dash

set -x
KERNEL_LOCALVERSION="-$(date +%Y.%m.%d.%H%M)"
export KERNEL_LOCALVERSION
"$(dirname "$0")/unwrapped-build-kernel-and-install.sh" "$@" 2>&1 | tee "build-$(make -s kernelversion)${KERNEL_LOCALVERSION}.log"
