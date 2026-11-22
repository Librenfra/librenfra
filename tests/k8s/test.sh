#!/bin/bash
# Kontrol düğümünde çalışır: iki düğümlü kümenin kurulduğunu ve çalıştığını sınar.
# Kullanım: ssh librenfra@k8s-cp sudo TEST_PHASE=<aşama> bash -s < tests/k8s/test.sh
set -uo pipefail
. /etc/librenfra/k8s.conf
export KUBECONFIG=/etc/kubernetes/admin.conf
phase=${TEST_PHASE:-ilk}
pass=0 fail=0
check() {
    local name=$1; shift
    if [ -n "${TEST_SKIP:-}" ] && [[ $name =~ $TEST_SKIP ]]; then echo "ATLANDI $name"; return; fi
    if out=$("$@" 2>&1); then echo "GEÇTİ  $name"; pass=$((pass+1))
    else echo "KALDI  $name"; echo "$out" | tail -5 | sed 's/^/       /'; fail=$((fail+1)); fi
}
# Düğüm servisi her açılışta çalışır (kurulum, sürüm geçişi, Calico); bitmesini bekle.
for _ in $(seq 360); do
    [ "$(systemctl show -p SubState --value librenfra-k8s.service)" = exited ] && break
    sleep 10
done
# retry <saniye> <komut...>: komut başarılı olana kadar dener (API sunucusu yük altında
# kısa süre yanıt vermeyebilir).
retry() {
    local t=$1; shift
    local end=$((SECONDS + t))
    until "$@"; do [ $SECONDS -ge $end ] && return 1; sleep 10; done
}
image_version=$(kubeadm version -o short)
server_version() { kubectl version -o json | python3 -c 'import json,sys; print(json.load(sys.stdin)["serverVersion"]["gitVersion"])'; }

check "otomatik güncelleme kapalı (pipeline günceller)" sh -c "[ \"\$(systemctl is-enabled bootc-fetch-apply-updates.timer)\" = masked ]"
check "SELinux zorlayıcı" sh -c "[ \"\$(getenforce)\" = Enforcing ]"
check "takas kapalı" sh -c "[ -z \"\$(swapon --noheadings)\" ]"
check "düğüm servisi tamamlandı" sh -c "[ \"\$(systemctl show -p SubState --value librenfra-k8s.service)\" = exited ]"
check "crio ve kubelet çalışıyor" systemctl is-active crio.service kubelet.service
check "kubeadm ayarı /var'da" sh -c "[ \"\$(readlink -f /etc/kubernetes)\" = /var/lib/kubernetes ] && test -f /var/lib/kubernetes/admin.conf"
check "küme CA'sı cloud-init'ten" cmp /etc/librenfra/k8s-ca.crt /etc/kubernetes/pki/ca.crt
check "iki düğüm Ready" retry 1800 sh -c "[ \"\$(kubectl get nodes --no-headers | awk '\$2==\"Ready\"' | wc -l)\" = 2 ]"
check "düğüm adresleri segmentte" retry 300 sh -c "kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type==\"InternalIP\")].address}{\"\\n\"}{end}' | sort | tr '\n' ' ' | grep -qx '10.99.0.30 10.99.0.31 '"
check "Calico her düğümde hazır" retry 1200 kubectl -n kube-system rollout status daemonset/calico-node --timeout=60s
check "Calico IP havuzu podSubnet ile aynı" retry 300 sh -c "kubectl get ippools.crd.projectcalico.org -o jsonpath='{.items[*].spec.cidr}' | grep -qx 10.244.0.0/16"
check "CoreDNS hazır" retry 900 kubectl -n kube-system rollout status deployment/coredns --timeout=60s
sv=$(retry 300 server_version 2>/dev/null)
if [ "$phase" = rollback ]; then
    # Geri dönülen imajın kubelet'i kümeden eski olabilir; kubeadm buna izin verir.
    check "küme sürümü ($sv) imajdakinden ($image_version) eski değil" \
        sh -c "[ -n '$sv' ] && [ \"\$(printf '%s\n' $sv $image_version | sort -V | head -1)\" = $image_version ]"
else
    check "küme sürümü imajdaki kubeadm ile aynı ($image_version)" test "$sv" = "$image_version"
fi
check "kubelet sürümü imajdaki ile aynı" retry 300 sh -c "kubectl get node \$(hostname) -o jsonpath='{.status.nodeInfo.kubeletVersion}' | grep -qx $image_version"

# Her düğümde bir pod: dizinin adını kümenin DNS'i üzerinden çözer.
# dns_pod <düğüm> <pod>: pod'u çalıştırır, bitmesini bekler, çıktısını yazar.
dns_pod() {
    local node=$1 pod=$2 s=
    kubectl delete pod "$pod" --ignore-not-found --wait >/dev/null 2>&1
    kubectl run "$pod" --image=docker.io/library/busybox:1.37 --restart=Never \
        --overrides="{\"spec\":{\"nodeName\":\"$node\",\"tolerations\":[{\"operator\":\"Exists\"}]}}" \
        --command -- nslookup "$LIBRENFRA_DC" >/dev/null || return 1
    for _ in $(seq 90); do
        s=$(kubectl get pod "$pod" -o jsonpath='{.status.phase}')
        [ "$s" = Succeeded ] || [ "$s" = Failed ] && break
        sleep 5
    done
    kubectl logs "$pod"
    kubectl delete pod "$pod" --wait=false >/dev/null 2>&1
    [ "$s" = Succeeded ]
}
resolves_dc() { dns_pod "$1" "dns-$1-$phase" | grep -A2 '^Name:' | grep -q 'Address: 10.99.0.10'; }
for node in k8s-cp k8s-w1; do
    # Açılıştan sonra Calico ve CoreDNS'in yerleşmesi zaman alabilir.
    check "$node: pod dizinin DNS'ini çözüyor" retry 900 resolves_dc "$node"
done

echo "toplam: $pass geçti, $fail kaldı"
[ "$fail" -eq 0 ]
