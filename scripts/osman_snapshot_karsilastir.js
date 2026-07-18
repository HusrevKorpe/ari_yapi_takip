// SALT-OKUNUR: Osman'ın tüm snapshot'larının donmuş brüt'ünü, bugünkü
// kayıtlardan hesaplanan (çalışılan × yevmiye) ile karşılaştırır.
const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();
const ID = '2dc75cbe-0fc5-4579-a24d-b8124b600d3f';
const WAGE = 2500;
const d = (x) => String(x || '').slice(0, 10);
const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  const oz = await org.collection('maas_ozetleri').where('calisanId', '==', ID).get();
  const y = await org.collection('yoklama').where('calisanId', '==', ID).get();
  const gunler = [];
  y.forEach((x) => { const r = x.data(); if (!r.silinmeTarihi) gunler.push(r); });
  const snaps = [];
  oz.forEach((x) => snaps.push(x.data()));
  snaps.sort((p, q) => String(p.ay).localeCompare(String(q.ay)));
  console.log('SNAPSHOT donmuş brut  vs  bugunku kayitlardan hesap:\n');
  for (const o of snaps) {
    const [s, e] = String(o.ay).split('_');
    let eq = 0;
    gunler.forEach((g) => { const gg = d(g.tarih); if (gg >= d(s) && gg <= d(e)) eq += eqOf(g.durum); });
    const bugun = eq * WAGE;
    const fark = (Number(o.brut) || 0) - bugun;
    console.log(`ay=${o.ay}`);
    console.log(`   DONMUS: gunEsd=${o.calisilanGunEsdegeri} brut=${o.brut} net=${o.net} kesinti=${o.kesintiler} gunlukDetay=${o.gunlukDetay ? 'VAR' : 'YOK'} v${o.senkronSurumu} olus=${d(o.olusturulmaTarihi)}`);
    console.log(`   BUGUN : donemde ${eq} gun kars x ${WAGE} = ${bugun}   FARK(brut-bugun)= ${fark}\n`);
  }
  console.log('--- ODEMELER ---');
  const pay = await org.collection('maas_odemeleri').where('calisanId', '==', ID).get();
  const ps = [];
  pay.forEach((x) => { const r = x.data(); if (!r.silinmeTarihi) ps.push(r); });
  ps.sort((p, q) => d(p.donemBitisi).localeCompare(d(q.donemBitisi)));
  ps.forEach((p) => console.log(`   ${d(p.donemBaslangici)}-${d(p.donemBitisi)} tutar=${p.tutar} odeme=${p.odemeTarihi}`));
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message); process.exit(1); });
