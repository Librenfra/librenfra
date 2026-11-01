# Repo dizin yapısı

Her server kendi reposunda tanımlanır. Her server'ın reposunun içeriği o server kurulurken belirlenir. Bu doküman yalnız tüm server repolarının uyduğu şablonu ve `librenfra-terraform` reposunun yapısını anlatır.

| Repo | Ne |
| --- | --- |
| `librenfra` | Ana dokümantasyon |
| `librenfra-terraform` | Tüm server'ların kullandığı Terraform modülleri ve NixOS ortak taban modülü; bir server değildir |
| `librenfra-<modül>` | Bir server; aşağıdaki şablona uyar |

**1 repo = 1 state:** Her server reposunun `main.tf`'i tek bir state dosyasına yazar (`<repo>/terraform.tfstate`). VM, DNS kayıtları, hesaplar ve NixOS kurulumu aynı state'tedir.

## Server reposu şablonu

```text
librenfra-<modül>/
  README.md                  bu server ne, neden böyle; işletme notları
  main.tf                    state yeri, librenfra-terraform modüllerinin çağrısı
  flake.nix                  girdiler: librenfra-terraform (nixpkgs ona bağlı)
  flake.lock                 girdilerin sabitlendiği commit'ler
  configuration.nix          server'ın ana tanımı: ortak taban + modules/
  modules/
    <servis>.nix             servis başına bir NixOS modülü
    secrets.nix              hangi secret hangi dosyaya yazılır
    storage.nix              veri diskinin bağlanması
  pkgs/                      gerekirse: projenin kendi yazdığı paketler
  vm.yml                     CPU, RAM, diskler, NIC, IP
  <veri>.yml                 server'a özel veri: DNS kayıtları, hesaplar, kurallar
  tests/                     smoke testler
```

- **`main.tf`:** Yalnız bağlantı kodudur, birkaç düzine satır. Backend'i ayarlar, veri dosyalarını `yamldecode` ile okur ve `librenfra-terraform` modüllerini `?ref=v1.4.0` gibi sabit bir sürümle çağırır. Hangi modüllerin çağrılacağı server'a göre değişir; `proxmox-vm` ve `nixos-server` her NixOS server'ında vardır.
- **`flake.nix`:** Server'ın NixOS tanımını tek bir `nixosConfigurations.<modül>` çıktısı olarak verir. `librenfra-terraform`'u aynı sürümle girdi olarak alır ve `nixpkgs.follows` ile tüm server'ların aynı `nixpkgs`'i kullanmasını sağlar.
- **`modules/`:** Konfigürasyon NixOS seçenekleriyle yazılır; Nix bunlardan server'daki dosyaları üretir. Tanımdan çıkarılan bir ayar server'dan da gider. Her servis kendi dosyasındadır, böylece PR diff'i hangi servisin değiştiğini doğrudan gösterir.
- **`pkgs/`:** Yalnız server bu projenin yazdığı bir yazılımı çalıştırıyorsa vardır; yazılım Nix paketi olarak build edilir.
- **Veri dosyaları:** `vm.yml` ve server'a özel `.yml` dosyaları. Server'ı değiştirmek için çoğu zaman yalnız bunlar düzenlenir; biçimleri `librenfra-terraform` modüllerinin değişken doğrulamalarıyla (`validation`) kontrol edilir.
- **`tests/`:** `terraform apply`'dan sonra çalıştırılan smoke testler.
- **NixOS tanımı olmayan server:** Firewall'un içi OPNsense'tir; reposunda `flake.nix`, `configuration.nix` ve `modules/` yoktur, içi `config.yml` veri dosyasıyla tanımlanır ([Firewall](06-firewall.md)).

## librenfra-terraform

```text
librenfra-terraform/
  README.md
  flake.nix                    nixpkgs girdisi; nixosModules.base çıktısı
  flake.lock
  nixos/
    base/                      tüm NixOS server'ların ortak modülü:
                               seri konsol, sshd, yönetim anahtarı,
                               OpenBao ajanı, izleme ajanı
  terraform/
    modules/
      proxmox-vm/              VM, sistem diski, ayrı veri diski
      nixos-server/            nixos-anywhere ile kurulum, nixos-rebuild ile
                               güncelleme, çalışan sürüm kontrolü
      cloudflare-dns/          DNS kayıtları
      cloudflare-worker/       Email Worker gibi worker'lar
      opnsense/                alias, kural, NAT, WireGuard, Unbound, Kea
      ad-accounts/             Samba kullanıcı, grup, servis hesabı
      openbao-policies/        policy ve AppRole'ler
      openbao-secrets/         provider kimliklerinin OpenBao'dan okunması
    examples/                  her modül için örnek kök modül
```

- **`flake.nix` neden `librenfra-terraform`'da:** `nixpkgs` sürümü ve ortak taban tek yerde sabitlenir. `librenfra-terraform` sürümü yükselince tüm server'lar aynı `nixpkgs`'e geçer.
- **`nixos-server` modülü:** nixos-anywhere'in Terraform modüllerini (`install`, `nixos-rebuild`) sarar. İlk `apply`'da VM'e NixOS'u kurar; sonraki her `apply`'da sistemi build eder, store yolu değiştiyse server'ı yeni sisteme geçirir. Bir `check` bloğu server'daki `/run/current-system`'i beklenen store yoluyla karşılaştırır, böylece `terraform plan` elle yapılan değişikliği de gösterir.
- **Tek server'ın kullandığı modüller:** `opnsense` veya `ad-accounts` gibi modüller de `librenfra-terraform`'da durur, çünkü Terraform kodunun tek kaynağı `librenfra-terraform`'dur. Yeni bir server yeni bir kaynak türü gerektiriyorsa modül buraya eklenir.

## Kurallar

- **Bir server'ı değiştirmek = yalnız o server'ın reposuna PR.** Paket, konfigürasyon, VM boyutu veya DNS kaydı fark etmez. `librenfra-terraform`'a yalnız yeni bir kaynak türü gerektiğinde PR açılır.
- **Server reposunda yalnız bağlantı kodu.** `main.tf` modülleri çağırır, kaynak tanımlamaz; kaynakların kendisi `librenfra-terraform` modüllerindedir.
- **Server'daki her şey repodan gelir.** Server'da bir şey değiştirilmek isteniyorsa NixOS tanımına PR açılır.
- **Kalıcı veri yalnız `/var` altında ve veri diskinde.**
- **Secret değeri hiçbir repoda ve hiçbir Nix ifadesinde yok.** `/nix/store` server'daki herkes tarafından okunabilir. `secrets.nix` yalnız ajan şablonlarını tutar.
- **`librenfra-terraform` sürümü Renovate ile yükselir.** `main.tf`'teki modül kaynağı ve `flake.nix`'teki `librenfra-terraform` girdisi aynı PR'da yükseltilir.
- **Sürüm ve commit kuralları:** `v1.2.3` sürümü, trunk tabanlı `main`, Conventional Commits (`feat(mail): DKIM imzası`), korumalı `main`: doğrudan push yok, PR + yeşil kontrol zorunlu.
