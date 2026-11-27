#!/bin/bash
# Firewall testi: temiz bir OPNsense'e ilk ayarı içe aktarır, firewall/ayar.yml'yi uygular ve
# segmentler arası erişimi ağ ad alanlarından sınar. QEMU'yu ve ad alanlarını kendisi kurar;
# root olarak çalışır.
#
#   OPNSENSE_IMAGE=<imzası doğrulanmış nano .img> tests/firewall/test.sh <çalışma dizini>
#
# Gerekenler: qemu-system-x86_64, genisoimage, tofu, ansible-playbook (ansibleguy.opnsense
# koleksiyonu ve python httpx ile), python3, curl, dnsmasq, ip.
# TEST_SKIP: atlanacak denetimlerin adlarına uyan bir düzenli ifade.
# OPS_IMAGE: ayarı bu ops imajının içinden uygular (podman).
# QEMU_CPU: QEMU işlemci modeli. TCG'de AVX2'li modeller OPNsense'in ZFS modülünü çökertir.
set -uo pipefail
repo=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mkdir -p "$1" && cd "$1" && pwd)
image=${OPNSENSE_IMAGE:?OPNSENSE_IMAGE gerekli}
here=$repo/tests/firewall
pass=0 fail=0
pids=()

check() {
    local name=$1; shift
    if [ -n "${TEST_SKIP:-}" ] && [[ $name =~ $TEST_SKIP ]]; then echo "ATLANDI $name"; return; fi
    if out=$("$@" 2>&1); then echo "GEÇTİ  $name"; pass=$((pass+1))
    else echo "KALDI  $name"; echo "$out" | tail -5 | sed 's/^/       /'; fail=$((fail+1)); fi
}
fails() { ! "$@"; }
retry() { local end=$((SECONDS + $1)); shift; until "$@"; do [ $SECONDS -ge $end ] && return 1; sleep 3; done; }
in_ns() { local ns=$1; shift; ip netns exec "lnfr-$ns" "$@"; }
probe() { in_ns "$1" python3 "$here/net.py" probe "$2" "$3" "$4"; }

cleanup() {
    for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
    for ns in home lan dmz lab; do
        ip netns pids "lnfr-$ns" 2>/dev/null | xargs -r kill 2>/dev/null
        ip netns del "lnfr-$ns" 2>/dev/null
        ip link del "lnfr-t-$ns" 2>/dev/null
        ip link del "lnfr-b-$ns" 2>/dev/null
    done
}
trap cleanup EXIT

# --- Ağ: her segment bir köprü; firewall'un tap'i ve bir istemci ad alanı köprüye bağlı. ---
# home ev ağıdır (192.168.1.1 ev yönlendiricisi, 198.51.100.10 "internet"). lan'da dc
# (10.10.10.10) ve ops (10.10.10.30), dmz'de mail (10.10.20.10), lab'da bir deneme makinesi var.
segment() {
    local ns=$1 gw=$2; shift 2
    ip link add "lnfr-b-$ns" type bridge && ip link set "lnfr-b-$ns" up
    ip tuntap add dev "lnfr-t-$ns" mode tap && ip link set "lnfr-t-$ns" master "lnfr-b-$ns" up
    ip netns add "lnfr-$ns"
    ip link add "lnfr-v-$ns" type veth peer name eth0 netns "lnfr-$ns"
    ip link set "lnfr-v-$ns" master "lnfr-b-$ns" up
    in_ns "$ns" ip link set lo up; in_ns "$ns" ip link set eth0 up
    for a in "$@"; do in_ns "$ns" ip addr add "$a" dev eth0; done
    [ -n "$gw" ] && in_ns "$ns" ip route add default via "$gw"
    mkdir -p "/etc/netns/lnfr-$ns"
    echo "nameserver ${gw:-192.168.1.1}" > "/etc/netns/lnfr-$ns/resolv.conf"
}
cleanup
set -e
segment home "" 192.168.1.1/24
in_ns home ip addr add 198.51.100.10/32 dev lo
segment lan 10.10.10.1 10.10.10.10/24 10.10.10.30/24
segment dmz 10.10.20.1 10.10.20.10/24
segment lab 10.10.30.1 10.10.30.50/24
listen() { ip netns exec "lnfr-$1" python3 "$here/net.py" listen "${@:2}" & pids+=($!); }
listen home 198.51.100.10 tcp:80
listen home 192.168.1.1 tcp:8080
listen lan 10.10.10.10 tcp:22 tcp:88 udp:88 tcp:445 tcp:464 udp:464 tcp:636
listen lan 10.10.10.30 tcp:636
listen dmz 10.10.20.10 tcp:25
ip netns exec lnfr-lan dnsmasq --keep-in-foreground --no-resolv --no-hosts --bind-interfaces \
    --listen-address=10.10.10.10 --address=/dc.test.lan/10.10.10.10 --pid-file= & pids+=($!)

