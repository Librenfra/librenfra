# Altyapı (OpenTofu)

Bu dizin Librenfra ortamını Proxmox VE üzerinde kurar: segment köprüleri, firewall ve bootc makineleri.

- `modules/opnsense-config/`: OPNsense'in ilk ayarını (`firewall/config.xml.tftpl`) doldurur. Ortam ve `tests/firewall` aynı modülü kullanır.
- `modules/bootc-vm/`: tek bir bootc makinesi, isteğe bağlı veri diski ve cloud-init user-data'sı.
  - İşletim sistemi diski yalnızca makine oluşturulurken imaj dosyasından alınır. Sonraki güncellemeler makinenin içinde `bootc switch` ile yapılır; yeni bir disk dosyası mevcut makineyi değiştirmez.
  - Veri diski, `9000 + VM numarası` numaralı, açılmayan ve korumalı bir tutucu makinede durur (`prevent_destroy`). Makine silinip yeniden kurulsa da disk kalır ve makineye `lnfr-data` seri numarasıyla takılır.
- `envs/home/`: ev ortamı.
  - `network.tf`: `vmbr1` (LAN 10.10.10.0/24), `vmbr2` (DMZ 10.10.20.0/24), `vmbr3` (LAB 10.10.30.0/24). Köprülerin fiziksel portu yoktur; dış bağlantı firewall'un `vmbr0`'daki WAN arayüzündendir.
  - `firewall.tf`: VM 100 `fw`, OPNsense. Arayüz sırası WAN, LAN, DMZ, LAB. Nano imajı checksum ile doğrulanarak indirilir. Makine kapalı oluşturulur; `terraform_data.fw_import` ilk açılışta `config.xml`'i içe aktarır (bkz. [firewall/README.md](../firewall/README.md)). root parolası, API anahtarı ve Librenfra CA ile imzalı arayüz sertifikası burada üretilir; ops için `fw_api_credentials` ve `ca_cert` çıktıları.
  - `dc.tf`: VM 120 `dc`, 10.10.10.10, veri diski 9120.
  - `mail.tf`: VM 130 `mail`, DMZ'de 10.10.20.10, veri diski 9130 (`/var/vmail`).
  - `k8s.tf`: VM 140 `k8s-cp` (10.10.10.20) ve VM 141 `k8s-w1` (10.10.10.21), aynı imajdan; rolü cloud-init belirler. Kümenin CA'sı ve kubeadm bootstrap token'ı burada üretilir. Veri diskleri yoktur.
  - `ops.tf`: VM 150 `ops` (10.10.10.30), veri diski 9150 (`/var/lib/librenfra`: runner ve OpenTofu state'i). ops'un SSH anahtarı burada üretilir ve bütün makinelere yetkili anahtar olarak verilir. Runner ilk açılışta `runner_token` ile GitHub'a kaydolur.
  - `pki.tf`: ortamın iç CA'sı; dc'nin LDAPS'i ve mail'in TLS'i bu CA'nın sertifikalarını kullanır.
- `cloudflare/`: mail'in internet tarafı. Gelen posta Email Routing'den bir Email Worker'a, oradan
  tünel üzerinden mail makinesindeki alıcıya gider; alıcı postayı Postfix'e verir. Giden posta
  doğrudan alıcı sunuculara gider ve DKIM ile imzalanır; anahtar burada üretilir, açık anahtarı
  `librenfra._domainkey` kaydıyla yayınlanır. Çıktıları (`cloudflared_token`, `mail_inbound_token`,
  `mail_dkim_key`) `envs/home`'a verilir.

## Testler

Proxmox olmadan, sahte provider ile:

```sh
cd infra/modules/bootc-vm && tofu init && tofu test
cd infra/modules/opnsense-config && tofu init && tofu test
cd infra/envs/home && tofu init -backend=false && tofu test
cd infra/cloudflare && tofu init -backend=false && tofu test
node --test infra/cloudflare/tests/email.test.mjs
```

## İlk kurulum

Diskler sürümün GitHub Release'inden indirilir (`librenfra-<rol>-<sürüm>.qcow2`). Boş bir Proxmox'ta ortam `tools/bootstrap.sh` ile bir kez, ev ağındaki bir makineden kurulur; sonraki her kurulum ve güncelleme pipeline ile `ops` üzerinden yapılır.

```sh
export PROXMOX_VE_ENDPOINT=https://192.168.1.200:8006/
export PROXMOX_VE_API_TOKEN='tofu@pve!librenfra=...'
export TF_VAR_dc_admin_password='...'
export TF_VAR_cloudflared_token='...' TF_VAR_mail_inbound_token='...' TF_VAR_mail_dkim_key='...'
tools/bootstrap.sh 0.2.0 ~/librenfra/home.tfvars
```

Betik:

1. GitHub'da `home` ortamının secret'larını ve değişkenlerini yazar.
2. İlk `tofu apply`'ı çalıştırır; firewall'un `config.xml`'i bu sırada içe aktarılır.
3. `ops`'un SSH anahtarını Proxmox'ta `root`'un `authorized_keys`'ine ekler.
4. State'i ve `home.tfvars`'ı `ops`'un veri diskine (`/var/lib/librenfra/tofu`) taşır; çalıştığı makinedeki state silinir.
5. `ops`'taki runner'ı yeni bir kayıt token'ıyla GitHub'a kaydeder ve ilk `deploy.yml` çalışmasını başlatır. Firewall'un kuralları, DNS ve DHCP ayarı bu çalışmada uygulanır, ardından ortam testleri koşar.

`ops` LAN'dadır ve ev ağından ulaşılamaz; betik ona Proxmox üzerinden atlar ve bunun için iş süresince Proxmox'un LAN köprüsüne geçici bir adres (`10.10.10.254/24`) verir. Gerekenler: `tofu`, `gh` (depoda yönetici yetkisiyle giriş yapılmış), `jq`, `python3` ve `ssh-agent`'ta hem Proxmox'un `root`'una hem makinelere (`ssh_authorized_keys`) giren anahtar.

## Proxmox'ta gerekenler

- `local` deposunda `import` ve `snippets` içerik türleri açık olmalı (Datacenter → Storage → local → Content).
- Provider, snippet yüklemek için düğüme SSH ile bağlanır (`ssh-agent` ve `PROXMOX_VE_SSH_USERNAME`).
- `import` içerik türü Proxmox VE 8.4 ve sonrasında vardır.
- Firewall'un ilk ayarı için `local` deposunda `iso` içerik türü açık olmalı; `import-config` düğümde `qm`, `pvesm` ve `genisoimage` kullanır (Proxmox VE'de kuruludur). SSH hedefi `proxmox_ssh` değişkenidir (varsayılan `root@192.168.1.200`).

