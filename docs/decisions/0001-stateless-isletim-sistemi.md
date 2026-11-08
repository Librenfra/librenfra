# 0001. İşletim sistemi seviyesinde stateless yapı

- **Durum:** Açık
- **Tarih:** 2026-11-08

## Bağlam

Bu kayıt [Stateless yapı](../02-stateless-yapi.md) dökümandaki ihtiyacı karşılayabilecek yaklaşımları değerlendirir.

## Değerlendirme ölçütleri

Her seçenek aynı dört soruyla değerlendirildi:

- **Versiyon:** Sunucunun işletim sistemi katmanı belirli bir sürüm numarasıyla tanımlanabiliyor mu ve kurulumdan sonra bu sürümden sapmadan (değişikliğe uğramadan) aynı kalabiliyor mu?
- **Güncelleme ve geri dönüş:** Versiyon güncellemesi yapmak kolay mı? Bir sorun çıktığında sistem hızlı ve güvenli bir şekilde önceki sürüme geri döndürülebiliyor mu?
- **Dağıtım:** Hazırlanan sürüm kurumlara kolayca ulaştırılabiliyor mu? Kurumlar bu temel sürümü bozmadan üzerine kendi yapılandırmalarını ekleyebiliyor mu?
- **Erişilebilirlik:** Kurumların BT ekipleri ve projeye katkı sağlayacak geliştiriciler bu yaklaşımı kolay kullanabilecekler mi?


## Seçenekler

### 1. bootc

**Nasıl çalışır:** İşletim sistemi bir OCI container imajı olarak `Containerfile` ile tanımlanır, build edilir ve registry'de yayınlanır. Sunucu bu imajdan kurulur, `bootc upgrade` ile yeni imaja geçer, `bootc rollback` ile öncekine döner. `/usr` salt okunurdur, `/etc` makineye özel ayar, `/var` kalıcı veri içindir.

| Ölçüt | Değerlendirme |
| --- | --- |
| Versiyon | Güçlü. Sistem kısmı imajdan gelir ve salt okunurdur; çalışan sürüm imajın sürümü ve digest'iyle kesin olarak söylenebilir |
| Güncelleme ve geri dönüş | Güçlü. Güncelleme atomiktir, önceki imaj diskte kalır ve tek komutla dönülür. Her güncelleme yeniden başlatma gerektirir |
| Dağıtım | Güçlü. İmajlar herhangi bir OCI registry'de durur, imzalanabilir, kurumun registry'sine kopyalanabilir. Kurum `FROM` ile kendi imajını türetebilir |
| Erişilebilirlik | Güçlü. `Containerfile` ve container araçları yaygın olarak bilinir; build sırasında `dnf` gibi normal paket yöneticisi kullanılır |

- **Artıları:** Uygulama container'larındaki modeli işletim sistemine taşır; tam bir işletim sistemi olduğu için AD ve mail gibi servisler container'a zorlanmadan kurulabilir. Red Hat (RHEL image mode), Fedora, CentOS Stream ve AlmaLinux bootc imajları yayınlıyor; proje CNCF bünyesinde gelişiyor.
- **Eksileri:** Her güncellemede yeniden başlatma; `/etc` yazılabilir kaldığı için sapma olasılığı; build ve yayın zinciri (CI, registry) ihtiyacı; görece yeni bir teknoloji olması; paket bulunurluğunun seçilen taban dağıtıma bağlı olması.

### 2. NixOS (ve Guix)

**Nasıl çalışır:** Sistemin tamamı (paketler, ayarlar, servisler) tek bir bildirimsel tanımdan üretilir. Sunucu yeni tanıma `nixos-rebuild switch` ile geçer, önceki versiyona dönülebilir.

| Ölçüt | Değerlendirme |
| --- | --- |
| Versiyon | Güçlü. Aynı tanım ve kilit dosyası her zaman aynı sistemi üretir |
| Güncelleme ve geri dönüş | Güçlü. Güncelleme bütün olarak yapılır, çoğu değişiklik yeniden başlatma istemez, önceki versiyona dönülebilir |
| Dağıtım | Orta. Tanımlar git ile paylaşılabilir, ikili önbellekler kurulabilir; ama kurumlara hazır bir "sürüm" ulaştırmanın ve türetmenin yolu container imajları kadar yaygın değildir |
| Erişilebilirlik | Zayıf. Nix kendine özgü bir dil ve düşünce biçimi gerektirir; hata ayıklamak zordur, kurumların IT ekiplerinin çoğu bilmez |

- **Artıları:** Bu ihtiyacı teknik olarak en kapsamlı karşılayan yaklaşımlardan biri; paket deposu çok geniş.
- **Eksileri:** Giriş eşiği yüksek; kurumsal yazılımların ve ticari desteğin çoğunun hedeflediği RHEL ve Debian ailelerinin dışında; kısa sürüm destek takvimi.

### 3. Değişmez container işletim sistemleri (Fedora CoreOS, Flatcar, Talos)

**Nasıl çalışır:** Salt okunur, atomik güncellenen ve yalnızca container çalıştırmak için tasarlanmış minimal işletim sistemleri. Servisler container olarak çalışır; Talos yalnızca Kubernetes çalıştırır.

| Ölçüt | Değerlendirme |
| --- | --- |
| Versiyon | Güçlü. İşletim sistemi sürümü sabit ve değişmezdir |
| Güncelleme ve geri dönüş | Güçlü. Atomik güncelleme ve geri dönüş |
| Dağıtım | Orta. İşletim sistemi upstream'den gelir, servisler container imajı olarak dağıtılabilir; ama işletim sisteminin kendisini kuruma göre türetmek doğal bir yol değildir |
| Erişilebilirlik | Orta. Container bilgisi yeterlidir, ama tüm servisleri container'a sığdırmak ayrı bir uzmanlık ister |

