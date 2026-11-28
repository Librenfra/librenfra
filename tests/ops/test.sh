#!/bin/bash
# ops makinesinin içinde çalışır: araçları, runner'ın hazırlanışını ve veri diskindeki
# OpenTofu state'ini sınar.
# Kullanım: ssh librenfra@ops sudo TEST_PHASE=<aşama> bash -s < tests/ops/test.sh
set -uo pipefail
phase=${TEST_PHASE:-ilk}
pass=0 fail=0
check() {
    local name=$1; shift
    if [ -n "${TEST_SKIP:-}" ] && [[ $name =~ $TEST_SKIP ]]; then echo "ATLANDI $name"; return; fi
    if out=$("$@" 2>&1); then echo "GEÇTİ  $name"; pass=$((pass+1))
    else echo "KALDI  $name"; echo "$out" | tail -5 | sed 's/^/       /'; fail=$((fail+1)); fi
}
as_runner() { runuser -u runner -- "$@"; }
runner=/var/lib/librenfra/runner
state=/var/lib/librenfra/tofu/test

check "otomatik güncelleme kapalı (pipeline günceller)" sh -c "[ \"\$(systemctl is-enabled bootc-fetch-apply-updates.timer)\" = masked ]"
check "veri diski /var/lib/librenfra'ya bağlı" sh -c "[ \"\$(findmnt -no SOURCE /var/lib/librenfra)\" = \"\$(readlink -f /dev/disk/by-id/virtio-lnfr-data)\" ]"
check "OpenTofu" sh -c "tofu version | head -1 | grep -q '^OpenTofu v'"
check "Ansible" sh -c "ansible --version | head -1 | grep -q '^ansible \[core'"
check "Ansible: OPNsense koleksiyonu ve httpx" sh -c "ansible-galaxy collection list ansibleguy.opnsense 2>/dev/null | grep -qE '^ansibleguy\.opnsense +[0-9]' && python3 -c 'import httpx'"
check "runner hazırlığı hata vermedi" systemctl is-active librenfra-runner-setup.service
check "runner imajdaki sürümle veri diskinde" cmp /usr/lib/actions-runner/librenfra-version $runner/librenfra-version
check "runner çalışabiliyor" sh -c "[ \"\$(runuser -u runner -- env -i $runner/bin/Runner.Listener --version)\" = \"\$(cat /usr/lib/actions-runner/librenfra-version)\" ]"
check "runner dizini runner kullanıcısının" sh -c "[ \"\$(stat -c %U $runner $runner/bin/Runner.Listener | sort -u)\" = runner ]"
check "systemd runner'ı çalıştırabilir (SELinux: bin_t)" sh -c "[ \"\$(stat -c %C $runner/run.sh | cut -d: -f3)\" = bin_t ]"
check "kayıt token'ı yokken runner başlamaz" sh -c "! test -f $runner/.runner && ! systemctl is-active -q librenfra-runner.service"
check "ortamın SSH anahtarı runner kullanıcısında" sh -c "[ \"\$(stat -c '%U %a' /var/lib/librenfra/ssh/id_ed25519)\" = 'runner 600' ] && runuser -u runner -- ssh-keygen -y -f /var/lib/librenfra/ssh/id_ed25519 >/dev/null"
check "runner root değil" sh -c "! id -nG runner | grep -qw wheel"

# OpenTofu state'i veri diskindedir: ilk kurulumda yazılır, sonraki aşamalarda okunur.
if [ "$phase" = ilk ]; then
    as_runner mkdir -p "$state"
    as_runner tee "$state/main.tf" >/dev/null <<'TF'
resource "terraform_data" "test" {
  input = "librenfra"
}
TF
    check "tofu apply: state veri diskine yazıldı" sh -c "cd $state && runuser -u runner -- tofu init -input=false >/dev/null && runuser -u runner -- tofu apply -auto-approve -input=false >/dev/null && test -s terraform.tfstate"
fi
check "tofu plan: state okunuyor, değişiklik yok" sh -c "cd $state && runuser -u runner -- tofu plan -input=false -detailed-exitcode >/dev/null"
# Kendi güncellemesi: runner yalnızca imaj adresini bırakır, root'taki birim denetleyip uygular.
self_update() { # <istek>: isteği runner olarak yazar, birimin bu istekle bitmesini bekler
    local before; before=$(systemctl show -p InvocationID --value librenfra-self-update.service)
    runuser -u runner -- sh -c "printf '%s\n' '$1' > /var/lib/librenfra/self-update/image"
    for _ in $(seq 60); do
        local now state
        now=$(systemctl show -p InvocationID --value librenfra-self-update.service)
        state=$(systemctl show -p ActiveState --value librenfra-self-update.service)
        [ -n "$now" ] && [ "$now" != "$before" ] && [ "$state" != activating ] && break
        sleep 2
    done
    systemctl show -p Result --value librenfra-self-update.service
}
booted_image() { bootc status --format=json | jq -r '.status.booted.image.image.image'; }
staged_none() { [ "$(bootc status --format=json | jq -r '.status.staged')" = null ]; }
check "kendi güncellemesi: istek bekleniyor" systemctl is-active librenfra-self-update.path
rejects_other() { [ "$(self_update quay.io/baska/ops:1.0.0)" = exit-code ] && staged_none; }
same_is_noop() {
    local img; img=$(booted_image)
    [ -n "$img" ] && [ "$(self_update "$img")" = success ] && staged_none &&
        journalctl -u librenfra-self-update.service -n 20 | grep -qF "ops zaten $img"
}
check "kendi güncellemesi: başka depodan imaj reddediliyor" rejects_other
check "kendi güncellemesi: aynı imaj için bir şey yapılmıyor" same_is_noop
if [ "$phase" = tasima ]; then
    check "taşınan diskte runner yeniden kopyalanmadı" sh -c "journalctl -b -u librenfra-runner-setup --no-pager | grep -q 'kayıt token' && ! journalctl -b -u librenfra-runner-setup --no-pager | grep -q kopyalanıyor"
fi

echo "toplam: $pass geçti, $fail kaldı"
[ "$fail" -eq 0 ]
