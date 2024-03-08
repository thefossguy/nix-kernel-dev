#!/usr/bin/env bash

set -xeuf

qemu-kvm \
    -machine virt \
    -cpu host \
    -smp 2 \
    -m 2048 \
    -accel kvm \
    -nographic \
    -kernel "$1" \
    -hda "$2" \
    -netdev user,id=mynet0,hostfwd=tcp::6902-:22 \
    -device virtio-net-pci,netdev=mynet0 \
    -append 'root=/dev/vda rw systemd.show_status=false'
