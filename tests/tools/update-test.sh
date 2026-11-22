#!/bin/bash
# tools/update.sh'nin akışını sahte bir makineyle sınar: güncel makineye dokunulmaz, sağlıklı
# açılan güncelleme kalır, sağlık denetimini geçemeyen güncelleme geri alınır.
#   bash tests/tools/update-test.sh
set -uo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
pass=0 fail=0
check() {
    local name=$1; shift
    if out=$("$@" 2>&1); then echo "GEÇTİ  $name"; pass=$((pass+1))
    else echo "KALDI  $name"; echo "$out" | tail -8 | sed 's/^/       /'; fail=$((fail+1)); fi
}

# Sahte ssh: makinenin durumu $work/m dizinindedir (booted, staged, rollback, boot_id, kotu).
mkdir -p "$work/bin" "$work/m"
cat > "$work/bin/ssh" <<'SH'
#!/bin/bash
m=$FAKE_MACHINE
while [ $# -gt 0 ] && [[ $1 != librenfra@* ]]; do shift; done
shift
cmd="$*"
case $cmd in
    "sudo bootc status --format=json")
        printf '{"status":{"booted":{"image":{"image":{"image":"%s"}}}}}\n' "$(cat "$m/booted")" ;;
    "cat /proc/sys/kernel/random/boot_id") cat "$m/boot_id" ;;
    "sudo bootc switch --quiet "*) echo "${cmd##* }" > "$m/staged" ;;
    "sudo bootc rollback") cp "$m/previous" "$m/staged" ;;
    "sudo systemctl reboot")
        if [ -s "$m/staged" ]; then cp "$m/booted" "$m/previous"; mv "$m/staged" "$m/booted"; fi
        echo "boot-$RANDOM" > "$m/boot_id" ;;
    "sudo bash -s")
        cat >/dev/null
        echo "sistem: $([ "$(cat "$m/booted")" = "$(cat "$m/kotu" 2>/dev/null)" ] && echo degraded || echo running)"
        [ "$(cat "$m/booted")" != "$(cat "$m/kotu" 2>/dev/null)" ] ;;
    *) echo "beklenmeyen komut: $cmd" >&2; exit 99 ;;
esac
SH
chmod +x "$work/bin/ssh"
export PATH=$work/bin:$PATH FAKE_MACHINE=$work/m
machine() { rm -f "$work/m"/*; echo "$1" > "$work/m/booted"; echo boot-0 > "$work/m/boot_id"; : > "$work/m/staged"; }
update() { bash "$root/tools/update.sh" 10.0.0.1 "$1"; }

up_to_date() { machine r/dc:1; out=$(update r/dc:1) && [[ $out == *"zaten r/dc:1"* ]] && [ "$(cat "$work/m/boot_id")" = boot-0 ]; }
healthy() { machine r/dc:1; update r/dc:2 && [ "$(cat "$work/m/booted")" = r/dc:2 ]; }
broken() {
    machine r/dc:1; echo r/dc:2 > "$work/m/kotu"
    update r/dc:2; local rc=$?
    [ $rc = 1 ] && [ "$(cat "$work/m/booted")" = r/dc:1 ]
}
check "güncel makine yeniden başlatılmaz" up_to_date
check "sağlıklı açılan güncelleme kalır" healthy
check "sağlık denetimini geçemeyen güncelleme geri alınır" broken

echo "toplam: $pass geçti, $fail kaldı"
[ "$fail" -eq 0 ]
