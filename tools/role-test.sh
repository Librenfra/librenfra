#!/bin/bash
# Bir rolün imajını QEMU'da kurup testlerini çalıştırır.
#
#   role-test.sh <rol> <imaj> [<yeni-imaj>]
#
# 1. İmaj(lar) yerel bir registry'ye (localhost:5000) itilir.
# 2. Rolün bağlı olduğu makineler açılır (aşağıda).
# 3. <imaj>'dan disk üretilir, makine tests/<rol>/cloud-init ile açılır, tests/<rol>/test.sh çalışır.
# 4. <yeni-imaj> verilmişse: bootc switch ile ona geçilir, yeniden açılır, test çalışır;
#    sonra bootc rollback ile geri dönülür, yeniden açılır, test yine çalışır.
# 5. Veri diski, aynı imajdan yeni kurulmuş bir makineye takılır ve test yine çalışır.
#    Rolün veri diski yoksa (tests/<rol>/no-data-disk dosyası) bu aşama atlanır.
#
# Bağımlılıklar: tests/<rol>/requires dosyasında satır başına bir makine adı. Her biri
# DEP_IMAGE_<ad> ortam değişkenindeki yerel imajdan (adda harf, rakam ve _ dışındaki
# karakterler _ olur), kendi veri diskiyle ve tests/<rol>/deps/<ad>/cloud-init (yoksa
# tests/<ad>/cloud-init) ile açılır; varsa tests/<rol>/setup-<ad>.sh o makinede çalışır.
#
# Test sertifikaları (tools/test-pki.sh) her çalıştırmada VMTEST_FILES'a üretilir ve
# cloud-init'te @B64:<dosya>@ ile kullanılır.
#
# Test betiği aşamayı TEST_PHASE değişkeninden okur: ilk, switch, rollback, tasima.
# TEST_SKIP verilirse test betiğine geçer.
#
# Gereken: podman (root), qemu, genisoimage, openssl. Disk üretimi için DISK_TOOL
# (varsayılan tools/disk.sh) aynı argümanları alan başka bir araçla değiştirilebilir.
set -euo pipefail

role=$1 image=$2 next=${3:-}
root=$(cd "$(dirname "$0")/.." && pwd)
vt() { bash "$root/tools/vm-test.sh" "$@"; }
disk_tool=${DISK_TOOL:-$root/tools/disk.sh}
work=${VMTEST_DIR:-/tmp/vm-test}/role-$role
mkdir -p "$work"
export VMTEST_FILES=$work/files
rm -rf "$VMTEST_FILES"
bash "$root/tools/test-pki.sh" "$VMTEST_FILES" dc.test.lan mail.test.lan

registry_up() {
    for _ in $(seq ${1:-30}); do curl -sf --noproxy '*' http://localhost:5000/v2/ >/dev/null && return 0; sleep 1; done
    return 1
}
# Registry host ağında çalışır; port yönlendirmesine bağlı değildir.
if ! registry_up 2; then
    podman rm -f vmtest-registry >/dev/null 2>&1 || true
    podman run -d --name vmtest-registry --network host -e REGISTRY_HTTP_ADDR=127.0.0.1:5000 \
        docker.io/library/registry:2 >/dev/null
    registry_up
fi
# push <rol> <yerel-imaj> <etiket>: makinenin göreceği imgref'i yazar
push() { podman push -q --tls-verify=false "$2" "localhost:5000/librenfra/$1:$3" >/dev/null; echo "10.0.2.2:5000/librenfra/$1:$3"; }

deps=()
[ -f "$root/tests/$role/requires" ] && mapfile -t deps < <(grep -v '^#' "$root/tests/$role/requires" | grep .)
for dep in "${deps[@]}"; do
    var=DEP_IMAGE_${dep//[^A-Za-z0-9_]/_}
    dep_image=${!var:?$var verilmeli}
    vt stop "$dep"
    dep_ref=$(push "$dep" "$dep_image" dep)
    bash "$disk_tool" "$dep_image" "$dep_ref" "$work/$dep-disk" >/dev/null
    rm -f "$work/$dep-data.qcow2"
    ci=$root/tests/$role/deps/$dep/cloud-init
    [ -d "$ci" ] || ci=$root/tests/$dep/cloud-init
    vt start "$dep" "$work/$dep-disk" "$ci" "$work/$dep-data.qcow2"
done
for dep in "${deps[@]}"; do
    vt wait "$dep"
    setup=$root/tests/$role/setup-$dep.sh
    if [ -f "$setup" ]; then echo "== $dep: hazırlık"; vt ssh "$dep" 'sudo bash -s' < "$setup"; fi
done

ref_a=$(push "$role" "$image" a)
[ -n "$next" ] && ref_b=$(push "$role" "$next" b)

bash "$disk_tool" "$image" "$ref_a" "$work/disk" >/dev/null
rm -f "$work/data.qcow2"
data=$work/data.qcow2
[ -f "$root/tests/$role/no-data-disk" ] && data=
run_tests() {
    echo "== $role: $1"
    vt ssh "$role" 'sudo bootc status --format humanreadable | grep -E "Booted|Version" | head -2'
    vt ssh "$role" "sudo TEST_PHASE=$2 TEST_SKIP='${TEST_SKIP:-}' bash -s" < "$root/tests/$role/test.sh"
}

vt stop "$role"
vt start "$role" "$work/disk" "$root/tests/$role/cloud-init" $data
vt wait "$role"
run_tests "ilk kurulum" ilk

if [ -n "$next" ]; then
    vt ssh "$role" "sudo bootc switch $ref_b" >/dev/null
    vt reboot "$role"; vt wait "$role"
    run_tests "bootc switch sonrası" switch
    vt ssh "$role" 'sudo bootc rollback' >/dev/null
    vt reboot "$role"; vt wait "$role"
    run_tests "bootc rollback sonrası" rollback
fi

# Veri diski, yeni kurulmuş bir makineye takıldığında veri korunur ve yeniden kurulmaz.
if [ -n "$data" ]; then
    vt stop "$role"
    vt start "$role" "$work/disk" "$root/tests/$role/cloud-init" "$data"
    vt wait "$role"
    run_tests "veri diski yeni makinede" tasima
fi
vt stop "$role"
for dep in "${deps[@]}"; do vt stop "$dep"; done
