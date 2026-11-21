#!/bin/bash
# bootc disklerini test için QEMU'da açar ve yönetir.
#
#   vm-test.sh start  <ad> <disk> <cloud-init-dizini> [veri-diski]
#                                                        makineyi açar; veri diski yoksa
#                                                        boş olarak açılır ve korunur
#   vm-test.sh wait   <ad> [saniye]                      SSH hazır olana kadar bekler
#   vm-test.sh ssh    <ad> [komut...]                    makinede komut çalıştırır (stdin geçer)
#   vm-test.sh reboot <ad>                               kapatıp aynı diskle yeniden açar
#   vm-test.sh stop   <ad>                               makineyi kapatır
#
# <cloud-init-dizini>: user-data, meta-data ve isteğe bağlı network-config.
# user-data içindeki @SSH_PUBKEY@ test anahtarıyla değiştirilir.
#
# Her makinenin iki ağ kartı vardır:
#   1. QEMU user ağı: internet ve host'tan SSH (127.0.0.1:<port>), host 10.0.2.2
#   2. Test segmenti: aynı VMTEST_SEGMENT'teki makineler arasında ortak L2 ağı
#
# Ortam değişkenleri:
#   VMTEST_DIR           durum dizini (varsayılan /tmp/vm-test)
#   VMTEST_SEGMENT       test segmentinin UDP multicast portu (varsayılan 31234)
#   VMTEST_MEMORY        MB (varsayılan 3072)
#   VMTEST_DIRECT_KERNEL 1 ise önyükleyici yerine diskin BLS girdisindeki çekirdekle açar
#                        (önyükleyicisi olmayan diskler için; ham disk ve root gerekir)
set -euo pipefail

dir=${VMTEST_DIR:-/tmp/vm-test}
mkdir -p "$dir"
key="$dir/id_ed25519"
[ -f "$key" ] || ssh-keygen -q -t ed25519 -N '' -C vm-test -f "$key"

ssh_opts=(-i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
          -o LogLevel=ERROR -o ConnectTimeout=5 -o BatchMode=yes)

vm_ssh() {
    local name=$1; shift
    ssh "${ssh_opts[@]}" -p "$(cat "$dir/$name/port")" librenfra@127.0.0.1 "$@"
}

boot() {
    local name=$1 m="$dir/$1"
    local disk; disk=$(cat "$m/disk")
    local accel=tcg,thread=multi cpu=max
    if [ -w /dev/kvm ]; then accel=kvm; cpu=host; fi
    local kargs=() data=()
    # Proxmox'taki gibi: veri diski "lnfr-data" seri numarasıyla takılır.
    if [ -s "$m/data" ]; then
        data=(-drive file="$(cat "$m/data")",format=qcow2,if=none,id=data
              -device virtio-blk-pci,drive=data,serial=lnfr-data)
    fi
    if [ "${VMTEST_DIRECT_KERNEL:-0}" = 1 ]; then
        direct_kernel "$m" "$disk"
        kargs=(-kernel "$m/vmlinuz" -initrd "$m/initrd" -append "$(cat "$m/cmdline") console=ttyS0")
    fi
    local mac; mac=$(printf '52:54:00:%s' "$(echo -n "$name" | md5sum | sed 's/^\(..\)\(..\)\(..\).*/\1:\2:\3/')")
    qemu-system-x86_64 -accel "$accel" -cpu "$cpu" -smp 2 -m "${VMTEST_MEMORY:-3072}" \
        "${kargs[@]}" \
        -drive file="$disk",format="$(cat "$m/format")",if=virtio \
        -drive file="$m/seed.iso",format=raw,if=virtio,readonly=on \
        "${data[@]}" \
        -netdev user,id=n0,hostfwd=tcp:127.0.0.1:"$(cat "$m/port")"-:22 \
        -device virtio-net-pci,netdev=n0 \
        -netdev socket,id=n1,mcast=230.0.0.1:"${VMTEST_SEGMENT:-31234}" \
        -device virtio-net-pci,netdev=n1,mac="$mac" \
        -display none -serial file:"$m/console.log" \
        -pidfile "$m/pid" -daemonize
}

