#!/bin/bash
# dc makinesinin içinde çalışır: domain'in kurulduğunu ve temel servislerin yanıt verdiğini sınar.
# Kullanım: ssh librenfra@dc sudo bash -s < tests/dc/test.sh
set -uo pipefail
. /etc/librenfra/dc.conf
realm=$LIBRENFRA_REALM domain_lc=${LIBRENFRA_REALM,,}
export ADMIN_PASSWORD=${ADMIN_PASSWORD:-$(cat /etc/librenfra/secrets/dc-admin-password)}
pass=0 fail=0

# Samba açıldıktan sonra LDAP'ın yanıt vermesi zaman alabilir.
for _ in $(seq 60); do
    ldapsearch -x -H ldap://127.0.0.1 -b '' -s base >/dev/null 2>&1 && break
    sleep 3
done
# TEST_SKIP: atlanacak denetimlerin adlarına uyan bir düzenli ifade (ör. dış DNS'i olmayan
# bir test ortamında "dış ad").
check() {
    local name=$1; shift
    if [ -n "${TEST_SKIP:-}" ] && [[ $name =~ $TEST_SKIP ]]; then echo "ATLANDI $name"; return; fi
    if out=$("$@" 2>&1); then echo "GEÇTİ  $name"; pass=$((pass+1))
    else echo "KALDI  $name"; echo "$out" | tail -5 | sed 's/^/       /'; fail=$((fail+1)); fi
}

check "domain kurulumu hata vermedi" sh -c "! systemctl is-failed -q librenfra-dc-provision.service"
check "samba çalışıyor" systemctl is-active samba.service
check "SPN güncellemesi" systemctl is-active librenfra-dc-spn.service
check "sam.ldb /var altında" test -f /var/lib/samba/private/sam.ldb
check "DNS: _ldap._tcp SRV kaydı" sh -c "dig +short @127.0.0.1 _ldap._tcp.$domain_lc SRV | grep -qE '^[0-9]+ [0-9]+ 389 '"
check "DNS: _kerberos._udp SRV kaydı" sh -c "dig +short @127.0.0.1 _kerberos._udp.$domain_lc SRV | grep -qE '^[0-9]+ [0-9]+ 88 '"
check "DNS: dış ad forwarder üzerinden"  sh -c "dig +short @127.0.0.1 fedoraproject.org A | grep -qE '^[0-9.]+$'"
check "Kerberos: Administrator bileti" sh -c "echo \"\$ADMIN_PASSWORD\" | kinit administrator@$realm >/dev/null && klist | grep -q krbtgt/$realm"
check "LDAP: GSSAPI ile arama" sh -c "ldapsearch -Q -Y GSSAPI -H ldap://$(hostname -f) -b '' -s base defaultNamingContext | grep -q DC="
check "samba-tool: kullanıcı listesi" sh -c "samba-tool user list | grep -qx Administrator"
check "veri diski /var/lib/samba'ya bağlı" sh -c "[ \"\$(findmnt -no SOURCE /var/lib/samba)\" = \"\$(readlink -f /dev/disk/by-id/virtio-lnfr-data)\" ]"
check "kısa ad FQDN değil" sh -c "[ \"\$(hostname -s)\" = \"\$(hostname)\" ] && [ \"\$(hostname -f)\" = \"\$(hostname).$domain_lc\" ]"
check "ad gerçek adrese çözülüyor" sh -c "getent hosts $(hostname -f) | grep -qv '^127\.'"
check "zaman: chronyd çalışıyor" systemctl is-active chronyd.service
check "zaman: Samba imza soketi" test -S /var/lib/samba/ntp_signd/socket
check "zaman: chrony imza soketini kullanıyor" grep -q '^ntpsigndsocket /var/lib/samba/ntp_signd' /etc/chrony.conf
check "servis hesapları açıldı" systemctl is-active librenfra-dc-accounts.service
if [ -f /etc/librenfra/dc-accounts ]; then
    while read -r kind name groups; do
        case $kind in
        group) check "grup: $name" samba-tool group show "$name" ;;
        user)
            check "hesap: $name parolasıyla bilet alır" sh -c "kinit $name@$realm < /etc/librenfra/secrets/$name >/dev/null"
            for g in ${groups//,/ }; do
                check "hesap: $name, $g üyesi" sh -c "samba-tool group listmembers $g | grep -qx $name"
            done ;;
        esac
    done < /etc/librenfra/dc-accounts
fi
if [ "${TEST_PHASE:-}" = tasima ]; then
    check "taşınan diskte domain yeniden kurulmadı" sh -c "[ \"\$(systemctl show -p ConditionResult --value librenfra-dc-provision.service)\" = no ]"
fi

echo "toplam: $pass geçti, $fail kaldı"
[ "$fail" -eq 0 ]
