# 0002. Dizin servisi Samba AD'dir

- **Durum:** Kabul edildi
- **Tarih:** 2026-11-01

## Bağlam

librenfra'nın kullanıcı, grup ve servis hesaplarını tutan merkezi bir dizin servisine ihtiyacı var. Mail girişi (Dovecot) ve OpenBao'ya insan girişi bu servise bağlanacak; istemci makinelerin de domain'e katılıp merkezi girişle açılması hedefleniyor. Repo adı `librenfra-active-directory` olarak sabit; içinde hangi çözümün çalışacağı bu kararla belirlenir. Değerlendirilen iki seçenek Samba AD ve FreeIPA idi.

## Karar

Dizin servisi Samba AD domain controller'dır. NixOS üzerinde ([karar 0001](0001-isletim-sistemi-secimi.md)) tek bir server olarak çalışır ve tanımı `librenfra-active-directory` reposundadır.

## Gerekçe

- **Üç istemci ailesi:** Açık kaynak çözümler arasında Windows, macOS ve Linux istemcilerin üçünü de domain'e katabilen tek seçenek Samba AD'dir.
- **NixOS ile uyum:** nixpkgs'teki Samba, Samba'nın kendi Heimdal Kerberos'uyla derlenir; AD DC desteği `samba4Full` paketindedir. FreeIPA'nın sunucu tarafı ise nixpkgs'te paketlenmemiştir.
- **Standart protokoller:** Dovecot, Postfix ve OpenBao Samba AD'ye LDAPS ile bağlanır; ek bir entegrasyon katmanı gerekmez.

## Sonuçlar

- **Domain:** Template'te realm `AD.DOMAIN.COM`, NetBIOS adı `LIBRENFRA`; kurum kendi domain'ini yazar. `ad.domain.com` alt alanının DNS'ini Samba'nın kendi DNS'i sunar; OPNsense'teki Unbound bu alanı domain controller'a yönlendirir ([Firewall](../06-firewall.md)).
- **Fonksiyonel seviye:** Varsayılan 2008R2 seviyesiyle kurulur. 2016 seviyesi Samba 4.19'dan beri kısmen desteklenir; gerekirse sonradan yükseltilir.
- **Domain bir kez kurulur:** `samba-tool domain provision` yalnız ilk açılışta çalışır. Sonrasında kullanıcı ve gruplar `accounts.yml`'den Terraform ile, Samba'nın kendisi NixOS tanımından yönetilir ([Repo dizin yapısı](../02-repo-yapisi.md#server-reposu-şablonu)).
- **Tek domain controller:** İlk aşamada tek DC vardır ve güncellemedeki kesinti kabul edilir. İkinci DC, domain'e katılan istemciler çoğalınca eklenir.
- **İlk doğrulama:** Samba AD DC librenfra'da NixOS üzerinde henüz çalıştırılmadı; hesapları yönetecek LDAP tabanlı AD provider'ının (isometry/ad) Samba ile çalıştığı da doğrulanmadı. Bu, Samba kurulurken yapılacak ilk iştir.
- **Etkilenenler:** `librenfra-active-directory`, `librenfra-mail` (Dovecot ve Postfix'in LDAP bağlantısı), OpenBao (LDAP auth), `librenfra-firewall` (DNS yönlendirmesi ve LDAPS kuralı).

## Değerlendirilen alternatifler

| Seçenek | Artı | Neden seçilmedi |
| --- | --- | --- |
| FreeIPA (RHEL IdM) | Linux istemciler için güçlü, Red Hat destekli | Windows makineler domain'e katılamaz, yalnız AD ile trust kurulabilir; sunucu tarafı nixpkgs'te yok |

## Kaynaklar

- [Samba wiki: Samba'yı AD domain controller olarak kurmak](https://wiki.samba.org/index.php/Setting_up_Samba_as_an_Active_Directory_Domain_Controller)
- [NixOS wiki: Samba](https://wiki.nixos.org/wiki/Samba)
