# Stateless Yapı

Kurumlara bir altyapı sunabilmek için, sunduğumuz şeyin bir versiyonu olması gerekiyor: "Kurum X, Librenfra'nın mail modülünün x.x.x sürümünü çalıştırıyor" diyebilmeliyiz ve bu cümle her kurumda aynı anlama gelmeli. Bu yüzden proje işletim sistemi seviyesinde stateless bir yapıya ihtiyaç duymaktadır. Bu ihtiyaç uygulama seviyesinde genellikle containerlar aracılığı ile sağlanır. Container imajı her yerde aynı çalışır, yeni sürüm yeni bir imajdır. Uygulamanın verisi imajın dışında, ayrı bir yerde durur. Container silinip yeniden oluşturulsa bile hiçbir şey kaybolmaz, çünkü container'ın kendisi genellikle bir state taşımaz.

Ama bu uygulamaların altında çalışan işletim sistemi hâlâ eski usulle yönetilir:

- Sunucu bir kez kurulur, sonra üzerine paket eklenir, ayar dosyaları elle düzenlenir, yamalar zaman içinde uygulanır.
- Her müdahale sunucunun üzerinde bir iz bırakır ve bu izlerin kaydı çoğu zaman yoktur.
- Zamanla aynı amaçla kurulmuş iki sunucu bile birbirinden farklılaşabilir.

Active Directory, mail sunucusu veya dosya sunucusu gibi servisler tam da bu katmanda yaşıyor. Librenfra'nın dağıtmak istediği şey de bu katmandır.


#
İşletim sistemi seviyesinde bu ihtiyacı karşılayabilecek yaklaşımlar ve karşılaştırmaları [0001-stateless-isletim-sistemi](decisions/0001-stateless-isletim-sistemi.md) karar kaydında tartışılmıştır.
