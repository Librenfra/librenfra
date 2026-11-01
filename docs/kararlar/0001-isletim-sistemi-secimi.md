# 0001. Server'ların işletim sistemi NixOS'tur

- **Durum:** Kabul edildi
- **Tarih:** 2026-11-01

## Bağlam

Projenin temel isteği makinelerdeki her şeyin bir state'te olmasıdır: bir makinenin içi (işletim sistemi, paketler, konfigürasyon, servisler) git'teki bir tanımdan üretilmeli, bu tanım versiyonlanmalı ve makine tanımdan sapmamalıdır.

Adımları sırayla çalıştıran araçların (Ansible gibi) kendi state'i yoktur: makineye ne yaptıklarını hatırlamazlar, tanımdan silinen bir görev makinede iz bırakmaya devam eder. Kurulum anını imajlayan araçlar (Packer gibi) ise yalnız ilk kurulumu versiyonlar; sonraki değişiklikler yine başka bir araca kalır. Bu yüzden makinenin içini baştan sona tek bir versiyonlu tanımla yöneten iki yaklaşım değerlendirildi: CentOS Stream 10 bootc ve NixOS.

## Karar

Firewall dışındaki tüm server'lar NixOS ile kurulur. Her server'ın içi kendi reposundaki bir flake ile tanımlanır; ortak taban `librenfra-terraform`'un flake'inden bir NixOS modülü olarak gelir. Server yeni tanıma `nixos-rebuild switch` ile geçer.

## Gerekçe

- **En kapsamlı tanım:** İşletim sistemi, paketler, konfigürasyon, güncelleme ve geri dönüş tek tanımdadır. Tanımdan çıkarılan bir paket veya ayar makineden de gider.
- **Sürüm kilidi:** `flake.lock` tüm girdileri commit hash'iyle kilitler; aynı commit her zaman aynı sistemi üretir.
- **Çoğu değişiklik yeniden başlatma istemez:** `nixos-rebuild switch` yalnız etkilenen servisleri yeniden başlatır; çekirdek değişikliği gibi durumlar dışında kesinti küçüktür.
- **Uygulamadan önce fark:** `nix store diff-closures` yeni sistemin paket farkını PR'da gösterir.
- **Ek altyapı az:** Container registry gerekmez. Terraform, nixos-anywhere modülleriyle sistemi build edip SSH üzerinden server'a kurar ve günceller.
- **RHEL uyumu tek başına yetmiyor:** CentOS Stream 10 bootc'u öne çıkaran asıl hedef RHEL ekosistemini takip etmekti. Bu hedef işletim sistemi seçimini tek başına belirlemeye yetecek kadar güçlü bulunmadı.

## Sonuçlar

- **Nix öğrenme eğrisi:** Nix dili yenidir ve hata ayıklamak zordur. Modüller küçük tutulur, ortak kalıplar `librenfra-terraform`'daki taban modülde toplanır.
- **Sürüm takvimi:** NixOS yılda iki sürüm çıkarır ve eski sürüm kısa sürede destek dışı kalır. Sürüm yükseltmesi `librenfra-terraform`'da `nixpkgs` girdisini değiştiren planlı bir PR'dır; server repoları yeni `librenfra-terraform` sürümüne Renovate PR'ı ile geçer.
- **RHEL'i hedefleyen yazılımlar:** İşletim sistemi seviyesinde RHEL uyumu yoktur. Böyle bir yazılım gerekirse NixOS üzerinde UBI tabanlı bir container olarak çalıştırılır.
- **Secret'lar Nix ifadesine yazılmaz:** `/nix/store` makinedeki herkes tarafından okunabilir. Secret'lar çalışma anında OpenBao ajanından gelir ([Secret'lar](../05-secrets.md)).
- **Etkilenenler:** Firewall dışındaki tüm server repoları ve `librenfra-terraform`'un ortak taban modülü.

## Değerlendirilen alternatifler

| Yöntem | Neyi versiyonlar | Neden seçilmedi |
| --- | --- | --- |
| CentOS Stream 10 bootc | OS imajını, digest ile | RHEL uyumu tek başına yeterli gerekçe değil; her değişiklik yeniden başlatma ister, `/etc` drift'i için ek önlem, container registry ve ayrıcalıklı build zinciri gerekir |
| Değiştirilebilir VM + Ansible | Playbook'ları | Makinenin gerçek halinin state'i yok |
| Packer katmanlı şablonlar | Kurulum anındaki diski | Kurulumdan sonrası başka bir araca kalıyor |
| Packer + OCI registry | Aynı diski, tag ve digest ile | Packer'ın eksiğini kapatmıyor |
| Flatcar Container Linux | İşletim sistemini (A/B bölüm) | Paket yöneticisi yok; tüm servislerin container olması gerekir |
| mkosi + systemd-sysupdate | Disk imajını (A/B bölüm) | Yeni, topluluğu küçük; güncelleme sunucusunu kendimiz kurmalıyız |
| LXC | Container imajını | Her server bir VM olarak planlanıyor |
| Proxmox snapshot + PBS | Diskin o anki halini | Versiyonlama değil, güvenlik ağı; git ile bağı yok |
| Fedora bootc | OS imajı | Yaklaşık 13 aylık destek süresi |
| Ubuntu bootc (bootcrew) | OS imajı | Deneysel; Ekim 2026 sonunda build'lerin hepsi başarısızdı |

## Kaynaklar

- [NixOS kılavuzu](https://nixos.org/manual/nixos/stable/)
- [Nix flake'leri](https://nix.dev/concepts/flakes)
- [bootc belgeleri](https://containers.github.io/bootc/print.html)
