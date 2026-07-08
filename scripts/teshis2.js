// SALT-OKUNUR: her koleksiyonda en son yazma zamanı + Temmuz 2026 aktivitesi.
const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const COLLECTIONS = ['calisanlar','santiyeler','yoklama','giderler','gelirler','ortak_odemeleri','avans_borclar','maas_odemeleri','maas_ozetleri','santiye_notlari'];
const iso = (v) => { if (!v) return ''; if (typeof v === 'object' && v.toDate) return v.toDate().toISOString(); return String(v); };
const s = (x) => x ? x.slice(0,16) : '—';

async function run() {
  const orgs = await db.collection('organizations').listDocuments();
  for (const orgRef of orgs) {
    console.log(`\norg=${orgRef.id}`);
    console.log('koleksiyon           enSonOlusturma    enSonGuncelleme   Temmuz2026(olus)');
    console.log('-------------------------------------------------------------------------');
    for (const c of COLLECTIONS) {
      const snap = await orgRef.collection(c).get();
      let maxOlus = '', maxGun = '', tmz = 0;
      snap.forEach((d) => {
        const x = d.data();
        const o = iso(x.olusturulmaTarihi), g = iso(x.guncellenmeTarihi);
        if (o > maxOlus) maxOlus = o;
        if (g > maxGun) maxGun = g;
        if (o.startsWith('2026-07')) tmz++;
      });
      console.log(`${c.padEnd(20)} ${s(maxOlus).padEnd(17)} ${s(maxGun).padEnd(17)} ${tmz}`);
    }

    // yoklama: iş tarihine (tarih alanı) göre en son 5 gün + Temmuz iş günleri
    const yk = await orgRef.collection('yoklama').get();
    const tarihler = new Set();
    let temmuzIsGunu = 0;
    yk.forEach((d) => {
      const t = iso(d.data().tarih).slice(0,10);
      if (t) tarihler.add(t);
      if (t >= '2026-07-01') temmuzIsGunu++;
    });
    const sortedT = [...tarihler].sort().reverse();
    console.log(`\nyoklama iş-tarihi (tarih alanı) — en son 8 gün: ${sortedT.slice(0,8).join(', ')}`);
    console.log(`yoklama: 1 Temmuz ve sonrası iş günü kaydı = ${temmuzIsGunu}`);
  }
}
run().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
