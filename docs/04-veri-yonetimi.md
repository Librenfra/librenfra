# Veri yönetimi

[0001](decisions/0001-stateless-isletim-sistemi.md) kaydında işletim sisteminin stateless olması hedeflendi. Ancak Librenfra'nın kuracağı servisler, işletim sistemi stateless olsa da kendi verilerini tutmak zorundadır. Bu döküman servislerin hangi verileri tuttuğunu ve bootc'un bu verileri nasıl yönettiğini anlatır.

## Servislerin verileri

Her servis için verinin türü dört gruptan biridir:

- **Veri:** Servisin çalışırken ürettiği ve kaybolmaması gereken bilgi.
- **Yapılandırma:** Servisin nasıl çalışacağını belirleyen dosyalar.
- **Secret:** Parolalar, anahtarlar, keytab'lar ve sertifikaların özel anahtarları.
- **Önbellek:** Silindiğinde servisin kendisinin yeniden oluşturduğu dosyalar.

### Samba AD DC

| Veri | Yol | Tür |
| --- | --- | --- |
| Dizin veritabanı: kullanıcılar, gruplar, parola özetleri, `krbtgt` anahtarı | `/var/lib/samba/private/sam.ldb`, `/var/lib/samba/private/sam.ldb.d/` | Veri ve secret |
| DC'nin makine hesabı ve Kerberos anahtarları | `/var/lib/samba/private/secrets.ldb`, `secrets.tdb`, `secrets.keytab` | Secret |
| Veritabanındaki şifreli alanların anahtarı | `/var/lib/samba/private/encrypted_secrets.key` | Secret |
| LDAPS sertifikası ve özel anahtarı | `/var/lib/samba/private/tls/` | Secret |
| Windows kimliği ile Linux kimlik numarası eşlemesi | `/var/lib/samba/private/idmap.ldb` | Veri |
| Grup ilkeleri ve oturum açma betikleri (SYSVOL) | `/var/lib/samba/sysvol/` | Veri |
| Hesap ilkeleri, paylaşım bilgileri | `/var/lib/samba/*.tdb` | Veri |
| Samba yapılandırması | `/etc/samba/smb.conf` | Yapılandırma |
| Kerberos yapılandırması | `/etc/krb5.conf` | Yapılandırma |
| Önbellek, kilit ve soket dosyaları | `/var/cache/samba`, `/run/samba` | Önbellek |

Laboratuvardaki kurulumda `private` dizini 42 MB, SYSVOL 96 KB, `smb.conf` 10 satırdı. SYSVOL dosyaları `security.NTACL` genişletilmiş özniteliğini ve POSIX ACL'lerini kullanır; bu yüzden SYSVOL'un bulunduğu dosya sistemi genişletilmiş öznitelikleri desteklemelidir.

### Mail: Postfix ve Dovecot

| Veri | Yol | Tür |
| --- | --- | --- |
| Posta kutuları | Dovecot'un `mail_location` ayarındaki dizin (ör. `/var/vmail`) | Veri |
| Dovecot indeksleri | Posta kutularının yanında | Önbellek |
| Teslim edilmeyi bekleyen postalar (kuyruk) | `/var/spool/postfix` | Veri |
| Postfix'in TLS oturum önbelleği | `/var/lib/postfix` | Önbellek |
| Postfix ve Dovecot yapılandırması, gönderen ve alıcı haritaları | `/etc/postfix`, `/etc/dovecot` | Yapılandırma |
| TLS sertifikalarının özel anahtarları | Yapılandırmada belirtilen yol | Secret |
| DKIM anahtarları | Seçilecek DKIM aracına göre | Secret |
| Spam filtresinin öğrenme verisi | Seçilecek spam filtresine göre | Veri |

### Tek oturum açma: Keycloak

