#!/bin/bash
# Bir makinenin içinde çalışır: açılışın bitmesini bekler ve hata veren birim olmadığını sınar.
# Pipeline bir güncellemeden sonra buna bakar; geçmezse makine önceki imaja döner.
#   ssh librenfra@<makine> sudo bash -s < tools/health.sh
set -uo pipefail
state=$(timeout 900 systemctl is-system-running --wait 2>/dev/null)
echo "sistem: ${state:-yanıt yok}"
echo "imaj: $(bootc status --format=json | jq -r '.status.booted.image.image.image // "?"')"
if [ "$state" != running ]; then
    systemctl --failed --no-legend --plain | sed 's/^/  hata veren birim: /'
    exit 1
fi
