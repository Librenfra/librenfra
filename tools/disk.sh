#!/bin/bash
# Yerel container deposundaki bir bootc imajından açılabilir bir qcow2 disk üretir.
# Kullanım: tools/disk.sh <yerel-imaj> <hedef-imgref> <çıktı.qcow2> [boyut]
#   <hedef-imgref>: kurulan sistemin `bootc upgrade` ile izleyeceği adres,
#                   ör. ghcr.io/librenfra/dc:0.1.0
#   DISK_KARGS:     isteğe bağlı, boşlukla ayrılmış ek çekirdek argümanları (ör. console=ttyS0,115200)
# Gereken: podman (root), qemu-img
set -euo pipefail

image=$1 target=$2 out=$3 size=${4:-20G}
kargs=()
for k in ${DISK_KARGS:-}; do kargs+=(--karg "$k"); done
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

truncate -s "$size" "$work/disk.raw"
podman run --rm --privileged --pid=host \
    --security-opt label=type:unconfined_t \
    -v /var/lib/containers:/var/lib/containers \
    -v /dev:/dev \
    -v "$work":/output \
    "$image" \
    bootc install to-disk --via-loopback --generic-image --wipe \
        --filesystem xfs \
        --target-imgref "$target" \
        "${kargs[@]}" \
        /output/disk.raw
qemu-img convert -c -O qcow2 "$work/disk.raw" "$out"
echo "$out"
