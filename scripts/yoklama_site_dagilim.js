// SALT-OKUNUR: Tüm yoklama kayıtlarında siteId doluluğu ve toplu re-sync izi.
const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();
const d = (x) => String(x || '').slice(0, 10);

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  const y = await org.collection('yoklama').get();
  let total = 0, siteli = 0, ikinciSiteli = 0, silinmis = 0;
  const bySyncDay = {}, bySonDeg = {}, byVer = {};
  const siteliAylar = {};
  y.forEach((doc) => {
    const r = doc.data();
    total++;
    if (r.silinmeTarihi) { silinmis++; return; }
    if (r.siteId) { siteli++; const ay = d(r.tarih).slice(0, 7); siteliAylar[ay] = (siteliAylar[ay] || 0) + 1; }
    if (r.ikinciSantiyeId) ikinciSiteli++;
    const sd = d(r._syncedAt) || '—'; bySyncDay[sd] = (bySyncDay[sd] || 0) + 1;
    const who = String(r.sonDegistiren || '—').slice(0, 12); bySonDeg[who] = (bySonDeg[who] || 0) + 1;
    byVer[r.senkronSurumu] = (byVer[r.senkronSurumu] || 0) + 1;
  });
  console.log(`Toplam yoklama: ${total} (silinmiş ${silinmis})`);
  console.log(`  siteId DOLU: ${siteli}   ikinciSantiyeId dolu: ${ikinciSiteli}`);
  console.log(`  siteId dolu olanların ay dağılımı: ${JSON.stringify(siteliAylar)}`);
  console.log(`\n_syncedAt gün dağılımı (ilk 12):`);
  Object.entries(bySyncDay).sort((a, b) => b[1] - a[1]).slice(0, 12).forEach(([k, v]) => console.log(`   ${k}: ${v}`));
  console.log(`\nsonDegistiren dağılımı:`);
  Object.entries(bySonDeg).sort((a, b) => b[1] - a[1]).forEach(([k, v]) => console.log(`   ${k}: ${v}`));
  console.log(`\nsenkronSurumu dağılımı: ${JSON.stringify(byVer)}`);

  // Org id ve users
  console.log(`\norg id: ${org.id}`);
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message); process.exit(1); });
