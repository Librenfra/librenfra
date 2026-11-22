#!/bin/bash
# Testler için bir CA ve verilen adlara sunucu sertifikaları üretir. Dosyalar varsa dokunmaz.
#   test-pki.sh <dizin> <fqdn>[,<ip>]...
# Çıktı: <dizin>/ca.pem, <dizin>/<fqdn>-cert.pem, <dizin>/<fqdn>-key.pem,
#        <dizin>/k8s-ca.pem ve k8s-ca-key.pem (Kubernetes kümesinin ayrı CA'sı),
#        <dizin>/dkim-key.pem (posta imzası için RSA anahtarı),
#        <dizin>/ops-ssh-key (ops'un makinelere bağlandığı SSH anahtarı)
set -euo pipefail
dir=$1; shift
mkdir -p "$dir"; cd "$dir"
if [ ! -f ca.pem ]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 \
        -subj "/CN=Librenfra test CA" -addext "basicConstraints=critical,CA:TRUE" \
        -addext "keyUsage=critical,keyCertSign,cRLSign" -keyout ca-key.pem -out ca.pem 2>/dev/null
fi
if [ ! -f k8s-ca.pem ]; then
    openssl req -x509 -newkey rsa:2048 -nodes -days 30 -subj "/CN=kubernetes" \
        -addext "keyUsage=critical,keyCertSign,cRLSign,digitalSignature,keyEncipherment" \
        -keyout k8s-ca-key.pem -out k8s-ca.pem 2>/dev/null
fi
[ -f dkim-key.pem ] || openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out dkim-key.pem 2>/dev/null
[ -f ops-ssh-key ] || ssh-keygen -q -t ed25519 -N '' -C librenfra-ops -f ops-ssh-key
for arg in "$@"; do
    name=${arg%%,*} san="DNS:$name"
    [ "$arg" != "$name" ] && san="$san,IP:${arg#*,}"
    [ -f "$name-cert.pem" ] && continue
    openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -subj "/CN=$name" \
        -keyout "$name-key.pem" -out "$name.csr" 2>/dev/null
    openssl x509 -req -in "$name.csr" -CA ca.pem -CAkey ca-key.pem -CAcreateserial -days 30 \
        -extfile <(printf 'subjectAltName=%s\nextendedKeyUsage=serverAuth\n' "$san") \
        -out "$name-cert.pem" 2>/dev/null
    rm -f "$name.csr"
done