# --- İlk ayar: test sertifikaları, config.xml, temiz kurulum ve içe aktarma ---
bash "$repo/tools/test-pki.sh" "$work/pki" fw.test.lan,10.10.10.1 >/dev/null
umask 077
printf 'key=librenfra-test-key\nsecret=librenfra-test-secret\n' > "$work/fw-api.txt"
mkdir -p "$work/render"
# Yerel modül yolu göreli olmalı; mutlak yol modülü .terraform'a kopyalar ve şablonu bulamaz.
module=$(realpath --relative-to="$work/render" "$repo/infra/modules/opnsense-config")
case $module in ../*) ;; *) module=./$module ;; esac
cat > "$work/render/main.tf" <<EOF
module "config" {
  source             = "$module"
  domain             = "test.lan"
  dns_servers        = ["192.168.1.1"]
  wan_address        = "192.168.1.201/24"
  wan_gateway        = "192.168.1.1"
  root_password_hash = bcrypt("test-root-parola")
  api_password_hash  = bcrypt("test-api-parola")
  api_key            = "librenfra-test-key"
  api_secret_hash    = bcrypt("librenfra-test-secret")
  tls_cert           = file("$work/pki/fw.test.lan-cert.pem")
  tls_key            = file("$work/pki/fw.test.lan-key.pem")
  segments = {
    lan = { ifname = "lan", device = "vtnet1", address = "10.10.10.1/24" }
    dmz = { ifname = "opt1", device = "vtnet2", address = "10.10.20.1/24" }
    lab = { ifname = "opt2", device = "vtnet3", address = "10.10.30.1/24" }
  }
}
output "config" {
  value     = module.config.config_xml
  sensitive = true
}
EOF
(cd "$work/render" && rm -f terraform.tfstate && tofu init -input=false >/dev/null && tofu apply -auto-approve -input=false >/dev/null &&
    tofu output -raw config) > "$work/config.xml"
umask 022
rm -rf "$work/cd" && mkdir -p "$work/cd/conf" && cp "$work/config.xml" "$work/cd/conf/"
genisoimage -quiet -R -V LNFRCFG -o "$work/config.iso" "$work/cd"
rm -f "$work/fw.qcow2" "$work/console.sock"
qemu-img create -q -f qcow2 -F raw -b "$image" "$work/fw.qcow2" 16G
nic() { echo "-netdev tap,id=$1,ifname=lnfr-t-$1,script=no,downscript=no -device virtio-net-pci,netdev=$1"; }
# nic'in çıktısı bilerek bölünür: her kart iki QEMU argümanıdır.
# shellcheck disable=SC2046
qemu-system-x86_64 -machine q35 -accel "${QEMU_ACCEL:-kvm:tcg}" -cpu "${QEMU_CPU:-qemu64}" -smp 2 -m 2048 \
    -nographic -display none -monitor none \
    -drive "file=$work/fw.qcow2,if=virtio,format=qcow2" \
    -drive "file=$work/config.iso,media=cdrom,if=none,id=cd" -device ide-cd,drive=cd,bus=ide.2 \
    $(nic home) $(nic lan) $(nic dmz) $(nic lab) \
    -chardev "socket,id=s0,path=$work/console.sock,server=on,wait=on,logfile=$work/console.log" \
    -serial chardev:s0 > "$work/qemu.log" 2>&1 & pids+=($!)
for _ in $(seq 100); do [ -S "$work/console.sock" ] && break; sleep 0.2; done
set +e
import_config() {
    python3 "$repo/firewall/import-config" --socket "$work/console.sock" --log "$work/import.log" "$work/config.xml" ||
        { echo "--- konsol (son satırlar)"; tail -c 3000 "$work/import.log" 2>/dev/null | tail -25; return 1; }
}
check "config.xml ilk açılışta içe aktarıldı" import_config

api_is() { [ "$(in_ns lan curl -sS -m 60 --cacert "$work/pki/ca.pem" -u "$2" -o /dev/null -w '%{http_code}' \
    "https://10.10.10.1/api/$3")" = "$1" ]; }
check "API: LAN'dan, sertifika CA ile doğrulanıyor" api_is 200 librenfra-test-key:librenfra-test-secret firewall/alias/get
check "API: yanlış anahtar reddediliyor" api_is 401 librenfra-test-key:yanlis firewall/alias/get

# --- Ayar ---
cat > "$work/vars.yml" <<EOF
fw_host: 10.10.10.1
fw_credentials: $work/fw-api.txt
fw_ca: $work/pki/ca.pem
domain: test.lan
dc_address: 10.10.10.10
EOF
# Ayar LAN'dan, ops'un yerinden uygulanır. OPS_IMAGE verilirse ops imajının içindeki Ansible ve
# koleksiyonla (ortamdaki sürümlerle) çalışır. Lab ortamının vekil değişkenleri ad alanında geçersizdir.
play() {
    if [ -n "${OPS_IMAGE:-}" ]; then
        # İmajda /mnt ve /home /var'a bağlantıdır ve hedefleri yoktur; dizinler sabit yerlere bağlanır.
        sed "s|$work|/work|g" "$work/vars.yml" > "$work/vars-ops.yml"
        podman run --rm --http-proxy=false --network ns:/run/netns/lnfr-lan -v "$repo:/repo:ro" -v "$work:/work:ro" \
            -e ANSIBLE_LOCALHOST_WARNING=False -e ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
            "$OPS_IMAGE" ansible-playbook /repo/firewall/ayar.yml -e @/work/vars-ops.yml "$@"
    else
        in_ns lan env -u HTTPS_PROXY -u HTTP_PROXY -u https_proxy -u http_proxy -u ALL_PROXY -u all_proxy \
            ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
            ansible-playbook "$repo/firewall/ayar.yml" -e "@$work/vars.yml" "$@"
    fi
}
unchanged() { local out; out=$(play "$@") || { echo "$out"; return 1; }; echo "$out" | tail -3
    echo "$out" | grep -qE 'localhost +: ok=[0-9]+ +changed=0 +unreachable=0 +failed=0'; }
check "ayar uygulandı" play
check "ayar ikinci kez uygulanınca değişiklik yok" unchanged
check "--check --diff: firewall git ile aynı" unchanged --check --diff

# --- Erişim ---
check "LAN: internete çıkış" probe lan tcp 198.51.100.10 80
check "LAN: ev ağına (Proxmox API'si)" probe lan tcp 192.168.1.1 8080
check "DMZ: internete çıkış" probe dmz tcp 198.51.100.10 80
check "LAB: internete çıkış" probe lab tcp 198.51.100.10 80
check "DMZ: mail'den dizine LDAPS" probe dmz tcp 10.10.10.10 636
check "DMZ: mail'den dizine Kerberos (TCP)" probe dmz tcp 10.10.10.10 88
check "DMZ: mail'den dizine Kerberos (UDP)" probe dmz udp 10.10.10.10 88
check "DMZ: mail'den dizine parola değişimi" probe dmz udp 10.10.10.10 464
check "DMZ: dizinin diğer portları kapalı (SSH)" fails probe dmz tcp 10.10.10.10 22
check "DMZ: dizinin diğer portları kapalı (SMB)" fails probe dmz tcp 10.10.10.10 445
check "DMZ: LAN'daki diğer makineler kapalı" fails probe dmz tcp 10.10.10.30 636
check "DMZ: ev ağı kapalı" fails probe dmz tcp 192.168.1.1 8080
check "DMZ: firewall arayüzü kapalı" fails probe dmz tcp 10.10.20.1 443
check "LAB: dizin kapalı" fails probe lab tcp 10.10.10.10 636
check "LAB: DMZ kapalı" fails probe lab tcp 10.10.20.10 25
check "LAB: ev ağı kapalı" fails probe lab tcp 192.168.1.1 8080
check "LAB: firewall arayüzü kapalı" fails probe lab tcp 10.10.30.1 443
check "ev ağından firewall arayüzü kapalı" fails probe home tcp 192.168.1.201 443
check "DNS: DMZ'den dizinin adı (firewall → dc)" sh -c "ip netns exec lnfr-dmz getent ahostsv4 dc.test.lan | grep -q '^10\.10\.10\.10 '"
check "DNS: LAB'dan firewall'daki çözümleyici" sh -c "ip netns exec lnfr-lab getent ahostsv4 dc.test.lan | grep -q '^10\.10\.10\.10 '"
check "DHCP: LAB'da adres öneriliyor" retry 120 sh -c "ip netns exec lnfr-lab python3 '$here/net.py' dhcp eth0 | grep -qE '^10\.10\.30\.(1[0-9][0-9])$'"

# --- Sapma: elle eklenen bir kural raporlanır ve bir sonraki uygulamada silinir ---
fwapi() { in_ns lan curl -sS -m 60 --cacert "$work/pki/ca.pem" -u librenfra-test-key:librenfra-test-secret "$@"; }
fwapi -H 'Content-Type: application/json' \
    -d '{"rule":{"sequence":"1","interface":"opt2","action":"pass","source_net":"opt2","destination_net":"10.10.10.10","description":"elle eklendi"}}' \
    https://10.10.10.1/api/firewall/filter/add_rule >/dev/null
fwapi -X POST -d '' https://10.10.10.1/api/firewall/filter/apply >/dev/null
check "sapma: elle eklenen kural LAB'dan dizini açtı" retry 60 probe lab tcp 10.10.10.10 636
check "sapma: elle eklenen kural --check'te görünüyor" fails unchanged --check --diff
check "sapma: uygulama elle eklenen kuralı siliyor" play
check "sapma: LAB'dan dizine yine kapalı" fails probe lab tcp 10.10.10.10 636

echo "toplam: $pass geçti, $fail kaldı"
[ "$fail" -eq 0 ]
