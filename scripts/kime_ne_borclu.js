// SALT-OKUNUR: Her çalışan için uygulamanın gösterdiği net bakiye.
// Uygulamanın _lifetimeNet formülünü BİREBİR üretir:
//   NET(app) = çalışılan gün × yevmiye + PRİM(canlı) − avans − ödenen
//   PRİM(canlı) = primAliyor ise, her yoklamada santiyeId dolu + durum saha
//                 gerektiriyorsa site.gunlukPrim × günKarşılığı (birincil santiye).
// + = işveren VERECEK (çalışan alacaklı),  − = çalışan fazla avans almış.
// BAYRAK: canlı prim ≠ donmuş snapshot primi (retro/carryOver) veya zam izi.
// HİÇBİR ŞEY YAZMAZ.  node scripts/kime_ne_borclu.js

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const d = (x) => String(x || '').slice(0, 10);
const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);
const requiresSite = (s) => s === 'worked' || s === 'half_day' || s === 'halfDay';
const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}₺`;
const near = (a, b) => Math.abs(a - b) < 0.5;

function groupBy(snap, key) {
  const m = new Map();
  snap.forEach((doc) => { const r = doc.data(); if (r.silinmeTarihi) return; if (!m.has(r[key])) m.set(r[key], []); m.get(r[key]).push({ _id: doc.id, ...r }); });
  return m;
}

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

  const sitePrim = {};
  stSnap.forEach((doc) => { sitePrim[doc.id] = Number(doc.data().gunlukPrim) || 0; });

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

    // App _lifetimeNet: worked eşdeğeri + canlı prim (birincil santiyeId)
    let workedAll = 0, liveBonus = 0;
    for (const g of days) {
      workedAll += eqOf(g.durum);
      if (primAliyor && requiresSite(g.durum) && g.santiyeId) {
        const b = sitePrim[g.santiyeId] || 0;
        if (b > 0) liveBonus += b * (g.durum === 'half_day' || g.durum === 'halfDay' ? 0.5 : 1.0);
      }
    }

    const advAll = (avByW.get(wid) || []).filter((a) => a.tur === 'advance').reduce((s, a) => s + (Number(a.tutar) || 0), 0);
    const paidAll = (payByW.get(wid) || []).reduce((s, p) => s + (Number(p.tutar) || 0), 0);
    const appNet = workedAll * wage + liveBonus - advAll - paidAll;

    // Donmuş snapshot primi (tarih bazlı dedupe) — canlıyla kıyas için
    const primByDate = new Map();
    let ucretDiff = false;
    for (const o of (ozByW.get(wid) || [])) {
      if (!o.gunlukDetay) continue;
      try {
        const arr = JSON.parse(o.gunlukDetay);
        for (const x of arr) {
          const sb = Number(x.siteBonus) || 0;
          if (sb > 0) primByDate.set(d(x.date), Math.max(primByDate.get(d(x.date)) || 0, sb));
          const eq = Number(x.dayEquivalent) || 0;
          if (eq > 0 && !near((Number(x.dailyAmount) || 0) / eq, wage)) ucretDiff = true;
        }
      } catch (_) {}
    }
    let frozenPrim = 0;
    primByDate.forEach((v) => (frozenPrim += v));

    out.push({
      ad: w.adSoyad, wage, primAliyor, silinmis: !!w.silinmeTarihi, pasif: w.aktifMi === false,
      workedAll, liveBonus, advAll, paidAll, appNet, frozenPrim, ucretDiff,
      snapCount: (ozByW.get(wid) || []).length,
    });
  }

  out.sort((a, b) => b.appNet - a.appNet);

  console.log('KİME NE ÖDENECEK — UYGULAMANIN GÖSTERDİĞİ NET (canlı prim dahil)\n');
  console.log('+ = işveren VERECEK (çalışan alacaklı)   − = çalışan fazla avans almış\n');
  console.log(
    'AD'.padEnd(22) + 'NET(app)'.padStart(12) + 'gün'.padStart(6) + 'kazanç'.padStart(11) +
    'prim'.padStart(9) + 'avans'.padStart(11) + 'ödenen'.padStart(11) + '  BAYRAK'
  );
  console.log('─'.repeat(100));
  let topPlus = 0, topMinus = 0;
  for (const r of out) {
    if (near(r.appNet, 0) && r.liveBonus === 0 && r.frozenPrim === 0) continue; // kapalı hesap
    const bayrak = [];
    const primDiff = r.liveBonus - r.frozenPrim;
    if (r.primAliyor && r.snapCount === 0 && r.liveBonus > 0.5) {
      bayrak.push('hiç maaş ödemesi yok (hep avans) — prim normal');
    } else if (r.primAliyor && r.snapCount > 0 && primDiff > 0.5) {
      bayrak.push(`retro prim? ödenmiş döneme +${TL(primDiff)} sonradan santiye — GÖZDEN GEÇİR`);
    } else if (r.primAliyor && r.snapCount > 0 && primDiff < -0.5) {
      bayrak.push(`prim kaybı? donmuştan −${TL(-primDiff)}`);
    }
    if (r.ucretDiff) bayrak.push('~zam (APK güncellenince değişebilir)');
    if (r.silinmis) bayrak.push('SİLİNMİŞ');
    if (r.pasif) bayrak.push('PASİF');
    const name = (r.ad || '?').slice(0, 21);
    console.log(
      name.padEnd(22) + TL(r.appNet).padStart(12) + String(r.workedAll).padStart(6) +
      TL(r.workedAll * r.wage).padStart(11) + TL(r.liveBonus).padStart(9) +
      TL(r.advAll).padStart(11) + TL(r.paidAll).padStart(11) + '  ' + bayrak.join(' | ')
    );
    if (r.appNet > 0) topPlus += r.appNet; else topMinus += r.appNet;
  }
  console.log('─'.repeat(100));
  console.log(`\nTOPLAM işveren VERECEK (+): ${TL(topPlus)}`);
  console.log(`TOPLAM çalışan fazla avans (−): ${TL(topMinus)}`);
  console.log('\nNOT: NET(app) = uygulamanın ekranda gösterdiği rakam; ödeme bu sütuna göre yapılır.');
  console.log('"canlı prim donmuştan +X (retro)" = ödenmiş döneme sonradan şantiye atanmış → app fazladan');
  console.log('prim sayıyor (carryOver). O günlerde gerçekten o şantiyedeyse doğru, değilse gözden geçir.');
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message); process.exit(1); });
