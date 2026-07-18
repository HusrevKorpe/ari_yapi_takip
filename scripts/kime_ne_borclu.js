// SALT-OKUNUR: Her çalışan için bugünkü net bakiye.
//  APP_NET  = uygulamanın gösterdiği (worked×güncelYevmiye − avans − ödenen)
//  PRIM+    = donmuş dökümlerden (gunlukDetay.siteBonus) geri eklenen prim (tarih bazında dedupe)
//  DÜZELTİLMİŞ = APP_NET + PRIM+  (prim alan kişilerde daha doğru)
//  Bayrak: döküm✗ dönemde brüt>gün×yevmiye (bilinmeyen prim/eski ücret) → ± belirsiz
// HİÇBİR ŞEY YAZMAZ.  node scripts/kime_ne_borclu.js

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const d = (x) => String(x || '').slice(0, 10);
const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);
const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}₺`;
const near = (a, b) => Math.abs(a - b) < 0.5;

function groupBy(snap, key) {
  const m = new Map();
  snap.forEach((doc) => { const r = doc.data(); if (r.silinmeTarihi) return; if (!m.has(r[key])) m.set(r[key], []); m.get(r[key]).push({ _id: doc.id, ...r }); });
  return m;
}

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  const [wSnap, ySnap, ozSnap, avSnap, paySnap] = await Promise.all([
    org.collection('calisanlar').get(),
    org.collection('yoklama').get(),
    org.collection('maas_ozetleri').get(),
    org.collection('avans_borclar').get(),
    org.collection('maas_odemeleri').get(),
  ]);
  const workers = new Map();
  wSnap.forEach((doc) => workers.set(doc.id, { _id: doc.id, ...doc.data() }));
  const yByW = groupBy(ySnap, 'calisanId');
  const ozByW = groupBy(ozSnap, 'calisanId');
  const avByW = groupBy(avSnap, 'calisanId');
  const payByW = groupBy(paySnap, 'calisanId');

  const out = [];
  for (const [wid, w] of workers) {
    const wage = Number(w.gunlukUcret) || 0;
    const primAliyor = w.primAliyor === true;
    const days = yByW.get(wid) || [];
    let workedAll = 0;
    days.forEach((g) => (workedAll += eqOf(g.durum)));
    const advAll = (avByW.get(wid) || []).filter((a) => a.tur === 'advance').reduce((s, a) => s + (Number(a.tutar) || 0), 0);
    const paidAll = (payByW.get(wid) || []).reduce((s, p) => s + (Number(p.tutar) || 0), 0);
    const appNet = workedAll * wage - advAll - paidAll;

    // Donmuş dökümlerden tarih-bazlı prim (dedupe) + eski-ücret farkı tespiti
    const primByDate = new Map();
    let dokumsuzFazla = 0; // döküm olmayan snapshot'larda brüt−gün×yevmiye (bilinmeyen prim/eski ücret)
    let ucretDiff = false;
    for (const o of (ozByW.get(wid) || [])) {
      const snapGun = Number(o.calisilanGunEsdegeri) || 0;
      const brut = Number(o.brut) || 0;
      if (o.gunlukDetay) {
        try {
          const arr = JSON.parse(o.gunlukDetay);
          for (const x of arr) {
            const dt = d(x.date);
            const sb = Number(x.siteBonus) || 0;
            if (sb > 0) primByDate.set(dt, Math.max(primByDate.get(dt) || 0, sb));
            const eq = Number(x.dayEquivalent) || 0;
            if (eq > 0 && !near((Number(x.dailyAmount) || 0) / eq, wage)) ucretDiff = true;
          }
        } catch (_) {}
      } else if (brut - snapGun * wage > 0.5) {
        dokumsuzFazla += brut - snapGun * wage;
      }
    }
    let primKnown = 0;
    primByDate.forEach((v) => (primKnown += v));
    const fair = appNet + primKnown;

    const snapCount = (ozByW.get(wid) || []).length;
    out.push({ ad: w.adSoyad, wage, primAliyor, silinmis: !!w.silinmeTarihi, pasif: w.aktifMi === false, workedAll, advAll, paidAll, appNet, primKnown, dokumsuzFazla, ucretDiff, fair, snapCount, dayCount: days.length });
  }

  out.sort((a, b) => b.fair - a.fair);

  console.log('BİLEŞENLER (neden negatif/pozitif olduğunu görmek için)\n');
  console.log('AD'.padEnd(22) + 'gün'.padStart(6) + 'kazanç'.padStart(11) + 'avans'.padStart(10) + 'ödenen'.padStart(11) + 'snap'.padStart(5) + 'ödm/gün');
  console.log('─'.repeat(80));
  for (const r of out) {
    if (near(r.appNet, 0) && r.primKnown === 0) continue;
    const odmGun = r.workedAll > 0 ? r.paidAll / r.workedAll : 0;
    console.log((r.ad || '?').slice(0, 21).padEnd(22) + String(r.workedAll).padStart(6) + TL(r.workedAll * r.wage).padStart(11) + TL(r.advAll).padStart(10) + TL(r.paidAll).padStart(11) + String(r.snapCount).padStart(5) + '  ' + TL(odmGun) + `/g (yev ${TL(r.wage)})`);
  }
  console.log('');

  console.log('KİME NE BORÇLU / ALACAKLI  (+ = işveren VERECEK / çalışan alacaklı,  − = çalışan borçlu)\n');
  console.log('AD'.padEnd(22) + 'DÜZELTİLMİŞ'.padStart(13) + 'APP'.padStart(12) + 'PRİM+'.padStart(10) + '  BAYRAK');
  console.log('─'.repeat(78));
  let topPlus = 0, topMinus = 0;
  for (const r of out) {
    if (near(r.fair, 0) && near(r.appNet, 0) && r.primKnown === 0 && r.dokumsuzFazla === 0) continue; // kapalı hesap
    const bayrak = [];
    if (r.dokumsuzFazla > 0.5) bayrak.push(`?±${TL(r.dokumsuzFazla)}(dökümsüz prim/eski ücret)`);
    if (r.ucretDiff) bayrak.push('~zam(yeniden fiyatlama)');
    if (r.silinmis) bayrak.push('SİLİNMİŞ');
    if (r.pasif) bayrak.push('PASİF');
    const name = (r.ad || '?').slice(0, 21);
    console.log(name.padEnd(22) + TL(r.fair).padStart(13) + TL(r.appNet).padStart(12) + TL(r.primKnown).padStart(10) + '  ' + bayrak.join(' '));
    if (r.fair > 0) topPlus += r.fair; else topMinus += r.fair;
  }
  console.log('─'.repeat(78));
  console.log(`TOPLAM işveren VERECEK (düzeltilmiş +): ${TL(topPlus)}`);
  console.log(`TOPLAM çalışan borçlu (düzeltilmiş −): ${TL(topMinus)}`);
  console.log(`\nNOT: PRİM+ = donmuş dökümden kesin geri eklenen prim. "?±...(dökümsüz)" olan satırlarda`);
  console.log(`o kadar daha prim/eski-ücret farkı olabilir (döküm yok, kesinleşmiyor). "~zam" satırlarında`);
  console.log(`yevmiye zammı geçmişi yeniden fiyatladığı için APP rakamı şişkin olabilir.`);
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message); process.exit(1); });