| Veri | Yol | Tür |
| --- | --- | --- |
| Realm'ler, istemciler, yerel kullanıcılar, oturumlar | PostgreSQL veritabanı (`/var/lib/postgresql`) | Veri |
| İstemci secret'ları, imza anahtarları | PostgreSQL veritabanı | Secret |
| Keycloak yapılandırması | `conf/keycloak.conf` | Yapılandırma |
| Truststore (DC'nin CA sertifikası) | `conf/truststores/` | Yapılandırma |

Keycloak'ın varsayılan `dev-file` veritabanı Keycloak belgelerine göre yalnızca geliştirme içindir ve verisini kurulum dizininin altındaki `data/` dizinine yazar. Üretimde veritabanı PostgreSQL'dir. Keycloak 26 ile oturumlar da varsayılan olarak veritabanında tutulur.

### Kablosuz ağ doğrulama: FreeRADIUS

| Veri | Yol | Tür |
| --- | --- | --- |
| Domain üyeliğinin makine hesabı parolası | `/var/lib/samba/private/secrets.tdb` | Secret |
| EAP sunucu sertifikası ve özel anahtarı | `/etc/freeradius/3.0/certs/` | Secret |
| FreeRADIUS yapılandırması | `/etc/freeradius/3.0/` | Yapılandırma |
| Kayıtlar | `/var/log/freeradius/` | Önbellek |

FreeRADIUS'un kendi verisi yoktur. Domain üyeliği kaybolursa sunucu domain'e yeniden katılır.

### Linux sunucular: SSSD

| Veri | Yol | Tür |
| --- | --- | --- |
| Domain üyeliğinin makine anahtarı | `/etc/krb5.keytab` | Secret |
| SSSD yapılandırması | `/etc/sssd/sssd.conf` | Yapılandırma |
| Kullanıcı ve grup önbelleği | `/var/lib/sss/db/` | Önbellek |

## bootc bu verileri nasıl yönetiyor

bootc'un dosya sistemi kuralları kendi belgelerinden ([bootc-filesystem(7)](https://github.com/bootc-dev/bootc/blob/main/docs/src/bootc-filesystem.7.md)) alınmıştır.

### `/usr` ve imajdaki diğer dizinler

composefs açıkken (`/usr/lib/ostree/prepare-root.conf` içinde `[composefs] enabled = true`) kök dosya sisteminin tamamı salt okunurdur. `/usr`, `/opt` ve imajda oluşturulan diğer üst dizinler imajla birlikte gelir ve güncellemede imajla birlikte bütün olarak değişir. Geri dönüşte eski imajın içeriğine döner.

Servisler buraya yazamaz. Keycloak'ın `dev-file` veritabanı gibi kurulum dizinine yazan yazılımların yazdığı kısım `/var`'a taşınmalıdır.

### `/etc`

`/etc` varsayılan olarak yazılabilir ve kalıcıdır. Güncellemede bootc üç yollu bir birleştirme yapar:

- Yeni imajın `/etc`'si taban alınır.
- Makinede değiştirilmiş dosyalar korunur.
- Değiştirilmiş bir dosya, yeni imajdaki sürümünü almaz.

Makinedeki değişiklikler `ostree admin config-diff` ile görülebilir. Dosyanın sahibi, izinleri ya da genişletilmiş öznitelikleri değiştiyse bu da değişiklik sayılır.

`/etc` geçici de yapılabilir (`prepare-root.conf` içinde `[etc] transient = true`). Bu durumda `/etc` her açılışta imajdaki haline döner ve çalışırken yapılan değişiklikler yeniden başlatmada kaybolur. bootc belgeleri sapmayı azaltmak için bunu öneriyor, ama makineye özgü dosyaların başka bir yerde tutulmasını gerektiriyor.

### `/var`

`/var` kalıcıdır ve imajdan bağımsızdır:

- İmajdaki `/var` içeriği yalnızca ilk kurulumda açılır. Sonraki imajlardaki değişiklikler `/var`'a uygulanmaz.
- bootc güncellemesi ve geri dönüşü `/var`'a dokunmaz. Bir servis güncellemede verisinin biçimini değiştirirse, geri dönüşte eski servis yeni biçimdeki veriyle karşılaşır.
- Servislerin ihtiyaç duyduğu dizinler imajda değil, `tmpfiles.d` ya da birim dosyasındaki `StateDirectory=` ile oluşturulmalıdır.
- `/var` ayrı bir bölüm ya da bağlama noktası olabilir. Ayrı bölüm değilse bootc onu `/ostree/deploy/<stateroot>/var` dizininden bağlar ve bütün imaj sürümleri aynı `/var`'ı kullanır.

### `/run`

`/run` her açılışta boştur. İmajda `/run` altına içerik koymak desteklenmez.

### Secret'lar

bootc'un secret'lar için tek bir yöntemi yoktur. Belgelerde şu yollar sayılıyor:

- İmaja koymak (yalnızca registry korunuyorsa ve yalnızca başlangıç secret'ları için).
- Kurulumda ya da disk imajında vermek.
- Bulut ortamlarında metadata sunucusundan almak.
- systemd credential'ları ile vermek.

Disk şifrelemesi de bootc'un dışında kurulur. bootc LUKS'u kendisi yönetmez; kurulum aracı LUKS'u kurar ve bootc şifreli dosya sisteminin üzerine yazar.

### Servislerin verileri nereye düşüyor

| Tür | Servislerdeki yeri | bootc'ta yeri | Güncellemede | Geri dönüşte |
| --- | --- | --- | --- | --- |
| Veri | `/var/lib/samba`, posta kutuları, `/var/spool/postfix`, `/var/lib/postgresql` | `/var` | Değişmez | Değişmez |
| Yapılandırma | `/etc/samba`, `/etc/postfix`, `/etc/dovecot`, `/etc/freeradius`, `/etc/sssd`, `/etc/krb5.conf` | `/etc` | Değiştirilmemiş dosyalar yeni imajdan gelir, değiştirilmişler korunur | Aynı birleştirme |
| Secret | Çoğu `/var/lib/samba/private`'ta; bir kısmı `/etc`'de (`/etc/krb5.keytab`, FreeRADIUS sertifikaları) | `/var` ya da `/etc` | `/var`'dakiler değişmez, `/etc`'dekiler birleştirmeye girer | Aynı |
| Önbellek | `/var/cache`, `/var/lib/sss/db`, `/run/samba` | `/var` ya da `/run` | Değişmez ya da silinir | Değişmez ya da silinir |

Bu tablodan çıkan üç nokta, dökümanın sonraki bölümlerinin konusudur:

1. Servislerin kalıcı verisi `/var`'da, bootc'un hiç yönetmediği yerde duruyor. Verinin korunması ve güncellemeyle uyumu bootc dışında çözülmelidir.
2. Yapılandırma `/etc`'de duruyor ve makinede değiştirilirse imajdan sapıyor.
3. Secret'lar `/var` ile `/etc` arasında dağınık duruyor ve bootc'un bunlar için bir yöntemi yok.
