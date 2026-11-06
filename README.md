# Kese

Harcamanı tek satırda yaz, paranın nereye gittiğini gör. Kişisel bütçe takibi için Android uygulaması. Veriler yalnızca telefonda durur: hesap yok, sunucu yok, uygulamanın internet izni de yok.

## Hızlı ekleme

```
market 340 tl
dün kira 12.500 #ev
maaş +45.000
netflix 229,99
```

- **Tutar:** `12.500` on iki bin beş yüz, `12,5` on iki buçuk lira. `1,250` gibi belirsiz yazımlar kabul edilmez.
- **Gün:** `bugün`, `dün`, `evvelsi gün`, hafta günleri. Hafta günü en son geçen günü gösterir.
- **Gelir:** `+` ile başlayan tutar veya `maaş`, `prim`, `iade` gibi kelimeler.
- **Kategori:** `#market`, `#yemek`, `#ulaşım`, `#fatura`, `#ev`, `#eğlence`, `#sağlık`, `#abonelik`, `#diğer`. Etiket yoksa önce kendi geçmişine, sonra anahtar kelimelere bakılır.

## Öneriler

Öneriler `lib/core/insights.dart` içindeki kurallarla yalnızca senin verilerinden hesaplanır ve gerekçesini kendi rakamlarınla gösterir.

| Öneri | Dayanağı |
|---|---|
| Abonelik | Aynı başlık, benzer tutar, en az 3 ay üst üste, ayın benzer günü |
| Ay sonu | Beklenen harcama, beklenen gelirini aşıyorsa uyarı |
| Artış | Ayın ilk günlerindeki harcama ile önceki 3 ayın aynı dönemi |
| Limit | Kategori limitinin %80'i ve %100'ü |
| Olağandışı | Kategori medyanının 3 katından büyük harcama |
| Yaklaşan | 7 gün içinde beklenen düzenli ödemeler; **Ödedim** ile tek dokunuşta kaydedilir |

Kabul ettiğin öneri türleri öne çıkar, kapattıkların geriye düşer.

## Birikim hedefleri

Bu ay ekranından hedef koyup para ekleyebilirsin. Tahmini ulaşma tarihi, biten son 3 ayın gelir ve gider farkından hesaplanır. Hedefe koyduğun para işlem sayılmaz, "Bu ay kalan" tutarını değiştirmez.

## Bildirimler

**Ayarlar → Bildirimler** altından ayrı ayrı açılır, hepsi telefonda çalışır. Metinlerde tutar yer almaz, çünkü kilit ekranında görünebilirler.

- **Yaklaşan ödemeler:** Ödemeden bir gün önce sabah.
- **Limit uyarıları:** Limitin %80 ve %100'ünde, ayda birer kez.
- **Akşam hatırlatması:** O gün işlem girmediysen akşam 9 gibi. Plan 7 gün ileriye yapılır, uygulamayı açtıkça yenilenir.

Android pil tasarrufu için hatırlatmaları bir saate kadar geciktirebilir.

## Ana ekran widget'ı

Telefonun widget listesinden **Kese**'yi ekle. Bu ayki kalan parayı gösterir, + düğmesi hızlı eklemeyi açar. Renkleri seçili temayı izler. Tutar yalnızca uygulamayı kullandıkça güncellenir.

## Uygulama kilidi

**Ayarlar → Güvenlik** altından açılır. Parmak izi, yüz veya ekran kilidi ister; 30 saniyeden uzun arka planda kalınca tekrar kilitlenir. Kilit açıkken widget tutarı gizler. Telefonun ekran kilidini kaldırırsan verilerine erişimin kesilmesin diye kilit kendiliğinden devre dışı kalır. Kilit ayarı yedekle taşınmaz.

## Özel tema

**Ayarlar → Tema → Özel** ile vurgu ve arka plan rengini seçersin, gerisi bunlardan türetilir. Yazı renkleri her renkte okunaklı kalacak şekilde hesaplanır; vurgu arka planda kayboluyorsa uyarı çıkar.

## Geliştirme

Flutter 3.47 ve Android SDK gerekir.

```bash
flutter test                # testler
flutter run                 # bağlı telefon veya emülatörde çalıştır
flutter build apk --release # build/app/outputs/flutter-apk/app-release.apk
```

## Yedekleme

Android'in otomatik bulut yedeği kapalıdır. Uygulamayı silersen veriler de silinir, bu yüzden **Ayarlar → Yedeği dışa aktar** ile ara sıra yedek al.
