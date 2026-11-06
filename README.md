# Kese

Harcamanı tek satırda yaz, paranın nereye gittiğini gör. Kişisel bütçe takibi için Android uygulaması. Veriler yalnızca telefonda durur: hesap yok, sunucu yok, uygulamanın internet izni de yok.

## Canlı kese

Ana ekrandaki kese paranla birlikte yaşar. Sıvı seviyesi bu ayki gelirinin kalan payıdır; yarısının altına inince kehribara, sonra kırmızıya döner. Harcayınca para keseden uçar, gelir girince içine düşer. Keseye dokununca sallanır.

Sürekli hareket yalnızca ekran görünürken çalışır ve Android'in **Animasyonları kaldır** ayarına uyar.

## Hızlı ekleme

```
market 340 tl
dün kira 12.500 #ev
maaş +45.000
netflix 229,99
telefon 30.000 6 taksit
ali 500 #alacak
```

- **Tutar:** `12.500` on iki bin beş yüz, `12,5` on iki buçuk lira. `1,250` gibi belirsiz yazımlar kabul edilmez.
- **Gün:** `bugün`, `dün`, `evvelsi gün`, hafta günleri. Hafta günü en son geçen günü gösterir.
- **Gelir:** `+` ile başlayan tutar veya `maaş`, `prim`, `iade` gibi kelimeler.
- **Taksit:** `6 taksit` veya `6taksit`, 2 ile 36 arası. Yazdığın tutar toplam fiyattır. `araba taksiti 8.000` gibi sayısız yazım tek ödeme olarak kalır.
- **Borç:** `#borç` sana verilen, `#alacak` senin verdiğin para.
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
| Borç | Günü 7 gün içinde olan veya geçen borç ve alacaklar |

Kabul ettiğin öneri türleri öne çıkar, kapattıkların geriye düşer.

## Taksitler

Bir taksitli alışveriş, her ay için ayrı bir işlem olarak kaydedilir. İlk taksit alışveriş gününe, sonrakiler izleyen ayların aynı gününe düşer; kısa aylarda ayın son günü kullanılır. Kuruş artarsa ilk taksitlere eklenir, toplam hep tutar.

Her taksit kendi ayının gideri sayılır, yani **Bu ay kalan**, limitler ve analiz onu gerçek haliyle gösterir. Ay sonu tahmini bu ayın kalan taksitlerini ekler. Abonelik, artış ve olağandışı harcama önerileri taksitleri saymaz, çünkü bunlar yeni bir alışkanlık değil, verilmiş bir karardır.

**Bu ay** ekranında aktif planlar ve gelecek ayın toplamı görünür. Plana dokununca kalan taksitleri silebilirsin, örneğin ürünü iade ettiysen; geçmiş taksitler kayıtta kalır. Gelecek ayların taksitleri **İşlemler** ekranından görülür.

## Borç ve alacak

Bu ay ekranının altındadır. Borçlar bütçenin dışında durur: birinden aldığın para gelir, geri ödediğin para gider sayılmaz, **Bu ay kalan** tutarını değiştirmez. Ödeme günü isteğe bağlıdır; verirsen gün yaklaşınca öneri çıkar. Faizli kredi gibi bütçeden çıkan ödemeleri ayrıca gider olarak yaz.

## Birikim hedefleri

Bu ay ekranından hedef koyup para ekleyebilirsin. Tahmini ulaşma tarihi, biten son 3 ayın gelir ve gider farkından hesaplanır. Hedefe koyduğun para işlem sayılmaz, "Bu ay kalan" tutarını değiştirmez.

## Bildirimler

**Ayarlar → Bildirimler** altından ayrı ayrı açılır, hepsi telefonda çalışır. Metinlerde tutar yer almaz, çünkü kilit ekranında görünebilirler.

- **Yaklaşan ödemeler:** Düzenli ödeme, taksit ve günü olan borçlar için bir gün önce sabah. Taksit ve borçların en yakın sekizi planlanır, uygulamayı açtıkça yenilenir.
- **Limit uyarıları:** Limitin %80 ve %100'ünde, ayda birer kez.
- **Akşam hatırlatması:** O gün işlem girmediysen akşam 9 gibi. Plan 7 gün ileriye yapılır, uygulamayı açtıkça yenilenir.

Android pil tasarrufu için hatırlatmaları bir saate kadar geciktirebilir.

## Ana ekran widget'ı

Telefonun widget listesinden **Kese**'yi ekle. Bu ayki kalan parayı gösterir, + düğmesi hızlı eklemeyi açar. Renkleri seçili temayı izler. Tutar yalnızca uygulamayı kullandıkça güncellenir.

## Uygulama kilidi

**Ayarlar → Güvenlik** altından açılır. Parmak izi, yüz veya ekran kilidi ister; 30 saniyeden uzun arka planda kalınca tekrar kilitlenir. Kilit açıkken widget tutarı gizler. Telefonun ekran kilidini kaldırırsan verilerine erişimin kesilmesin diye kilit kendiliğinden devre dışı kalır. Kilit ayarı yedekle taşınmaz.

## Özel tema

**Ayarlar → Tema → Özel** ile vurgu ve arka plan rengini seçersin, gerisi bunlardan türetilir. Yazı renkleri her renkte okunaklı kalacak şekilde hesaplanır; vurgu arka planda kayboluyorsa uyarı çıkar.

## Yazı tipi

Manrope, SIL Open Font License ile `assets/fonts/` içindedir. Boyutu düşürmek için Türkçe ve Latin karakterlere indirilmiş sabit ağırlıklar kullanılır.

## Geliştirme

Flutter 3.47 ve Android SDK gerekir.

```bash
flutter test                # testler
flutter run                 # bağlı telefon veya emülatörde çalıştır
flutter build apk --release # build/app/outputs/flutter-apk/app-release.apk
```

## İmzalama

Release derlemesi `android/key.properties` dosyasındaki anahtarla imzalanır. Dosya ve anahtar repoya girmez. Dosya yoksa APK imzasız çıkar ve telefona kurulmaz; bu bilinçlidir, çünkü başka bir anahtarla imzalanan sürüm eskisinin üstüne kurulamaz.

```properties
storeFile=C:/yol/kese-release.jks
storePassword=...
keyAlias=kese
keyPassword=...
```

Anahtar kaybolursa uygulama güncellenemez, kullanıcıların silip yeniden kurması gerekir. Bu yüzden anahtarı ve şifresini bilgisayar dışında da yedekle. Yeni sürüm yayınlarken `pubspec.yaml` içindeki `version` değerinin `+` sonrasını artır.

## Yedekleme

Android'in otomatik bulut yedeği kapalıdır. Uygulamayı silersen veriler de silinir, bu yüzden **Ayarlar → Yedeği dışa aktar** ile ara sıra yedek al.
