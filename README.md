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

## Notlar

- Firebase konfiguru degilse uygulama local-first modda calismaya devam eder.
- Giris ekrani yoktur; uygulama dogrudan ana panele acilir.
