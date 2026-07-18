// yusuf azerbaycan'a tarih-bazlı yevmiye segmenti girer:
//   1.800 (başlangıçtan beri)  →  2.000 (27.06.2026'dan itibaren)
//
// Bu, uygulamanın "Zam yap" akışının (WageHistory.withChange) ürettiği
// ucretGecmisi ile BİREBİR aynı JSON'u yazar. Fix'li app (v15, commit 75ddf7b)
// bunu pull edince yusuf'un 27 Haziran ÖNCESİ günlerini 1.800'den, sonrasını
// 2.000'den fiyatlar → hayali ~5.400 kaybolur, gerçek bakiye ~13.000 olur.
//
// SOFT-WRITE: sadece ucretGecmisi + guncellenmeTarihi + sonDegistiren +
// senkronSurumu+1 yazılır. gunlukUcret (2.000) DEĞİŞMEZ. Hiçbir şey silinmez.
//
// KURU ÇALIŞMA varsayılan. Gerçekten yazmak için:  node scripts/yusuf_zam_segmenti.js --yaz

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const YAZ = process.argv.includes('--yaz');
const FORCE = process.argv.includes('--force'); // mevcut ucretGecmisi'nin üstüne yaz
const ACTOR = 'admin-script-zam-duzeltme';
const norm = (s) => String(s || '').toLocaleLowerCase('tr-TR').replace(/\s+/g, ' ').trim();
const nowIso = () => new Date().toISOString();

// Uygulamanın withChange(effectiveFrom=27.06.2026, newWage=2000, previousWage=1800)
// + encode() çıktısının aynısı. Tarihler LOKAL (Z yok), app'in toIso8601String'i gibi.
// 27 Haz günü çalışıldı ve 1.800'den ödendi (o gün ödeme dönemindeydi) → zam
// öncesi sayılır. Bu yüzden 2.000 efektif 28 Haziran: ≤27 Haz = 1.800, ≥28 Haz = 2.000.
const SEGMENT = [
  { from: '2000-01-01T00:00:00.000', wage: 1800 }, // taban: 28 Haz öncesi TÜM günler 1.800
  { from: '2026-06-28T00:00:00.000', wage: 2000 }, // zam: 28 Haziran 2026'dan itibaren 2.000
];
const SEGMENT_JSON = JSON.stringify(SEGMENT);

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  const wSnap = await org.collection('calisanlar').get();
  const matches = [];
  wSnap.forEach((doc) => {
    const r = doc.data();
    if (r.silinmeTarihi) return;
    if (norm(r.adSoyad).includes('yusuf azer')) matches.push({ ref: doc.ref, id: doc.id, ...r });
  });

  if (matches.length !== 1) {
    console.log(`⚠ Tam 1 yusuf beklenirken ${matches.length} kayıt bulundu. İptal.`);
    matches.forEach((m) => console.log(`  ${m.id.slice(0, 8)}  ${m.adSoyad}  aktif=${m.aktifMi !== false}`));
    process.exit(1);
  }
  const y = matches[0];

  console.log('=== HEDEF ÇALIŞAN ===');
  console.log(`  ${y.adSoyad}  (${y.id})`);
  console.log(`  gunlukUcret (DEĞİŞMEYECEK): ${y.gunlukUcret}`);
  console.log(`  mevcut ucretGecmisi        : ${y.ucretGecmisi === undefined ? '(yok)' : JSON.stringify(y.ucretGecmisi)}`);
  console.log(`  senkronSurumu              : ${y.senkronSurumu}`);

  // güvenlik kontrolleri
  if (Number(y.gunlukUcret) !== 2000) {
    console.log(`\n⚠ Güncel yevmiye 2.000 değil (${y.gunlukUcret}). Beklenmeyen durum, İPTAL.`);
    process.exit(1);
  }
  if (y.ucretGecmisi && !FORCE) {
    console.log('\n⚠ ucretGecmisi ZATEN DOLU. Üzerine yazmak için --force ekle. İPTAL.');
    console.log('  mevcut:', JSON.stringify(y.ucretGecmisi));
    process.exit(1);
  }
  if (y.ucretGecmisi && FORCE) {
    console.log('\n[--force] Mevcut ucretGecmisi üzerine yazılacak. Eski değer:', JSON.stringify(y.ucretGecmisi));
  }

  console.log('\n=== YAZILACAK ===');
  console.log(`  ucretGecmisi = ${SEGMENT_JSON}`);
  console.log('  + guncellenmeTarihi=now, sonDegistiren=' + ACTOR + ', senkronSurumu=' + ((Number(y.senkronSurumu) || 0) + 1));

  if (!YAZ) {
    console.log('\n[KURU ÇALIŞMA] Hiçbir şey yazılmadı. Gerçekten yazmak için:  node scripts/yusuf_zam_segmenti.js --yaz');
    process.exit(0);
  }

  await y.ref.update({
    ucretGecmisi: SEGMENT_JSON,
    guncellenmeTarihi: nowIso(),
    sonDegistiren: ACTOR,
    senkronSurumu: (Number(y.senkronSurumu) || 0) + 1,
  });
  console.log('\n✅ YAZILDI. ucretGecmisi segmenti eklendi, senkronSurumu bump edildi.');
  console.log('   Etki: yalnızca v15 (fix) APK telefonda olunca görünür. Eski app bu alanı yok sayar.');
  console.log('   UYARI: v15 kurulmadan yusuf\'u ESKİ app\'ten düzenlersen bu alan silinir (eski app geri yazar).');
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message); process.exit(1); });
