#!/bin/bash
# Bir makineyi yeni imaja geçirir; açılıştan sonra sağlık denetimi geçmezse önceki imaja döner.
#   update.sh <adres> <imaj>      ör. update.sh 10.10.10.10 ghcr.io/librenfra/dc:0.2.0
# ops'ta runner olarak çalışır; makinelere librenfra kullanıcısıyla SSH ile bağlanır
# (LIBRENFRA_SSH_KEY, LIBRENFRA_KNOWN_HOSTS).
# Çıkış: 0 güncel ya da güncellendi, 1 güncelleme geri alındı, 2 makineye ulaşılamadı.
set -uo pipefail
host=$1 image=$2
root=$(cd "$(dirname "$0")/.." && pwd)
key=${LIBRENFRA_SSH_KEY:-/var/lib/librenfra/ssh/id_ed25519}
known=${LIBRENFRA_KNOWN_HOSTS:-/var/lib/librenfra/ssh/known_hosts}
on() {
    ssh -i "$key" -o UserKnownHostsFile="$known" -o StrictHostKeyChecking=accept-new \
        -o BatchMode=yes -o ConnectTimeout=10 "librenfra@$host" "$@"
}
booted() { on sudo bootc status --format=json | jq -r '.status.booted.image.image.image // empty'; }
boot_id() { on cat /proc/sys/kernel/random/boot_id 2>/dev/null; }
reboot_and_wait() {
    local before; before=$(boot_id)
    on sudo systemctl reboot >/dev/null 2>&1
    for _ in $(seq 180); do
        sleep 5
        local now; now=$(boot_id) || continue
        [ -n "$now" ] && [ "$now" != "$before" ] && return 0
    done
    echo "$host: yeniden açılmadı" >&2
    return 1
}
health() { on sudo bash -s < "$root/tools/health.sh" | sed "s/^/$host: /"; return "${PIPESTATUS[0]}"; }

current=$(booted) || { echo "$host: ulaşılamadı" >&2; exit 2; }
if [ "$current" = "$image" ]; then
    echo "$host: zaten $image"
    exit 0
fi
echo "$host: $current -> $image"
if ! on sudo bootc switch --quiet "$image"; then
    echo "$host: bootc switch başarısız" >&2
    exit 1
fi
if reboot_and_wait && [ "$(booted)" = "$image" ] && health; then
    echo "$host: $image ile açıldı"
    exit 0
fi

echo "$host: güncelleme geri alınıyor" >&2
on sudo bootc rollback >/dev/null
if reboot_and_wait && [ "$(booted)" = "$current" ]; then
    health || true
    echo "$host: önceki imaja ($current) dönüldü" >&2
else
    echo "$host: önceki imaja dönülemedi; makineye elle bakılmalı" >&2
fi
exit 1