- **Artıları:** Stateless ihtiyacına çok yakın; olgun ve üretimde yaygın kullanılan sistemler.
- **Eksileri:** İşletim sistemi özelleştirmeye kapalıdır; Active Directory gibi ağa, saate ve dosya sistemi özniteliklerine sıkı bağlı servisleri bu sistemlerde çalıştırmak zorlaşır.

### 4. mkosi ve systemd-sysupdate

**Nasıl çalışır:** systemd projesinin araçlarıyla disk imajları üretilir; sunucu A/B bölümleri arasında geçerek yeni imaja güncellenir.

| Ölçüt | Değerlendirme |
| --- | --- |
| Versiyon | Güçlü. Sistem bölümü imajın kendisidir |
| Güncelleme ve geri dönüş | Güçlü. A/B bölüm modeliyle atomik güncelleme ve geri dönüş |
| Dağıtım | Zayıf. İmajların yayınlanması ve güncelleme sunucusu büyük ölçüde projenin kendisine kalır; kurumun türetmesi için hazır bir model yok |
| Erişilebilirlik | Orta. Araçlar sadedir ama topluluk, örnekler ve belgeler henüz sınırlıdır |

- **Artıları:** Modern, sade, systemd ile sıkı uyumlu; dağıtımdan bağımsız.
- **Eksileri:** Küçük topluluk; dağıtım altyapısını kendimiz kurmamız gerekir; kurumsal kullanım örnekleri az.

### 5. Yapılandırma yönetimi araçları (Ansible, Puppet, Salt, Chef)

**Nasıl çalışır:** Sunucunun nasıl olması gerektiği bir tanımda tutulur ve bu tanım çalışan sunucuya uygulanır.

| Ölçüt | Değerlendirme |
| --- | --- |
| Versiyon | Zayıf. Sunucu stateful kalır; tanımdan silinen bir paket veya elle yapılan değişiklik sunucuda kalmaya devam eder |
| Güncelleme ve geri dönüş | Zayıf. Güncelleme adım adım uygulanır ve yarıda kalabilir; eski tanımı tekrar uygulamak sunucuyu her zaman eski haline getirmez |
| Dağıtım | Orta. Roller ve playbook'lar kolayca paylaşılır; ama her kurumda farklı bir başlangıç durumuna uygulanır |
| Erişilebilirlik | Güçlü. Kurumlarda en yaygın yaklaşım; öğrenmesi görece kolay |

- **Artıları:** Bilinen, olgun, geniş topluluk; mevcut sunuculara uygulanabilir.
- **Eksileri:** İşletim sistemini stateless yapmaz; "sunucu şu sürümde" demek kesin değildir.

### 6. Altın imajlar (Packer ve benzerleri)

**Nasıl çalışır:** Sunucunun diski önceden hazırlanıp şablon olarak saklanır, yeni sunucular bu şablondan kurulur.

| Ölçüt | Değerlendirme |
| --- | --- |
| Versiyon | Orta. Kurulum anı sürümlüdür, ama sonrası değildir |
| Güncelleme ve geri dönüş | Zayıf. Güncellemeler başka bir yöntemle yapılır ya da sunucu yeni şablondan baştan kurulur; geri dönüş eski şablondan yeniden kurmaktır |
| Dağıtım | Orta. Disk imajları dağıtılabilir, ama hipervizöre özgü biçimlerdedir ve türetmek zordur |
| Erişilebilirlik | Orta. Araçlar bilinir, ama kurulum sonrası için ikinci bir araç gerekir |

- **Artıları:** Kurulum anını tekrarlanabilir kılar; olgun araçlar.
- **Eksileri:** Yalnızca ilk kurulumu çözer; sunucu zamanla şablondan uzaklaşır.

### 7. Her şeyi Kubernetes üzerinde çalıştırmak

**Nasıl çalışır:** Tüm servisler container olarak bir Kubernetes kümesinde çalışır.

| Ölçüt | Değerlendirme |
| --- | --- |
| Versiyon | Orta. Servisler sürümlüdür, ama düğümlerin işletim sistemi yine ayrı yönetilmesi gereken bir katmandır |
| Güncelleme ve geri dönüş | Orta. Servisler için güçlü; düğümler için sorun bir alt katmana taşınır |
| Dağıtım | Orta. Helm, operatörler gibi olgun dağıtım araçları var; ama kurumun önce bir küme işletmesi gerekir |
| Erişilebilirlik | Zayıf. Küçük ve orta ölçekli kurumlar için bir Kubernetes kümesini işletmek başlı başına bir yüktür |

- **Artıları:** Uygulama katmanında stateless modelin tamamen kullanılması; geniş ekosistem.
- **Eksileri:** İşletim sistemi sorununu çözmez; domain controller ve mail sunucusu gibi servisler bu ortamda doğal çalışmaz.

## Özet

| Sıra | Seçenek | Versiyon | Güncelleme ve geri dönüş | Dağıtım | Erişilebilirlik |
| --- | --- | --- | --- | --- | --- |
| 1 | bootc | Güçlü | Güçlü | Güçlü | Güçlü |
| 2 | NixOS / Guix | Güçlü | Güçlü | Orta | Zayıf |
| 3 | Değişmez container işletim sistemleri | Güçlü | Güçlü | Orta | Orta |
| 4 | mkosi + systemd-sysupdate | Güçlü | Güçlü | Zayıf | Orta |
| 5 | Yapılandırma yönetimi araçları | Zayıf | Zayıf | Orta | Güçlü |
| 6 | Altın imajlar | Orta | Zayıf | Orta | Orta |
| 7 | Kubernetes | Orta | Orta | Orta | Zayıf |

## Karar

Henüz verilmedi.

