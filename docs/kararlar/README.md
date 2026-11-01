# Karar kayıtları

Projede alınan, açık duran ve rafa kaldırılan mimari kararlar burada tutulur. Her kayıt kararın bağlamını, gerekçesini ve sonuçlarını anlatır; karar değişirse eski kayıt silinmez, durumu güncellenir ve yeni kayda bağlantı verilir.

| No | Karar | Durum | Tarih |
| --- | --- | --- | --- |
| [0001](0001-isletim-sistemi-secimi.md) | Server'ların işletim sistemi NixOS'tur | Kabul edildi | 2026-11-01 |
| [0002](0002-active-directory-secimi.md) | Dizin servisi Samba AD'dir | Kabul edildi | 2026-11-01 |

## Durumlar

- **Açık:** Seçenekler belli, karar verilmedi.
- **Kabul edildi:** Karar uygulanır; dokümanlar buna göre yazılır.
- **Rafa kaldırıldı:** Fikir değerlendirildi ama şimdilik uygulanmayacak; yeniden ele alınma koşulu kayıtta yazılıdır.
- **Yerini aldı:** Karar daha yeni bir kayıtla değişti; yeni kayda bağlantı verilir.

## Yeni kayıt şablonu

Dosya adı `NNNN-kisa-baslik.md` biçimindedir.

```markdown
# NNNN. Başlık

- **Durum:** Açık | Kabul edildi | Rafa kaldırıldı | Yerini aldı (NNNN)
- **Tarih:** YYYY-AA-GG

## Bağlam
Hangi sorun, hangi kısıtlar.

## Karar
Ne yapılacak, tek paragraf.

## Gerekçe
Neden bu seçenek.

## Sonuçlar
Kazanılan ve kaybedilen, etkilenen repolar.

## Değerlendirilen alternatifler
Seçenek, neden seçilmedi.
```