## Pipeline

Kurulum ve güncellemeler `.github/workflows` altındaki iş akışlarıyla yapılır:

- `build.yml`: her push'ta statik testler, imajların derlenmesi (`sha-<commit>` etiketiyle), rol testleri ve firewall testi. `v<sürüm>` etiketinde imajlar sürüm ve `latest` etiketleriyle yayınlanır, diskler (`disk.yml`) Release'e yüklenir ve ortam güncellenir (`deploy.yml`).
- `disk.yml`: bir sürümün disklerini (`librenfra-<rol>-<sürüm>.qcow2` ve `.sha256`) Release'e yükler; elle de çalıştırılabilir.
- `deploy.yml`: ortamın içindeki `ops` makinesinin runner'ında (`librenfra-ops` etiketi) `tools/deploy.sh <sürüm>` çalıştırır. Proxmox API'si ev ağında olduğu için GitHub'ın runner'ları ortama ulaşamaz.

`tools/deploy.sh` sırasıyla `tofu apply` yapar, firewall ayarını uygular (`firewall/ayar.yml`), bootc makinelerini (dc, mail, k8s) `tools/update.sh` ile yeni imaja geçirir, ortam testlerini (`tests/ortam`) çalıştırır ve en son `ops`'un kendi güncellemesini ister. Sağlık denetimini (`tools/health.sh`) geçemeyen makine önceki imaja döner ve kurulum orada durur. `ops` işi bitince yeni imajla yeniden başlar (`librenfra-self-update`).

GitHub'da gerekenler:

- `home` adında bir ortam (Settings → Environments). Secret'lar: `PROXMOX_VE_API_TOKEN`, `DC_ADMIN_PASSWORD`, `CLOUDFLARED_TOKEN`, `MAIL_INBOUND_TOKEN`, `MAIL_DKIM_KEY`. Değişkenler: `PROXMOX_VE_ENDPOINT`, `PROXMOX_VE_SSH_USERNAME`.
- ghcr.io'daki `librenfra/<rol>` paketleri herkese açık olmalı; makineler imajları kimlik bilgisi olmadan çeker.

`ops`'ta gerekenler:

- Secret olmayan değişkenler veri diskinde `/var/lib/librenfra/tofu/home.tfvars`'tadır, state aynı dizindedir (`home.tfstate`).
- Ortamı yöneten SSH anahtarı (`/etc/librenfra/secrets/ops-ssh-key`, runner'a `/var/lib/librenfra/ssh/id_ed25519` olarak verilir) makinelerdeki `librenfra` kullanıcısında ve Proxmox düğümünde `root`'un `authorized_keys`'inde olmalıdır.
