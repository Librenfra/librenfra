#!/bin/bash
# Bir rolün imajını QEMU'da kurup testlerini çalıştırır.
#
#   role-test.sh <rol> <imaj> [<yeni-imaj>]
#
# 1. İmaj(lar) yerel bir registry'ye (localhost:5000) itilir.
# 2. <imaj>'dan disk üretilir, makine tests/<rol>/cloud-init ile açılır, tests/<rol>/test.sh çalışır.
# 3. <yeni-imaj> verilmişse: bootc switch ile ona geçilir, yeniden açılır, test çalışır;
#    sonra bootc rollback ile geri dönülür, yeniden açılır, test yine çalışır.
# 4. Veri diski, aynı imajdan yeni kurulmuş bir makineye takılır ve test yine çalışır.
#
# Test betiği aşamayı TEST_PHASE değişkeninden okur: ilk, switch, rollback, tasima.
# TEST_SKIP verilirse test betiğine geçer.
#
# Gereken: podman (root), qemu, genisoimage. Disk üretimi için DISK_TOOL
# (varsayılan tools/disk.sh) aynı argümanları alan başka bir araçla değiştirilebilir.
set -euo pipefail

role=$1 image=$2 next=${3:-}
root=$(cd "$(dirname "$0")/.." && pwd)
vt() { bash "$root/tools/vm-test.sh" "$@"; }
disk_tool=${DISK_TOOL:-$root/tools/disk.sh}
work=${VMTEST_DIR:-/tmp/vm-test}/role-$role
mkdir -p "$work"

podman container exists vmtest-registry || podman run -d --name vmtest-registry -p 5000:5000 docker.io/library/registry:2 >/dev/null
for _ in $(seq 30); do curl -sf --noproxy '*' http://localhost:5000/v2/ >/dev/null && break; sleep 1; done
push() { podman push -q --tls-verify=false "$1" "localhost:5000/librenfra/$role:$2" >/dev/null; echo "10.0.2.2:5000/librenfra/$role:$2"; }

ref_a=$(push "$image" a)
[ -n "$next" ] && ref_b=$(push "$next" b)

bash "$disk_tool" "$image" "$ref_a" "$work/disk" >/dev/null
rm -f "$work/data.qcow2"
run_tests() {
    echo "== $role: $1"
    vt ssh "$role" 'sudo bootc status --format humanreadable | grep -E "Booted|Version" | head -2'
    vt ssh "$role" "sudo TEST_PHASE=$2 TEST_SKIP='${TEST_SKIP:-}' bash -s" < "$root/tests/$role/test.sh"
}

vt stop "$role"
vt start "$role" "$work/disk" "$root/tests/$role/cloud-init" "$work/data.qcow2"
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
vt stop "$role"
vt start "$role" "$work/disk" "$root/tests/$role/cloud-init" "$work/data.qcow2"
vt wait "$role"
run_tests "veri diski yeni makinede" tasima
vt stop "$role"
