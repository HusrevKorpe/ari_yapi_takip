// SALT-OKUNUR.  node scripts/prim_ham_dokum.js
// osman + hayrettin: ham snapshot + ücret geçmişi + ödeme/avans dökümü.
// Amaç: EARNED tarafı (gün×yevmiye + prim) şişkin mi? Prim gerçekten borç mu?

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);
const requiresSite = (s) => s === 'worked' || s === 'half_day' || s === 'halfDay';
const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 0, maximumFractionDigits: 0 })}₺`;
const d10 = (x) => String(x || '').slice(0, 10);
const norm = (s) => String(s || '').toLocaleLowerCase('tr-TR').replace(/\s+/g, ' ').trim();
const TARGETS = ['yusuf azerbaycan'];

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  const [wSnap, ySnap, ozSnap, avSnap, paySnap, stSnap] = await Promise.all([
    org.collection('calisanlar').get(), org.collection('yoklama').get(),
    org.collection('maas_ozetleri').get(), org.collection('avans_borclar').get(),
    org.collection('maas_odemeleri').get(), org.collection('santiyeler').get(),
  ]);
  const siteName = new Map(), primBySite = new Map();
  stSnap.forEach((doc) => { const s = doc.data(); siteName.set(doc.id, s.ad); if (!s.silinmeTarihi) primBySite.set(doc.id, Number(s.gunlukPrim) || 0); });
  const targets = new Map();
  wSnap.forEach((doc) => { const w = doc.data(); if (!w.silinmeTarihi && w.aktifMi !== false && TARGETS.includes(norm(w.adSoyad))) targets.set(doc.id, { _id: doc.id, ...w }); });
  const by = (snap, id) => { const r = []; snap.forEach((doc) => { const x = doc.data(); if (x.silinmeTarihi) return; if (x.calisanId === id) r.push({ _id: doc.id, ...x }); }); return r; };

  for (const [wid, w] of targets) {
    const wage = Number(w.gunlukUcret) || 0;
    console.log('\n' + '═'.repeat(78));
    console.log(`${w.adSoyad}   güncel yevmiye=${TL(wage)}`);
    console.log('═'.repeat(78));

    // ücret geçmişi
    let wh = w.ucretGecmisi;
    if (typeof wh === 'string') { try { wh = JSON.parse(wh); } catch (_) {} }
    console.log('ÜCRET GEÇMİŞİ:', wh ? JSON.stringify(wh) : '(yok/boş)');

    // canlı günler: ay bazında gün + prim
    const days = by(ySnap, wid).sort((a, b) => d10(a.tarih).localeCompare(d10(b.tarih)));
    const byMonth = new Map();
    let worked = 0, canliPrim = 0;
    for (const g of days) {
      const eq = eqOf(g.durum); worked += eq;
      const m = d10(g.tarih).slice(0, 7);
      if (!byMonth.has(m)) byMonth.set(m, { gun: 0, prim: 0, sites: new Set() });
      const mm = byMonth.get(m); mm.gun += eq;
      if (requiresSite(g.durum) && g.santiyeId) {
        const p = primBySite.get(g.santiyeId) || 0;
        if (p > 0) { const sb = p * eq; canliPrim += sb; mm.prim += sb; mm.sites.add(siteName.get(g.santiyeId) || g.santiyeId?.slice(0, 6)); }
      }
    }
    console.log('\nAY BAZINDA ÇALIŞMA (canlı, güncel oranlarla):');
    for (const [m, v] of [...byMonth].sort()) console.log(`  ${m}: ${v.gun}g × ${TL(wage)} = ${TL(v.gun * wage).padStart(9)}  + prim ${TL(v.prim).padStart(7)}  [${[...v.sites].join(', ')}]`);
    console.log(`  TOPLAM: ${worked}g  gün-kazanç ${TL(worked * wage)}  + prim ${TL(canliPrim)}`);

    // ham snapshotlar — tarihsel yevmiye ve prim
    console.log('\nHAM SNAPSHOTLAR (maas_ozetleri) — donmuş kayıt:');
    const snaps = by(ozSnap, wid).sort((a, b) => String(a.month || '').localeCompare(String(b.month || '')));
    for (const o of snaps) {
      const wk = Number(o.calisilanGunEsdegeri) || 0, brut = Number(o.brut) || 0, net = Number(o.net) || 0;
      let sb = 0, wageHint = '?', hasDetay = false;
      if (o.gunlukDetay) { try { const arr = JSON.parse(o.gunlukDetay); hasDetay = true; const rates = new Set(); for (const x of arr) { sb += Number(x.siteBonus) || 0; const eq = Number(x.dayEquivalent) || 0; if (eq > 0) rates.add(Math.round((Number(x.dailyAmount) || 0) / eq)); } wageHint = [...rates].map(TL).join('/'); } catch (_) {} }
      const impliedWage = wk > 0 ? Math.round((brut - sb) / wk) : 0;
      console.log(`  [${o.month || '(boş key)'}] ${wk}g brut ${TL(brut).padStart(9)} net ${TL(net).padStart(9)} prim ${TL(sb).padStart(6)}  yevmiye≈${TL(impliedWage)} ${hasDetay ? `(döküm yevmiye ${wageHint})` : '(döküm YOK)'}`);
    }
    if (!snaps.length) console.log('  (snapshot yok)');

    const advs = by(avSnap, wid).filter((a) => a.tur === 'advance').sort((a, b) => d10(a.islemTarihi).localeCompare(d10(b.islemTarihi)));
    const pays = by(paySnap, wid).sort((a, b) => d10(a.odemeTarihi).localeCompare(d10(b.odemeTarihi)));
    console.log('\nÖDEMELER:');
    for (const p of pays) console.log(`  ${d10(p.odemeTarihi)}  dönem ${d10(p.donemBaslangici)}→${d10(p.donemBitisi)}  ${TL(p.tutar)}`);
    console.log('AVANSLAR:', advs.length ? '' : '(yok)');
    for (const a of advs) console.log(`  ${d10(a.islemTarihi)}  ${TL(a.tutar).padStart(9)}  ${a.not || ''}`);

    const advTot = advs.reduce((s, a) => s + (Number(a.tutar) || 0), 0);
    const paidTot = pays.reduce((s, p) => s + (Number(p.tutar) || 0), 0);
    console.log('\nHESAP:');
    console.log(`  gün-kazanç ${TL(worked * wage)} + prim ${TL(canliPrim)} − avans ${TL(advTot)} − ödenen ${TL(paidTot)} = ${TL(worked * wage + canliPrim - advTot - paidTot)}`);
    console.log(`  PRİMSİZ olsaydı: ${TL(worked * wage - advTot - paidTot)}  → prim'in bakiyeye katkısı: ${TL(canliPrim)}`);
  }
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message, e.stack); process.exit(1); });
