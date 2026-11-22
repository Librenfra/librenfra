#!/bin/bash
# İlk kurulum: boş bir Proxmox'ta ortamı bir kez kurar, sonrasını pipeline'a bırakır.
# Ev ağındaki, Proxmox API'sine ve SSH'ına erişen bir makineden çalıştırılır.
#   bootstrap.sh <sürüm> <home.tfvars>      ör. bootstrap.sh 0.2.0 ~/librenfra/home.tfvars
#
# 1. GitHub'da "home" ortamının secret'larını ve değişkenlerini yazar (deploy.yml bunları kullanır).
# 2. İlk tofu apply'ı çalıştırır: köprüler, firewall ve bootc makineleri sürümün disklerinden kurulur.
# 3. ops'un anahtarını Proxmox'ta yetkilendirir (provider snippet yüklemek için SSH kullanır).
# 4. state'i ve home.tfvars'ı ops'un veri diskine taşır; buradaki state silinir.
# 5. ops'taki runner'ı yeni bir kayıt token'ıyla GitHub'a kaydeder ve ilk pipeline'ı (deploy.yml) başlatır.
#
# ops LAN'dadır ve ev ağından ulaşılamaz. Betik, ops'a Proxmox üzerinden atlar: işi sürerken
# Proxmox'un LAN köprüsüne geçici bir adres (LIBRENFRA_JUMP_ADDRESS, 10.10.10.254/24) verir ve
# çıkarken kaldırır.
#
# Gerekenler: tofu, gh (depoda yönetici yetkisiyle giriş yapılmış), jq, ssh ve ssh-agent'ta
# Proxmox'un root'una ve makinelere (ssh_authorized_keys) giren anahtar.
# Ortam değişkenleri:
#   PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN
#   TF_VAR_dc_admin_password, TF_VAR_cloudflared_token, TF_VAR_mail_inbound_token, TF_VAR_mail_dkim_key
#   LIBRENFRA_REPO         GitHub deposu (varsayılan Librenfra/librenfra)
#   LIBRENFRA_STATE_DIR    taşınana kadar state'in durduğu yer (varsayılan ~/.local/state/librenfra)
# TF_VAR_... değişkenleri aşağıda, kullanılmadan önce denetlenir.
# shellcheck disable=SC2154
set -euo pipefail
version=${1:?sürüm gerekli} tfvars=${2:?home.tfvars gerekli}
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "geçersiz sürüm: $version" >&2; exit 1; }
tfvars=$(realpath "$tfvars")
root=$(cd "$(dirname "$0")/.." && pwd)
repo=${LIBRENFRA_REPO:-Librenfra/librenfra}
state_dir=${LIBRENFRA_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/librenfra}
jump=${LIBRENFRA_JUMP_ADDRESS:-10.10.10.254/24}
ops_data=/var/lib/librenfra

say() { echo "== $*"; }
die() { echo "bootstrap: $*" >&2; exit 1; }

for c in tofu gh jq ssh ssh-add python3; do command -v "$c" >/dev/null || die "$c bulunamadı"; done
for v in PROXMOX_VE_ENDPOINT PROXMOX_VE_API_TOKEN TF_VAR_dc_admin_password TF_VAR_cloudflared_token \
         TF_VAR_mail_inbound_token TF_VAR_mail_dkim_key; do
    [ -n "${!v:-}" ] || die "$v verilmeli"
done
[ -f "$tfvars" ] || die "$tfvars yok"
ssh-add -l >/dev/null 2>&1 || die "ssh-agent'ta anahtar yok"
gh auth status >/dev/null 2>&1 || die "gh ile giriş yapılmamış (gh auth login)"
gh release view "v$version" -R "$repo" >/dev/null || die "v$version sürümü GitHub'da yok"

work=$(mktemp -d)
chmod 700 "$work"
px='' jump_added=''
cleanup() {
    if [ -n "$jump_added" ]; then
        ssh -o BatchMode=yes "$px" ip addr del "$jump" dev "$lan_bridge" || \
            echo "bootstrap: Proxmox'taki geçici adres ($jump, $lan_bridge) elle kaldırılmalı" >&2
    fi
    rm -rf "$work"
}
trap cleanup EXIT

mkdir -p "$state_dir"
chmod 700 "$state_dir"
state=$state_dir/home.tfstate
cd "$root/infra/envs/home"
tofu init -input=false -backend-config="path=$state" >/dev/null
tf() { tofu "$@" -input=false -var-file="$tfvars" -var "release=$version"; }

px=$(tf console <<<'var.proxmox_ssh' | jq -r .)
ssh -o BatchMode=yes "$px" true || die "Proxmox'a SSH ile bağlanılamadı ($px)"
export PROXMOX_VE_SSH_USERNAME=${px%@*}