# ostree'nin en yüksek "version" numaralı BLS girdisi, önyükleyicinin seçeceği girdidir.
direct_kernel() {
    local m=$1 disk=$2 mnt; mnt=$(mktemp -d)
    local loop; loop=$(losetup -fP --show "$disk")
    partx -u "$loop" 2>/dev/null || true
    local nr; nr=$(partx -g -o NR,TYPE "$disk" | awk '$2=="4f68bce3-e8cd-4db1-96e7-fbcaf984b709"{print $1}')
    local root="${loop}p${nr}"
    mount -o ro "$root" "$mnt"
    local entry; entry=$(for f in "$mnt"/boot/loader/entries/*.conf; do
        echo "$(awk '/^version/{print $2}' "$f") $f"; done | sort -rn | head -1 | cut -d' ' -f2)
    cp "$mnt$(awk '/^linux/{print $2}' "$entry")" "$m/vmlinuz"
    cp "$mnt$(awk '/^initrd/{print $2}' "$entry")" "$m/initrd"
    sed -n 's/^options //p' "$entry" > "$m/cmdline"
    umount "$mnt"; losetup -d "$loop"; rmdir "$mnt"
}

running() { [ -f "$dir/$1/pid" ] && kill -0 "$(cat "$dir/$1/pid")" 2>/dev/null; }

case ${1:-} in
start)
    name=$2 disk=$3 ci=$4 data=${5:-} m="$dir/$2"
    running "$name" && { echo "$name zaten çalışıyor" >&2; exit 1; }
    rm -rf "$m"; mkdir -p "$m"
    # Test diski temel diskin kopyasıdır; temel disk değişmez.
    if [ "${VMTEST_DIRECT_KERNEL:-0}" = 1 ]; then
        cp --sparse=always "$disk" "$m/disk.raw"; echo "$m/disk.raw" > "$m/disk"; echo raw > "$m/format"
    else
        qemu-img create -q -f qcow2 -F "$(qemu-img info --output=json "$disk" | python3 -c 'import json,sys;print(json.load(sys.stdin)["format"])')" \
            -b "$(realpath "$disk")" "$m/disk.qcow2"
        echo "$m/disk.qcow2" > "$m/disk"; echo qcow2 > "$m/format"
    fi
    if [ -n "$data" ]; then
        [ -f "$data" ] || qemu-img create -q -f qcow2 "$data" 8G
        realpath "$data" > "$m/data"
    fi
    python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])' > "$m/port"
    mkdir -p "$m/seed"
    sed "s|@SSH_PUBKEY@|$(cat "$key.pub")|" "$ci/user-data" > "$m/seed/user-data"
    cp "$ci/meta-data" "$m/seed/"
    [ -f "$ci/network-config" ] && cp "$ci/network-config" "$m/seed/"
    genisoimage -quiet -output "$m/seed.iso" -volid cidata -joliet -rock "$m/seed"/*
    boot "$name"
    echo "$name açıldı: ssh -p $(cat "$m/port") librenfra@127.0.0.1"
    ;;
wait)
    name=$2 timeout=${3:-900} t=0
    until vm_ssh "$name" true 2>/dev/null; do
        sleep 5; t=$((t+5))
        [ "$t" -ge "$timeout" ] && { echo "$name: $timeout saniyede SSH açılmadı" >&2; tail -20 "$dir/$name/console.log" >&2; exit 1; }
    done
    # cloud-init ve açılış işleri bitene kadar bekle
    vm_ssh "$name" 'cloud-init status --wait >/dev/null 2>&1; systemctl is-system-running --wait >/dev/null 2>&1; true'
    ;;
ssh)
    name=$2; shift 2
    vm_ssh "$name" "$@"
    ;;
reboot)
    name=$2
    timeout 20 ssh "${ssh_opts[@]}" -p "$(cat "$dir/$name/port")" librenfra@127.0.0.1 'sudo systemctl poweroff' 2>/dev/null || true
    while running "$name"; do sleep 2; done
    boot "$name"
    ;;
stop)
    name=$2
    running "$name" || exit 0
    timeout 20 ssh "${ssh_opts[@]}" -p "$(cat "$dir/$name/port")" librenfra@127.0.0.1 'sudo systemctl poweroff' 2>/dev/null || true
    for _ in $(seq 60); do running "$name" || exit 0; sleep 2; done
    kill "$(cat "$dir/$name/pid")"
    ;;
*)
    sed -n '2,20p' "$0"; exit 2
    ;;
esac
