# 0002. İki aşamalı geliştirme: önce açık kaynak temel, sonra çok ortam desteği

- **Durum:** Kabul edildi
- **Tarih:** 2026-11-21

## Bağlam

Bu kayıt, [Entegrasyon](../03-entegrasyon.md) dökümanı üzerinde çalışırken projenin yönünün nasıl değiştiğini ve neden iki aşamalı bir geliştirme sırasına karar verildiğini anlatır.

Projenin başlangıçtaki hedefi, kurumların açık kaynak altyapıya az eforla geçebilmesiydi. Bunun için Librenfra servislerinin kurumların hâlihazırda kullandığı dizin ve mail altyapısıyla uyumlu çalışması gerektiği düşünüldü. Entegrasyon dökümanı bu düşünceyle yazıldı ve iki sürümden geçti. Ardından dökümandaki tasarım gerçek servisler ayağa kaldırılarak test edildi. Test sonuçları, projenin bu uyumluluk sorunuyla başlamaması gerektiğini gösterdi.

## Fikrin gelişimi

### 1. Her türlü dizin ve mail altyapısına uyumlu ara katman

**Ne önerildi:** Servisler ile kurumun mevcut altyapısı arasında duran ve iki tarafı birbirine uyduran bir ara katman yazılması. Ara katman bağlandığı dizinin türünü kendisi keşfedecek, farkları normalize edecek ve servislere her kurumda aynı arayüzü sunacaktı. Hedeflenen dizinler Windows AD, Samba AD, FreeIPA, OpenLDAP ve Entra ID; mail tarafında ise Exchange, Microsoft 365 ve diğer mail sunucularıydı.

**Neden bırakıldı:** Kapsam çok genişti. Her dizin türü aynı soruya farklı cevap veriyor, bazı sorulara hiç cevap veremiyordu. Örneğin MSCHAPv2 ile parola doğrulama FreeIPA'da, şemasız OpenLDAP'ta ve Entra ID'de çalışmıyor. Bu kadar farklı dizini aynı anda desteklemek, asıl altyapı geliştirilmeden önce bitmeyen bir uyumluluk işine dönüşecekti.

### 2. Yalnızca Microsoft altyapısına uyumlu ara katman

**Ne önerildi:** Üniversitelerde kimlik ve posta altyapısının neredeyse tamamen Microsoft ürünlerine dayandığı varsayımıyla kapsam Microsoft'a daraltıldı. Hedefler üç düzene indirildi: kurum içi (AD ve Exchange Server), hibrit (AD, Entra ID'ye senkron; posta Exchange Online'da) ve yalnızca bulut (Entra ID ve Exchange Online). Samba AD, AD ile aynı protokolleri konuştuğu için kurum içi düzenin içinde sayıldı.

**Neden bırakıldı:** Dökümandaki tasarım, Samba AD'ye karşı altı ayrı deneyle test edildi. Deneylerde Wi-Fi doğrulama, Linux sunucu girişi, tarayıcıda giriş, posta, çekirdek prototipi ve LDAP arayüzü sınandı. Sonuçlar şunu gösterdi:

| Bulgu | Anlamı |
| --- | --- |
| FreeRADIUS, SSSD, Keycloak ve Postfix AD'ye doğrudan, ara katman olmadan bağlanabiliyor | Ara katman ayrı bir yazılım olarak gerekli değil |
| Servisleri ortak bir LDAP arayüzünün arkasına almak işi azaltmadı | Arayüz tek hata noktası ve gecikme ekledi; Kerberos, MSCHAPv2 ve parola değiştirme arayüzden geçemedi |
| Wi-Fi doğrulaması için domain üyeliği şart | Dökümandaki "dizine yalnızca soran servis" varsayımı yanlış |
| Samba AD'de MSCHAPv2 varsayılan olarak kapalı ve bu LDAP üzerinden keşfedilemiyor | Kurumun dizinini dışarıdan doğru tanımak sanıldığından zor |
| Araçların varsayılan ayarları sessizce yanlış ya da güvensiz sonuç veriyor | Süresi dolmuş hesap içeri alınıyor, iç içe gruplar gelmiyor, sahte `From:` başlığı geçiyor |
| Kapanan hesabın erişimi varsayılan ayarlarla hemen kesilmiyor | SSH anahtarı, refresh token ve önbellekli doğrulama gecikmeli kapanıyor |

En zor sorunlar, Librenfra'nın kontrol etmediği taraftan geliyordu: kurumun kendi AD ayarları, Entra ID ve Exchange. Ayrıca gerçek Windows AD, Entra ID ve Exchange bu ortamda test edilemedi. Hiç kurulmamış bir altyapının, kontrol edilemeyen ve test edilemeyen ortamlara uyumluluğuyla başlamak doğru bir sıra değildi.

### 3. Önce altyapıyı geliştirmek

**Ne önerildi:** Uyumluluk sorununu ertelemek ve önce yalnızca açık kaynak bileşenlerle eksiksiz bir kurum altyapısı geliştirmek. İki tarafı da Librenfra kurduğu için güvenli varsayılanlar baştan doğru seçilebilir ve her şey uçtan uca test edilebilir. Test edilen ve çalıştığı görülen parçalar bu altyapının başlangıç noktası olur.

## Karar

Proje iki aşamada geliştirilecek.

### Aşama 1: Açık kaynak temel altyapı

Bir kurumun altyapısı yalnızca açık kaynak bileşenlerle, temelden başlanarak oluşturulur.

- Geliştirme, her kurumun ihtiyaç duyduğu temel servislerle başlar: **dizin (AD)** ve **mail sunucuları**.
- Temel servisler tamamlandıkça, onlara bağlı diğer servisler eklenir (örneğin kablosuz ağ doğrulama, Linux sunucu girişi, tek oturum açma).
- Bu aşamada kurumların mevcut altyapısıyla uyumluluk hedeflenmez. Altyapının bütün parçaları Librenfra tarafından kurulur ve birlikte test edilir.
- Servisler [0001](0001-stateless-isletim-sistemi.md) kaydında değerlendirilen sürümlü ve stateless yapı üzerinde geliştirilir.

### Aşama 2: Çok ortam desteği

Aşama 1'de oluşturulan altyapıya, kurumlar arasındaki farklara uygun çalışabilmesi için çok ortam desteği kazandırılır.

- Destek **uç servislerden başlayıp temele doğru** ilerler. Önce kurumun mevcut dizinine ve mail sunucusuna bağlanabilen uç servisler (örneğin kablosuz ağ doğrulama, tek oturum açma) farklı ortamlarda çalışır hale getirilir. Sonra sırayla temel servislere kadar gelinir.
- Bu sıra, kurumların mevcut altyapılarını bir anda değiştirmeden, uç uygulamalardan başlayarak parça parça geçebilmesini sağlar.
- [Entegrasyon](../03-entegrasyon.md) dökümanı ve test bulguları bu aşamanın girdisidir.
