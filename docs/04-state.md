# State

Bir server'ın tam hali dört parçadan oluşur:

| Parça | Nerede durur | Versiyon kimliği |
| --- | --- | --- |
| Server'ın içi (OS, paketler, konfigürasyon, servisler) | Server reposundaki flake; build sonucu yönetim makinesinin ve server'ın Nix store'unda | Sistemin store yolu (`/nix/store/<hash>-nixos-system-…`) |
| Server'ın dışı (VM, diskler, DNS, firewall kuralları, dizin hesapları, OpenBao policy'leri) | R2'de Terraform state, repo başına bir dosya | tfstate serial |
| Veri (posta kutuları, Samba veritabanı, OpenBao raft) | Veri diskinde `/var` altında + PBS yedeği | Yedek zamanı |
| Secret'lar | OpenBao | KV sürümü |

İlk iki parçayı tek bir kayıt bağlar: Terraform state'i, VM'in yanında server'a son uygulanan sistemin store yolunu da tutar. "Bu server'da şu an ne çalışıyor" sorusunun cevabı reponun state'idir.

## Terraform state'inin yeri

Terraform state'i ortamın dışında, kilitli ve sürümlü bir S3 bucket'ında durur.

| Seçenek | Artı | Eksi |
| --- | --- | --- |
| **Cloudflare R2 (öneri)** | Ortam dışında, yani doğal yedek; S3 uyumlu | Dış servise bağımlılık; kilitleme davranışı ilk kurulumda test edilmeli |
| MinIO/Garage, Proxmox'ta VM | Tamamen self-hosted | Yönettiği altyapının içinde: tavuk-yumurta sorunu, ayrıca yedeklenmesi gerekir |
| Terraform Cloud / HCP | Hazır kilit ve UI | Proxmox API'ye erişemez, local execution gerekir; "libre" hedefiyle çelişir |

Yapı: tek bucket `librenfra-state`, bucket sürümleme açık, kilit için S3 backend'in `use_lockfile = true` seçeneği. State içinde AppRole secret ID'leri gibi sırlar olduğu için bucket'a yalnız yönetim makinesinin erişim anahtarı yetkilidir. OpenTofu seçilirse state ayrıca istemci taraflı şifrelenebilir.

## Bucket düzeni

Her server reposunun tek bir state dosyası vardır; "1 repo = 1 state" kuralı bucket'ta da görünür.

```text
librenfra-state/                     (R2 bucket, sürümleme açık)
  librenfra-firewall/
    terraform.tfstate                VM, alias, kural, NAT, WireGuard, Unbound, Kea
    snapshots/config.xml.enc         OPNsense'in tam config'i, şifreli
  librenfra-secrets/
    terraform.tfstate                VM, NixOS sistemi, policy ve AppRole'ler
  librenfra-active-directory/
    terraform.tfstate                VM, NixOS sistemi, hesaplar
  librenfra-mail/
    terraform.tfstate                VM, NixOS sistemi, Cloudflare kayıtları ve worker
```

OpenBao'nun gece aldığı raft snapshot'ı state bucket'ına değil, ayrı `librenfra-backup` bucket'ına yazılır. OpenBao'daki R2 anahtarı yalnız o bucket'a yetkilidir; böylece state bucket'ına yalnız yönetim makinesi erişir.

Bucket sürümlemesi sayesinde her `apply`'dan önceki state geri alınabilir; bu, server'ların uygulama geçmişini de tutar.

## Drift'i kapatmak

- **Server'ın içi:**
  - `/nix/store` salt okunurdur ve Nix'in yönettiği `/etc` dosyaları her `switch`'te tanımdan yeniden üretilir.
  - `users.mutableUsers = false` ile server'da elle kullanıcı veya parola değiştirilemez.
  - `nixos-server` modülünün `check` bloğu çalışan sistemin store yolunu state'tekiyle karşılaştırır; fark `terraform plan`'da görünür.
  - Nix'in yönetmediği yollara elle yazılan dosyalar kalabilir. Kök dosya sistemini her açılışta sıfırlayan "impermanence" düzeni, ilk server'lar oturduktan sonra ortak tabana eklenebilir.
- **Server'ın dışı:** `terraform plan` farkı gösterir. Samba'da elle eklenen bir hesap state'te olmadığı için `plan`'da görünmez; `ad-accounts` modülündeki bir `check` bloğu dizindeki hesap listesini `accounts.yml` ile karşılaştırır.

## Veri

Kalıcı veri yalnız `/var` altında ve ayrı veri disklerinde durur. Server yeni sürüme geçerken veri diskine dokunulmaz. Veri disklerinin yedeği Proxmox Backup Server ile alınır; Terraform veri diskini VM'den ayrı bir kaynak olarak tutar, böylece VM yeniden oluşturulsa da veri kalır. Samba veritabanının tutarlı yedeği için Samba her gece `samba-tool domain backup offline` ile veri diskine bir yedek de yazar.
