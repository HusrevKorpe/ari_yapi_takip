// SALT-OKUNUR: islem_kayitlari (audit log) içinde Osman'ın yoklama kayıtlarının
// ORİJİNAL payload'ında santiyeId olup olmadığını arar. Sync kurtarmadan önceki
// hali burada iz bırakmış olabilir.
const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();
const ID = '2dc75cbe-0fc5-4579-a24d-b8124b600d3f';
const d = (x) => String(x || '').slice(0, 10);

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  // Osman'ın yoklama doc id'leri
  const y = await org.collection('yoklama').where('calisanId', '==', ID).get();
  const ids = new Set();
  y.forEach((x) => ids.add(x.id));
  console.log(`Osman yoklama doc sayısı: ${ids.size}`);

  const audit = await org.collection('islem_kayitlari').get();
  console.log(`islem_kayitlari toplam: ${audit.size}\n`);
  let hit = 0, siteli = 0;
  audit.forEach((docu) => {
    const r = docu.data();
    const blob = JSON.stringify(r);
    // Osman'a veya onun yoklama id'lerine değen kayıtlar
    const touchesOsman = blob.includes(ID) || [...ids].some((i) => blob.includes(i));
    if (!touchesOsman) return;
    // Yoklama ile ilgili mi?
    const isYoklama = /yoklama|attendance/i.test(blob) || blob.includes('"tarih"') || blob.includes('durum');
    if (!isYoklama) return;
    hit++;
    // Payload'da santiye alanı var mı ve dolu mu?
    const m = blob.match(/"(santiyeId|ikinciSantiyeId|siteId)"\s*:\s*"([^"]+)"/g);
    if (m) {
      siteli++;
      console.log(`[AUDIT ${docu.id}] tarih=${d(r.tarih || r.islemTarihi || r.zaman)} → SİTE İZİ: ${m.join(', ')}`);
      console.log(`   ${blob.slice(0, 260)}\n`);
    }
  });
  console.log(`\nOsman-yoklama ile ilgili audit kaydı: ${hit}, içinde DOLU site alanı olan: ${siteli}`);
  if (hit === 0) console.log('(islem_kayitlari bu org için yoklama izi tutmuyor olabilir.)');
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message); process.exit(1); });