say "GitHub: home ortamı ($repo)"
gh api -X PUT "repos/$repo/environments/home" >/dev/null
secret() { printf '%s' "$2" | gh secret set "$1" --env home -R "$repo"; }
secret PROXMOX_VE_API_TOKEN "$PROXMOX_VE_API_TOKEN"
secret DC_ADMIN_PASSWORD "$TF_VAR_dc_admin_password"
secret CLOUDFLARED_TOKEN "$TF_VAR_cloudflared_token"
secret MAIL_INBOUND_TOKEN "$TF_VAR_mail_inbound_token"
secret MAIL_DKIM_KEY "$TF_VAR_mail_dkim_key"
gh variable set PROXMOX_VE_ENDPOINT --env home -R "$repo" --body "$PROXMOX_VE_ENDPOINT"
gh variable set PROXMOX_VE_SSH_USERNAME --env home -R "$repo" --body "$PROXMOX_VE_SSH_USERNAME"

say "tofu apply ($version)"
tf apply -auto-approve
ops_ip=$(tofu output -json machines | jq -r '.[] | select(.name == "ops") | .address')
lan_bridge=$(tofu output -raw lan_bridge)

say "Proxmox: ops'un anahtarı yetkilendiriliyor"
tofu output -raw ops_ssh_public_key | ssh -o BatchMode=yes "$px" \
    'k=$(cat); f=~/.ssh/authorized_keys; grep -qxF "$k" "$f" 2>/dev/null || printf "%s\n" "$k" >> "$f"'

say "ops'a Proxmox üzerinden bağlanılıyor ($ops_ip)"
if ! ssh -o BatchMode=yes "$px" ip -o addr show dev "$lan_bridge" | grep -qw "${jump%/*}"; then
    ssh -o BatchMode=yes "$px" ip addr add "$jump" dev "$lan_bridge"
    jump_added=1
fi
ops() {
    ssh -o BatchMode=yes -o ConnectTimeout=10 -o UserKnownHostsFile="$work/known_hosts" \
        -o StrictHostKeyChecking=accept-new -J "$px" "librenfra@$ops_ip" "$@"
}
for i in $(seq 120); do
    ops mountpoint -q "$ops_data" 2>/dev/null && break
    [ "$i" = 120 ] && die "ops 20 dakikada açılmadı ya da veri diski bağlanmadı"
    sleep 10
done

say "state ve home.tfvars ops'un veri diskine taşınıyor"
ops "sudo test ! -s $ops_data/tofu/home.tfstate" || die "ops'ta zaten bir state var; ilk kurulum yapılmış"
put() { ops sudo -u runner sh -c "'umask 027; cat > $1'" < "$2"; }
put "$ops_data/tofu/home.tfvars" "$tfvars"
put "$ops_data/tofu/home.tfstate" "$state"
[ "$(ops sudo sha256sum "$ops_data/tofu/home.tfstate" | cut -d' ' -f1)" = "$(sha256sum "$state" | cut -d' ' -f1)" ] \
    || die "ops'taki state buradakiyle aynı değil; buradaki state silinmedi: $state"
# Proxmox'un anahtarı: ops'taki ssh (firewall/import-config) LIBRENFRA_KNOWN_HOSTS'a bakar.
ssh -o BatchMode=yes "$px" cat /etc/ssh/ssh_host_ed25519_key.pub | awk -v h="${px#*@}" '{print h, $1, $2}' \
    | ops sudo -u runner sh -c "'cat >> $ops_data/ssh/known_hosts'"
rm -f "$state" "$state.backup"
echo "state ops'ta: $ops_data/tofu/home.tfstate"

say "runner GitHub'a kaydediliyor"
if ! ops sudo test -f "$ops_data/runner/.runner"; then
    gh api -X POST "repos/$repo/actions/runners/registration-token" --jq .token \
        | ops "sudo sh -c 'umask 077; cat > /etc/librenfra/secrets/runner-token'"
    ops sudo systemctl restart librenfra-runner-setup.service
    ops sudo systemctl start librenfra-runner.service
    ops sudo rm -f /etc/librenfra/secrets/runner-token
fi
for i in $(seq 60); do
    status=$(gh api "repos/$repo/actions/runners" --jq '.runners[] | select(.name == "ops") | .status') || status=
    [ "$status" = online ] && break
    [ "$i" = 60 ] && die "runner GitHub'da çevrimiçi görünmüyor"
    sleep 10
done

say "ilk pipeline başlatılıyor"
gh workflow run deploy.yml -R "$repo" --ref "v$version" -f version="$version"
echo "kurulum pipeline'da sürüyor: gh run list -R $repo --workflow deploy.yml"
