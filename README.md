# Librenfra

Librenfra, kurumların IT altyapısını lisanlı ürünlere bağımlı olmadan kurup işletebilmesi için açık kaynaklı bir altyapı oluşturma fikridir. Active Directory ve mail servisleri gibi her kurumun ihtiyaç duyduğu sunucuları IaC prensipleri ile tekrarlanabilir ve kolay entegre edilebilir şekilde tanımlayarak açık kaynak araçların sorunsuz çalışabileceği bir zemin hazırlamayı amaçlamaktadır.

## Fikir
Kurumların kimlik, posta ve dosya altyapısı bugün büyük ölçüde yüksek lisans maliyeti olan ürünlere bağlı. Bu ürünlerin açık kaynak alternatifleri mevcut ancak arkasında yeterli desteğin bulunmamasından dolayı kurumlar bu ürünleri alıp kendi sistemleri kolay bir şekilde entegre edemiyorlar. Eğer bu entegrasyonu daha prüzsüz ve modüler hale getirmeyi başarırsak kurumları lisans maliyetlerinden kurtarabilir, hatta bu çekirdek projeye destek vermelerini sağlayabiliriz.

## Dokümanlar

1. [Fikrin çıkış noktası](docs/01-fikrin-cikis-noktasi.md): projenin açık kaynak bir UBS fikrinden nasıl doğduğu ve neden önce altyapının açık olması gerektiği
2. [Stateless yapı](docs/02-stateless-yapi.md): kurumlara sürümlü bir altyapı sunabilmek için işletim sistemi seviyesinde neden stateless bir yapıya ihtiyaç duyulduğu
3. [Entegrasyon](docs/03-entegrasyon.md): Librenfra altyapısının kurumların farklı ortamlarıyla uyumlu hale getirilmesi: birinci aşamada dikkat edilecekler ve ikinci aşamadaki çok ortam desteği

### Karar kayıtları

- [0001. İşletim sistemi seviyesinde stateless yapı](docs/decisions/0001-stateless-isletim-sistemi.md): bu ihtiyacı karşılayabilecek yaklaşımların karşılaştırması (Durum: Açık)
- [0002. İki aşamalı geliştirme](docs/decisions/0002-iki-asamali-gelistirme.md): entegrasyon fikrinin gelişimi ve önce açık kaynak temel altyapının, sonra çok ortam desteğinin geliştirilmesi kararı (Durum: Kabul edildi)
