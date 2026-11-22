#!/bin/bash
# Ortam testleri: rollerin birlikte çalıştığını, gerçek ortamda sınar. ops'ta runner olarak çalışır
# (tools/deploy.sh güncellemelerden sonra çağırır).
#   run.sh <makineler.json> <ca.pem>
# makineler.json: tofu output -json machines. Makinelere tools/update.sh'deki SSH ayarıyla bağlanır.
#
# Geçici bir kullanıcı açılır (lnfr-ortam-<rastgele>) ve test sonunda silinir:
# - kullanıcı dizinde parolasıyla Kerberos bileti alır,
# - mail'e parolasıyla gönderdiği posta kendi posta kutusuna düşer (posta kutusu ilk postayla açılır),
# - Kubernetes'teki bir pod dizinin adını ve LDAP SRV kaydını firewall/dc üzerinden çözer.
set -uo pipefail
machines=$1 ca=$2
key=${LIBRENFRA_SSH_KEY:-/var/lib/librenfra/ssh/id_ed25519}
known=${LIBRENFRA_KNOWN_HOSTS:-/var/lib/librenfra/ssh/known_hosts}
pass=0 fail=0
check() {
    local name=$1; shift
    if [ -n "${TEST_SKIP:-}" ] && [[ $name =~ $TEST_SKIP ]]; then echo "ATLANDI $name"; return; fi
    if out=$("$@" 2>&1); then echo "GEÇTİ  $name"; pass=$((pass+1))
    else echo "KALDI  $name"; echo "$out" | tail -5 | sed 's/^/       /'; fail=$((fail+1)); fi
}
field() { jq -r --arg n "$1" ".[] | select(.name == \$n) | .$2" "$machines"; }
on() {
    local host; host=$(field "$1" address); shift
    ssh -i "$key" -o UserKnownHostsFile="$known" -o StrictHostKeyChecking=accept-new \
        -o BatchMode=yes -o ConnectTimeout=10 "librenfra@$host" "$@"
}

dc_fqdn=$(field dc fqdn) dc_ip=$(field dc address)
mail_fqdn=$(field mail fqdn) mail_ip=$(field mail address)
domain=${dc_fqdn#*.} realm=${dc_fqdn#*.}; realm=${realm^^}
mail_domain=${mail_fqdn#*.}
user=lnfr-ortam-$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)
password="Ortam-$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 20)-1"
address=$user@$mail_domain
subject="librenfra ortam testi $user"

cleanup() {
    on dc sudo samba-tool user delete "$user" >/dev/null 2>&1
    on mail sudo rm -rf "/var/vmail/$user" >/dev/null 2>&1
    on k8s-cp sudo kubectl --kubeconfig /etc/kubernetes/admin.conf delete pod "$user" --ignore-not-found --wait=false >/dev/null 2>&1
}
trap cleanup EXIT

user_created() {
    on dc sudo samba-tool user create "$user" "$password" --mail-address="$address" >/dev/null
}
kerberos() {
    printf '%s\n' "$password" | on dc "KRB5CCNAME=MEMORY: kinit $user@$realm >/dev/null && echo bilet"
}
# Posta: SMTP gönderimi (587, STARTTLS) ve IMAP (993); mail'in sertifikası ortamın CA'sıyla ve
# adıyla doğrulanır, bağlantı makinenin adresine yapılır.
mail_py() { python3 - "$@" <<'PY'
import imaplib, smtplib, socket, ssl, sys, time
ca, ip, name, user, pw, addr, subject = sys.argv[1:8]
ctx = ssl.create_default_context(cafile=ca)

# Sertifika adı (name) doğrulanır; bağlantı adın değil makinenin adresine (ip) yapılır.
class SMTP(smtplib.SMTP):
    def _get_socket(self, host, port, timeout):
        return socket.create_connection((ip, port), timeout)

class IMAP(imaplib.IMAP4_SSL):
    def _create_socket(self, timeout):
        sock = socket.create_connection((ip, self.port), timeout)
        return self.ssl_context.wrap_socket(sock, server_hostname=name)

with SMTP(name, 587, timeout=120) as s:
    s.starttls(context=ctx)
    s.login(user, pw)
    s.sendmail(addr, [addr], f"From: {addr}\r\nTo: {addr}\r\nSubject: {subject}\r\n\r\ntest\r\n")

deadline = time.time() + 180
while True:
    with IMAP(name, 993, ssl_context=ctx, timeout=60) as m:
        m.login(user, pw)
        m.select("INBOX", readonly=True)
        typ, data = m.search(None, "SUBJECT", f'"{subject}"')
        if data[0].split():
            sys.exit(0)
    if time.time() > deadline:
        sys.exit("posta gelmedi")
    time.sleep(5)
PY
}
mail_roundtrip() { mail_py "$ca" "$mail_ip" "$mail_fqdn" "$user" "$password" "$address" "$subject"; }
mailbox_exists() { on mail sudo test -d "/var/vmail/$user"; }
# Pod'un çıktısı: nslookup <dc> ve _ldap._tcp SRV kaydı, kümenin DNS'i (CoreDNS) üzerinden.
pod_queries_directory() {
    local out
    out=$(on k8s-cp sudo env KUBECONFIG=/etc/kubernetes/admin.conf bash -s "$user" "$dc_fqdn" "$domain" <<'SH'
pod=$1 dc=$2 domain=$3
kubectl run "$pod" --image=docker.io/library/busybox:1.37 --restart=Never --command -- \
    sh -c "nslookup $dc; nslookup -type=SRV _ldap._tcp.$domain" >/dev/null || exit 1
for _ in $(seq 90); do
    s=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}')
    [ "$s" = Succeeded ] || [ "$s" = Failed ] && break
    sleep 5
done
kubectl logs "$pod"
SH
    ) || return 1
    echo "$out"
    grep -A2 '^Name:' <<<"$out" | grep -q "Address: $dc_ip" && grep -qE "service = [0-9]+ [0-9]+ 389 " <<<"$out"
}

check "dizin: kullanıcı açılıyor" user_created
check "dizin: kullanıcı parolasıyla Kerberos bileti alıyor" kerberos
check "posta: gönderilen posta kullanıcının kutusuna düşüyor" mail_roundtrip
check "posta: posta kutusu mail'in veri diskinde" mailbox_exists
check "Kubernetes: pod dizinin adını ve LDAP kaydını çözüyor" pod_queries_directory

echo "toplam: $pass geçti, $fail kaldı"
[ "$fail" -eq 0 ]
