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
# user-data içinde:
#   @SSH_PUBKEY@   test anahtarıyla
#   @B64:<dosya>@  VMTEST_FILES dizinindeki dosyanın base64 içeriğiyle değiştirilir
#                  (write_files'ta "encoding: b64" ile; ör. test sertifikaları)
#
# Her makinenin iki ağ kartı vardır:
#   1. QEMU user ağı: internet ve host'tan SSH (127.0.0.1:<port>), host 10.0.2.2
#   2. Test segmenti: aynı VMTEST_SEGMENT'teki makineler arasında ortak L2 ağı.
#      Adresi network-config ile verilir.
# Kart adları dağıtıma göre değiştiği için network-config kartları MAC adresiyle seçer:
# @NIC0_MAC@ ve @NIC1_MAC@ makinenin adresleriyle değiştirilir.
#
# Ortam değişkenleri:
#   VMTEST_DIR           durum dizini (varsayılan /tmp/vm-test)
#   VMTEST_SEGMENT       test segmentinin UDP multicast portu (varsayılan 31234)
#   VMTEST_MEMORY        MB (varsayılan 3072)
#   VMTEST_FILES         @B64:...@ yer tutucularının okunduğu dizin
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

# Segmentteki MAC adresi makinenin adından türetilir; segmentte her makineninki farklıdır.
segment_mac() {
    printf '52:54:00:%s' "$(echo -n "$1" | md5sum | sed 's/^\(..\)\(..\)\(..\).*/\1:\2:\3/')"
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
    local mac; mac=$(segment_mac "$name")
    qemu-system-x86_64 -accel "$accel" -cpu "$cpu" -smp 2 -m "${VMTEST_MEMORY:-3072}" \
        "${kargs[@]}" \
        -drive file="$disk",format="$(cat "$m/format")",if=none,id=root \
        -device virtio-blk-pci,drive=root,bootindex=0 \
        -drive file="$m/seed.iso",format=raw,if=virtio,readonly=on \
        "${data[@]}" \
        -netdev user,id=n0,hostfwd=tcp:127.0.0.1:"$(cat "$m/port")"-:22 \
        -device virtio-net-pci,netdev=n0,mac=52:54:00:12:34:56 \
        -netdev socket,id=n1,mcast=230.0.0.1:"${VMTEST_SEGMENT:-31234}" \
        -device virtio-net-pci,netdev=n1,mac="$mac" \
        -display none -serial file:"$m/console.log" \
        -chardev file,id=bios,path="$m/bios.log" -device isa-debugcon,iobase=0x402,chardev=bios \
        -monitor unix:"$m/monitor.sock",server=on,wait=off \
        -pidfile "$m/pid" -daemonize 2>"$m/qemu.log"
}

# Açılmayan makine için: seri konsol, firmware (SeaBIOS) kaydı ve ekranın görüntüsü (screen.ppm).
diagnose() {
    local m="$dir/$1"
    echo "--- $1: seri konsol (son satırlar)" >&2; tail -60 "$m/console.log" >&2
    echo "--- $1: firmware" >&2; tail -30 "$m/bios.log" >&2
    echo "--- $1: qemu" >&2; cat "$m/qemu.log" >&2 2>/dev/null || true
    echo "--- $1: monitor" >&2
    python3 - "$m/monitor.sock" "$m/screen.ppm" <<'PY2' >&2 || true
import re, socket, sys, time
s = socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])
out = b""
for cmd in ("info status", "info registers", f"screendump {sys.argv[2]}"):
    s.sendall(cmd.encode() + b"\n"); time.sleep(1)
s.settimeout(2)
try:
    while True:
        b = s.recv(65536)
        if not b: break
        out += b
except socket.timeout:
    pass
s.close()
# Monitörün satır düzenleyicisi her tuşu yankılar; yalnızca komutların çıktısı kalır.
text = re.sub(r"\x1b\[[0-9;]*[A-Za-z]", "", out.decode(errors="replace"))
lines = [l.rstrip("\r").split("\r")[-1] for l in text.split("\n")]
print("\n".join(l for l in lines if l.strip() and not l.startswith(("(qemu)", "QEMU "))))
PY2
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
    python3 - "$ci/user-data" "$key.pub" "${VMTEST_FILES:-}" > "$m/seed/user-data" <<'PY'
import base64, os, re, sys
text, pub, files = open(sys.argv[1]).read(), open(sys.argv[2]).read().strip(), sys.argv[3]
def b64(m):
    return base64.b64encode(open(os.path.join(files, m.group(1)), "rb").read()).decode()
print(re.sub(r"@B64:([^@]+)@", b64, text.replace("@SSH_PUBKEY@", pub)), end="")
PY
    cp "$ci/meta-data" "$m/seed/"
    if [ -f "$ci/network-config" ]; then
        sed -e "s|@NIC0_MAC@|52:54:00:12:34:56|g" -e "s|@NIC1_MAC@|$(segment_mac "$name")|g" \
            "$ci/network-config" > "$m/seed/network-config"
    fi
    genisoimage -quiet -output "$m/seed.iso" -volid cidata -joliet -rock "$m/seed"/*
    boot "$name"
    echo "$name açıldı: ssh -p $(cat "$m/port") librenfra@127.0.0.1"
    ;;
wait)
    name=$2 timeout=${3:-900} t=0
    until vm_ssh "$name" true 2>/dev/null; do
        sleep 5; t=$((t+5))
        [ "$t" -ge "$timeout" ] && { echo "$name: $timeout saniyede SSH açılmadı" >&2; diagnose "$name"; exit 1; }
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
