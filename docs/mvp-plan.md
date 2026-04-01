# Dernek Temsilci-Bagisci Takip MVP Plani

## Hedef
9 temsilcinin faaliyetlerini, bagisci iliskilerini ve ziyaretlerini hiyerarsik yetki ile takip eden, mobil-oncelikli bir uygulama cikariyoruz.

## Kapsam Ozeti (MVP)
- Temsilci takibi: gorev, etiket, kategori, durum, oncelik, son tarih, aktivite gecmisi.
- Bagisci takibi: ad-soyad, telefon, konum, temsilci atamasi, bagis durumu.
- Ziyaret takibi: planla, gerceklesti kaydi, not, hediye bilgisi, fotograf.
- Hiyerarsi: Ust yonetici > Bolge sorumlusu > Temsilci.
- Takvim gorunumu: ziyaret ve gorevlerin gun/hafta takibi.
- Harita gorunumu: bagisci/ziyaret lokasyonlarini listeden haritaya gecis.
- Site ici bildirim: yeni atama, yaklasan ziyaret, geciken gorev.

## Teknoloji Karari
- Backend: Go + pgx + sqlc + PostgreSQL
- Frontend: React + shadcn/ui (mobile-first tasarim)
- Mimari: Monorepo (api + web), REST API (MVP icin)

## Faz 0 - Urun Cekirdegi ve Yetki Modeli
Amac: hiyerarsik is kurallarini netlestirmek.
- Roller: admin, bolge_sorumlusu, temsilci.
- Veri sahipligi:
  - Admin tum veriyi gorur.
  - Bolge sorumlusu kendi alt temsilcilerini ve bagiscilarini gorur.
  - Temsilci sadece kendi kayitlarini gorur/duzenler.
- Basari olcutu: rol bazli erisim matrisi yazili hale gelir.

## Faz 1 - Veri Modeli ve Altyapi
Amac: temel tablolar ve migration altyapisi.
- PostgreSQL semasi:
  - users, roles, representative_hierarchy
  - tasks, task_tags, task_categories
  - donors, donor_assignments
  - visits, visit_notes, visit_media
  - notifications
- sqlc query paketleri: users, tasks, donors, visits, notifications.
- Basari olcutu: local ortamda migration + temel CRUD queryleri calisir.

## Faz 2 - Temsilci Takibi Modulu
Amac: gorev bazli faaliyet takibi.
- Gorev alanlari: baslik, aciklama, kategori, etiketler, durum, oncelik, son_tarih, atanan_temsilci.
- Ekranlar (mobile-first):
  - Gorev listesi (filtre: durum/kategori/etiket)
  - Gorev detay + aktivite gecmisi
  - Gorev olustur/duzenle
- Basari olcutu: temsilci kendi gorevini yonetir, yonetici gorev atar.

## Faz 3 - Bagisci ve Ziyaret Modulu
Amac: temsilci-bagisci iliskisini takip etmek.
- Bagisci alanlari: ad, soyad, telefon, adres, lokasyon(lat/lng), not, temsilci_id.
- Ziyaret akis:
  - Planlandi (tarih/saat)
  - Gerceklesti (durum + not + hediye)
  - Medya ekle (fotograf)
- Ekranlar:
  - Bagisci listesi/detay
  - Ziyaret planlama formu
  - Ziyaret gecmisi
- Basari olcutu: her temsilciye bagli bagiscilar ve ziyaret kayitlari gorunur.

## Faz 4 - Takvim, Harita, Bildirim
Amac: operasyonel gorunurluk.
- Takvim: haftalik/aylik ziyaret ve gorev gorunumu.
- Harita: bagiscilarin pin olarak gosterimi, detaya gecis.
- Bildirim tipleri:
  - Yeni gorev atamasi
  - 24 saat icinde ziyaret hatirlatma
  - Geciken gorev uyarisi
- Basari olcutu: kullanici kritik aksiyonlari tek ekrandan gorebilir.

## Faz 5 - MVP Sertlestirme ve Yayin Hazirligi
Amac: canliya alinabilir minimum kalite.
- Loglama, hata yonetimi, temel audit alanlari (created_by, updated_by).
- Basit dashboard metrikleri:
  - Temsilci basina acik gorev
  - Haftalik planlanan/gerceklesen ziyaret
  - Aktif bagisci sayisi
- Test:
  - Backend: yetki + temel is akisi entegrasyon testleri
  - Frontend: kritik ekran smoke testleri
- Basari olcutu: pilot ekip (9 temsilci) ile 1 haftalik testten gecmesi.


