#!/bin/bash
# Ortamı bir sürüme getirir. ops'taki runner'da çalışır (.github/workflows/deploy.yml).
#   deploy.sh <sürüm>      ör. deploy.sh 0.2.0
#
# 1. tofu apply: eksik makineler sürümün disklerinden oluşturulur; var olanlara dokunulmaz.
# 2. Firewall ayarı (firewall/ayar.yml) API ile uygulanır.
# 3. bootc makineleri sırayla (dc, mail, k8s, ...) sürümün imajına geçirilir (tools/update.sh).
#    Bir makine sağlık denetimini geçemezse önceki imaja döner ve kurulum orada durur.
# 4. Ortam testleri (tests/ortam) çalışır.
# 5. ops kendi güncellemesini ister; iş bitince yeni imajla yeniden başlar.
#
# Ortam: PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN, PROXMOX_VE_SSH_USERNAME ve secret değişkenler
# (TF_VAR_dc_admin_password, TF_VAR_cloudflared_token, TF_VAR_mail_inbound_token,
# TF_VAR_mail_dkim_key). Secret olmayan değişkenler ops'un veri diskindeki home.tfvars'tadır.
set -euo pipefail
version=${1:?sürüm gerekli}
# GitHub boş secret'ı boş metin olarak verir; OpenTofu'da değer verilmemiş (null) sayılsın.
for v in TF_VAR_cloudflared_token TF_VAR_mail_inbound_token TF_VAR_mail_dkim_key; do
    [ -n "${!v:-}" ] || unset "$v"
done
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "geçersiz sürüm: $version" >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
data=${LIBRENFRA_DATA:-/var/lib/librenfra}
registry=${LIBRENFRA_REGISTRY:-ghcr.io/librenfra}
export LIBRENFRA_SSH_KEY=$data/ssh/id_ed25519 LIBRENFRA_KNOWN_HOSTS=$data/ssh/known_hosts
work=$(mktemp -d)
trap 'rm -rf "$work"; [ -n "${SSH_AGENT_PID:-}" ] && ssh-agent -k >/dev/null' EXIT
chmod 700 "$work"

# Provider snippet yüklemek, firewall'un ilk ayarı Proxmox'ta konsolu yürütmek için SSH kullanır.
eval "$(ssh-agent -s)" >/dev/null
ssh-add -q "$LIBRENFRA_SSH_KEY"

echo "== tofu apply ($version)"
# Proxmox API'sinin sertifikası Proxmox'un kendi CA'sıyla imzalıdır (bootstrap.sh veri diskine koyar);
# tofu sistemin CA'larına ek olarak ona güvenir.
cat /etc/pki/tls/certs/ca-bundle.crt "$data/tofu/pve-root-ca.pem" > "$work/ca-bundle.pem"
cd "$root/infra/envs/home"
SSL_CERT_FILE=$work/ca-bundle.pem tofu init -input=false -backend-config="path=$data/tofu/home.tfstate" >/dev/null
SSL_CERT_FILE=$work/ca-bundle.pem tofu apply -input=false -auto-approve -var-file="$data/tofu/home.tfvars" -var "release=$version"
tofu output -raw fw_api_credentials > "$work/fw-api.txt"
tofu output -raw ca_cert > "$work/ca.pem"
tofu output -json machines > "$work/machines.json"

echo "== firewall ayarı"
cat > "$work/fw.yml" <<EOF
fw_host: 10.10.10.1
fw_credentials: $work/fw-api.txt
fw_ca: $work/ca.pem
domain: $(tofu output -raw domain)
dc_address: $(jq -r '.[] | select(.name == "dc") | .address' "$work/machines.json")
EOF
ANSIBLE_LOCALHOST_WARNING=False ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ansible-playbook "$root/firewall/ayar.yml" -e "@$work/fw.yml"

echo "== bootc makineleri"
while read -r name role address; do
    [ "$role" = ops ] && continue
    bash "$root/tools/update.sh" "$address" "$registry/$role:$version" || {
        echo "$name güncellenemedi; kurulum durdu" >&2
        exit 1
    }
done < <(jq -r '.[] | "\(.name) \(.role) \(.address)"' "$work/machines.json")

if [ -f "$root/tests/ortam/run.sh" ]; then
    echo "== ortam testleri"
    bash "$root/tests/ortam/run.sh" "$work/machines.json" "$work/ca.pem"
fi

echo "== ops"
printf '%s\n' "$registry/ops:$version" > "$data/self-update/image"
echo "ops $registry/ops:$version imajını istedi; iş bitince yeniden başlayacak"
