// SALT-OKUNUR.  node scripts/prim_odendi_mi.js
// osman bilgiç + hayrettin ünal: primleri geçmişte ödendi mi?
//
// Mantık: her ödeme (maas_odemeleri) bir döneme ait. O dönemin donmuş
// snapshot'ı (maas_ozetleri, key=start_end) gross'unda prim VAR mıydı?
//   ΣsiteBonus (gunlukDetay) = o snapshot'ın gross'una giren prim.
//   Ödeme tutarı ≈ snapshot net ise → o prim NAKİT ödendi.
// canlıPrim (bugün app'in saydığı tüm prim) − (ödenmiş snapshot'lardaki prim)
//   = henüz ödenmemiş / açık dönem primi.

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);
const requiresSite = (s) => s === 'worked' || s === 'half_day' || s === 'halfDay';
const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 0, maximumFractionDigits: 0 })}₺`;
const d10 = (x) => String(x || '').slice(0, 10);
const pk = (a, b) => `${d10(a)}_${d10(b)}`;
const norm = (s) => String(s || '').toLocaleLowerCase('tr-TR').replace(/\s+/g, ' ').trim();

const TARGETS = ['osman bilgiç', 'hayrettin ünal'];

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  const [wSnap, ySnap, ozSnap, avSnap, paySnap, stSnap] = await Promise.all([
    org.collection('calisanlar').get(),
    org.collection('yoklama').get(),
    org.collection('maas_ozetleri').get(),
    org.collection('avans_borclar').get(),
    org.collection('maas_odemeleri').get(),
    org.collection('santiyeler').get(),
  ]);
  const primBySite = new Map();
  stSnap.forEach((doc) => { const s = doc.data(); if (s.silinmeTarihi) return; primBySite.set(doc.id, Number(s.gunlukPrim) || 0); });

  const targetIds = new Map(); // id -> worker
  wSnap.forEach((doc) => { const w = doc.data(); if (!w.silinmeTarihi && w.aktifMi !== false && TARGETS.includes(norm(w.adSoyad))) targetIds.set(doc.id, { _id: doc.id, ...w }); });

  const by = (snap, id) => { const r = []; snap.forEach((doc) => { const x = doc.data(); if (x.silinmeTarihi) return; if (x.calisanId === id) r.push({ _id: doc.id, ...x }); }); return r; };

  for (const [wid, w] of targetIds) {
    const wage = Number(w.gunlukUcret) || 0;
    const days = by(ySnap, wid);
    const snaps = by(ozSnap, wid);
    const advs = by(avSnap, wid).filter((a) => a.tur === 'advance');
    const pays = by(paySnap, wid);

    let worked = 0, canliPrim = 0;
    const primDays = []; // {date, sb}
    for (const g of days) {
      worked += eqOf(g.durum);
      if (requiresSite(g.durum) && g.santiyeId) {
        const p = primBySite.get(g.santiyeId) || 0;
        if (p > 0) { const sb = p * eqOf(g.durum); canliPrim += sb; primDays.push({ date: d10(g.tarih), sb, site: g.santiyeId }); }
      }
    }
    const advTot = advs.reduce((s, a) => s + (Number(a.tutar) || 0), 0);
    const paidTot = pays.reduce((s, p) => s + (Number(p.tutar) || 0), 0);
    const canliNet = worked * wage + canliPrim - advTot - paidTot;

    // snapshot prim (period key -> ΣsiteBonus + hasDetay + gross/net/worked)
    const snapByKey = new Map();
    for (const o of snaps) {
      const key = o.month || pk(o.donemBaslangici, o.donemBitisi);
      let sbSum = 0, hasDetay = false;
      if (o.gunlukDetay) { try { for (const x of JSON.parse(o.gunlukDetay)) sbSum += Number(x.siteBonus) || 0; hasDetay = true; } catch (_) {} }
      snapByKey.set(key, { key, worked: Number(o.calisilanGunEsdegeri) || 0, gross: Number(o.brut) || 0, net: Number(o.net) || 0, ded: Number(o.kesintiler) || 0, sbSum, hasDetay });
    }

    console.log('\n' + '═'.repeat(74));
    console.log(`${w.adSoyad}   (yevmiye ${TL(wage)})`);
    console.log('═'.repeat(74));
    console.log(`worked=${worked}g  canlıPrim=${TL(canliPrim)}  avans=${TL(advTot)}  ödenen=${TL(paidTot)}  → CANLI net=${TL(canliNet)}`);

    console.log('\nÖDEMELER (tarih → dönem → tutar | o dönemin snapshot primi/net):');
    pays.sort((a, b) => d10(a.odemeTarihi).localeCompare(d10(b.odemeTarihi)));
    let primInPaidPeriods = 0;
    const paidKeys = new Set();
    for (const p of pays) {
      const key = pk(p.donemBaslangici, p.donemBitisi);
      paidKeys.add(key);
      const s = snapByKey.get(key);
      const tutar = Number(p.tutar) || 0;
      let tag = '';
      if (s) {
        primInPaidPeriods += s.sbSum;
        const kapsar = tutar + 0.5 >= s.net ? '✓tam' : '⚠eksik';
        tag = `snapPrim=${TL(s.sbSum)} snapNet=${TL(s.net)} ${s.hasDetay ? '' : '(döküm YOK)'} ${kapsar}`;
      } else {
        tag = 'snapshot YOK (dökümsüz ödeme → primi bilinmiyor)';
      }
      console.log(`  ${d10(p.odemeTarihi)}  ${key}  ödendi ${TL(tutar).padStart(9)}  | ${tag}`);
    }
    if (!pays.length) console.log('  (hiç maaş ödemesi yok)');

    // snapshot'ı olup ödemesi olmayan dönemler
    const orphanPrim = [];
    for (const [key, s] of snapByKey) if (!paidKeys.has(key) && s.sbSum > 0) orphanPrim.push({ key, sb: s.sbSum });

    console.log('\nPRİM MUHASEBESİ:');
    console.log(`  Bugün app'in saydığı TÜM prim (canlıPrim)     : ${TL(canliPrim)}`);
    console.log(`  Ödenmiş dönemlerin snapshot'ındaki prim       : ${TL(primInPaidPeriods)}  ← nakit ödendiği belgeli`);
    const kalan = canliPrim - primInPaidPeriods;
    console.log(`  Fark (ödeme snapshot'ında GÖRÜNMEYEN prim)    : ${TL(kalan)}`);
    if (orphanPrim.length) {
      console.log(`    ↳ bunun ${TL(orphanPrim.reduce((s, o) => s + o.sb, 0))}'si ödemesi olmayan snapshot dönemlerinde:`);
      for (const o of orphanPrim) console.log(`        ${o.key}: ${TL(o.sb)}`);
    }
    // hangi prim günleri hiç bir snapshot dönemine düşmüyor? (kaba: tarih aralığı)
    console.log('\n  YORUM: Fark > 0 ise ya (a) açık/güncel dönemin primi (henüz ödenmedi, GERÇEK borç),');
    console.log('         ya (b) dökümsüz eski ödemeye gömülü prim (ödendi ama snapshot göstermiyor).');
  }
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message, e.stack); process.exit(1); });
