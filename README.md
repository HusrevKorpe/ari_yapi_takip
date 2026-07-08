# Ari Yapi Takip

Ari Yapi Takip, yoneticiler icin gelistirilmis local-first bir isci, yoklama, maas ve gider takip uygulamasidir.

## v1 Ozellikler

- Isci yonetimi (kart, gunluk yevmiye, aktif/pasif)
- Gunluk yoklama (`Calisti`, `Yarim Gun`, `Gelmedi`, `Izinli`)
- `Calisti` ve `Yarim Gun` durumunda santiye secimi zorunlu
- Gider kaydi ve aylik gider listesi
- Avans/Borc kaydi
- Maas hesabi: `(calisma gun esdegeri x gunluk ucret) - (avans + borc)`
- Aylik rapor ekrani
- Offline-first veri yazimi + sync queue

## Teknik Yapi

- Flutter + Riverpod
- Local DB: Drift (SQLite)
- Sync katmani: Queue tabanli remote upsert
- Remote adapter: Firebase Firestore (opsiyonel)

## Baslatma

```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter run
```

## Test

```bash
flutter test
```

## Yerel Firebase Emulator (test)

Production projesine (`ari-yapi-takip`) dokunmadan test etmek icin yerel
Firebase Emulator Suite kullanilir. Emulator verisi cikista `emulator-data/`
klasorune kaydedilir, bir sonraki acilista geri yuklenir (klasor git'e dahil
degildir).

```bash
# 1) Emulator'i baslat (bu terminali ACIK birak)
./scripts/emulator.sh

# 2) Ayri bir terminalde uygulamayi emulator'a baglayarak calistir ve GIRIS YAP
flutter run --dart-define=USE_EMULATOR=true

# 3) Giris yaptiktan sonra users/{uid} uyelik kaydini olustur
#    (firestore.rules, organizationId'yi client'in yazmasini engeller; bu yuzden
#     emulator'da elle/otomatik seed gerekir)
./scripts/seed.sh

# 4) Isin bitince emulator terminalinde Ctrl+C  -> veri emulator-data/'ya yazilir
```

Onemli: Kalicilik yalnizca emulator `./scripts/emulator.sh` ile baslatilip
**Ctrl+C ile duzgun** kapatildiginda calisir. Zorla kapatilirsa (hard kill)
export olmaz ve `users/{uid}` kaydi kaybolur; bu durumda sync `permission-denied`
verir. Calisirken anlik kayit almak icin: `firebase emulators:export ./emulator-data`.

## Notlar

- Firebase konfiguru degilse uygulama local-first modda calismaya devam eder.
- Giris ekrani yoktur; uygulama dogrudan ana panele acilir.
