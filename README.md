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
| Yaklaşan | 7 gün içinde beklenen düzenli ödemeler |

Kabul ettiğin öneri türleri öne çıkar, kapattıkların geriye düşer.

## Geliştirme

Flutter 3.47 ve Android SDK gerekir.

```bash
flutter test                # testler
flutter run                 # bağlı telefon veya emülatörde çalıştır
flutter build apk --release # build/app/outputs/flutter-apk/app-release.apk
```

## Yedekleme

Android'in otomatik bulut yedeği kapalıdır. Uygulamayı silersen veriler de silinir, bu yüzden **Ayarlar → Yedeği dışa aktar** ile ara sıra yedek al.
