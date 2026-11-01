# Librenfra

Librenfra projesi "**infrastructure as code**" ve "**GitOps**" prensiplerini kullanarak bir kurumun ihtiyaç duyacağı tüm IT altyapısını tekrar kullanılabilir ve kolay entegre edilebilir bir template haline getirmeyi amaçlar.

Bu repo projenin ana dokümantasyonudur. Her modülün kendi dokümantasyonu kendi reposundadır; buradan onlara referans verilir.

## Repolar

**Repo kuralı: 1 repo = 1 state olmak zorundadır.** Her repo kendine ait olan modülün tüm bileşenlerini içerir ve o modüle ait bileşenlerin hiçbiri ilgili repo dışındaki bir yerde bulundurulamaz. `librenfra` ve `librenfra-terraform` dışındaki her repo bir server'dır.

**İsim kuralı:** `librenfra-<modül>`. Her modül hangi servisin işlevselliğini tamamlıyorsa o servisin genel ismini alır. "Samba", "opnsense" gibi özel isimler modül ismi olamaz.

| Repo | İçerik |
| --- | --- |
| `librenfra` | Ana dokümantasyon: mimari, repo ve dizin yapısı, karar kayıtları; modül dokümantasyonlarına referans |
| `librenfra-terraform` | Tüm server'ların kullandığı Terraform modülleri ve NixOS ortak taban modülü |
| `librenfra-firewall` | Firewall: OPNsense konfigürasyonu (alias, kural, NAT, WireGuard VPN, DNS, DHCP) veri olarak; ağ haritası |
| `librenfra-secrets` | OpenBao: NixOS tanımı ve policy'ler |
| `librenfra-active-directory` | Samba: Active Directory'nin NixOS tanımı; kullanıcı, grup ve servis hesapları veri olarak |
| `librenfra-mail` | Mail: NixOS tanımı, Email Worker ve alıcısı, VM ve DNS verisi |

Proxmox host'larının ve yönetim makinesinin kurulumu bu template'in kapsamı dışındadır.

**Sürümleme:** `v1.2.3` şeklindedir. Server repoları trunk tabanlıdır; `main` neyse server odur.

## Dokümanlar

Sırayla okunması önerilir:

1. [Mimari](docs/01-mimari.md): template'in bileşenleri, server tanımı, sürümleme
2. [Repo dizin yapısı](docs/02-repo-yapisi.md): server reposu şablonu ve `librenfra-terraform`
3. [CI/CD akışı](docs/03-ci-cd.md): bir değişikliğin PR'dan server'a yolculuğu
4. [State](docs/04-state.md): server'ın hangi parçasının nerede ve hangi kimlikle tutulduğu
5. [Secret'lar](docs/05-secrets.md): OpenBao düzeni ve secret'ın server'a varış yolu
6. [Firewall konfigürasyonunun versiyonlanması](docs/06-firewall.md): örnek bir kural değişikliği
7. [Karar kayıtları](docs/kararlar/README.md): alınan, açık ve rafa kaldırılan kararlar, gerekçeleriyle
