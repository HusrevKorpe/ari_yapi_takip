// SALT-OKUNUR. Hiçbir veri yazmaz.  node scripts/canli_vs_tablo.js
//
// Canlı "Maaş Ver" ekranının gösterdiği net (PayrollRepository._lifetimeNet)
// ile bu oturumda verdiğim "vereceğin (düzeltilmiş)" tablosunu yan yana koyar.
//
// CANLI net = worked×güncelYevmiye + canlıPrim − avans − ödenen
//   canlıPrim = totalLocationBonus: sadece BİRİNCİL santiyeId dolu ve
//   santiye.gunlukPrim>0 olan worked/half_day günlerde. (ikinciSantiyeId
//   uygulamada prim'e katılmıyor — birebir taklit ediliyor.)
// PRIM(snap) = donmuş maas_ozetleri dökümünden tarih-bazlı geri eklenen prim
//   (benim tablomun primi buradan geldi; canlı ekran bunu GÖRMÜYOR).

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const d = (x) => String(x || '').slice(0, 10);
const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);
const requiresSite = (s) => s === 'worked' || s === 'half_day' || s === 'halfDay';
const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 0, maximumFractionDigits: 0 })}₺`;
const near = (a, b) => Math.abs(a - b) < 0.5;
const norm = (s) => String(s || '').toLocaleLowerCase('tr-TR').replace(/\s+/g, ' ').trim();

// Bu oturumda verdiğim tablo (vereceğin = +, çalışan borçlu = −)
const TABLO = {
  'yusuf azerbaycan': 18400, 'bayram uğuz': 16250, 'abdullah akbaş': 14850,
  'osman bilgiç': 13400, 'hayrettin ünal': 13200, 'ern fidan': 3750,
  'nihat azerbrycan': 3650, 'şamil furkan arıgüzel': 3217, 'ibrahim varışlı': 1925,
  'ibrahim azerbaycan': 1300, 'nejıbullah moradi': 100,
  'ahmet furtana': -19800, 'abdullah yüzgeç': -11390, 'ilker varışlı': -10478,
  'halil ibrahim ekici': -9550, 'hasan yalvaçlı': -7700, 'engin furtana': -6674,
  'ali osman': -6569, 'mehmet güngör': -6465, 'çoşkun azerbaycan': -3000,
  'murat azerbaycan': -600,
};
const TABLO_KOPYA_ABDULLAH = 2500; // pasif kopya kaydı

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
  const workers = new Map();
  wSnap.forEach((doc) => workers.set(doc.id, { _id: doc.id, ...doc.data() }));
  const primBySite = new Map();
  stSnap.forEach((doc) => { const s = doc.data(); if (s.silinmeTarihi) return; primBySite.set(doc.id, Number(s.gunlukPrim) || 0); });
  const yByW = groupBy(ySnap, 'calisanId');
  const ozByW = groupBy(ozSnap, 'calisanId');
  const avByW = groupBy(avSnap, 'calisanId');
  const payByW = groupBy(paySnap, 'calisanId');

  // Yoklamalarda birincil santiyeId doluluk oranı (org geneli tanı)
  let toplamGun = 0, sahaliGun = 0;
  ySnap.forEach((doc) => { const r = doc.data(); if (r.silinmeTarihi) return; if (!requiresSite(r.durum)) return; toplamGun++; if (r.santiyeId) sahaliGun++; });

  const out = [];
  for (const [wid, w] of workers) {
    const wage = Number(w.gunlukUcret) || 0;
    const primAliyor = w.primAliyor === true;
    const days = yByW.get(wid) || [];
    let worked = 0, canliPrim = 0;
    for (const g of days) {
      worked += eqOf(g.durum);
      if (primAliyor && requiresSite(g.durum) && g.santiyeId) {
        const p = primBySite.get(g.santiyeId) || 0;
        if (p > 0) canliPrim += p * eqOf(g.durum);
      }
    }
    const advAll = (avByW.get(wid) || []).filter((a) => a.tur === 'advance').reduce((s, a) => s + (Number(a.tutar) || 0), 0);
    const paidAll = (payByW.get(wid) || []).reduce((s, p) => s + (Number(p.tutar) || 0), 0);
    const canliNet = worked * wage + canliPrim - advAll - paidAll; // === app _lifetimeNet

    // donmuş snapshot priminin toplamı (benim tablomun prim kaynağı)
    const primByDate = new Map();
    for (const o of (ozByW.get(wid) || [])) {
      if (!o.gunlukDetay) continue;
      try { for (const x of JSON.parse(o.gunlukDetay)) { const sb = Number(x.siteBonus) || 0; if (sb > 0) primByDate.set(d(x.date), Math.max(primByDate.get(d(x.date)) || 0, sb)); } } catch (_) {}
    }
    let primSnap = 0; primByDate.forEach((v) => (primSnap += v));

    out.push({ ad: w.adSoyad, pasif: w.aktifMi === false, silinmis: !!w.silinmeTarihi, primAliyor, wage, worked, canliPrim, primSnap, advAll, paidAll, canliNet });
  }

  // Tablo eşleştir
  for (const r of out) {
    const key = norm(r.ad);
    if (key === 'abdullah akbaş' && r.pasif) r.tablo = TABLO_KOPYA_ABDULLAH;
    else if (key in TABLO) r.tablo = TABLO[key];
    else r.tablo = null;
  }

  console.log(`\nYOKLAMA SANTİYE DOLULUĞU: ${sahaliGun}/${toplamGun} çalışılan günde birincil santiyeId dolu` +
    (toplamGun ? `  (%${((sahaliGun / toplamGun) * 100).toFixed(1)})` : '') + '\n');

  const withTablo = out.filter((r) => r.tablo !== null).sort((a, b) => (b.tablo || 0) - (a.tablo || 0));

  console.log('KARŞILAŞTIRMA  (+ = sen verecesin,  − = çalışan fazla avans/borçlu)\n');
  console.log('AD'.padEnd(24) + 'CANLI(app)'.padStart(12) + 'BENİM tablo'.padStart(13) + 'FARK'.padStart(11) + '   canlıPrim/snapPrim');
  console.log('─'.repeat(92));
  for (const r of withTablo) {
    const fark = r.canliNet - r.tablo;
    const flag = [];
    if (r.pasif) flag.push('PASİF');
    if (Math.abs(fark) < 200) flag.push('≈uyumlu');
    const primInfo = `${TL(r.canliPrim)} / ${TL(r.primSnap)}` + (r.primAliyor ? '' : ' (prim yok)');
    console.log(
      (r.ad || '?').slice(0, 23).padEnd(24) +
      TL(r.canliNet).padStart(12) +
      TL(r.tablo).padStart(13) +
      (fark >= 0 ? '+' : '') + TL(fark).padStart(fark >= 0 ? 10 : 11) +
      '   ' + primInfo + (flag.length ? '  ' + flag.join(' ') : '')
    );
  }
  console.log('─'.repeat(92));
  const sumCanli = withTablo.filter(r => r.canliNet > 0).reduce((s, r) => s + r.canliNet, 0);
  const sumTablo = withTablo.filter(r => r.tablo > 0).reduce((s, r) => s + r.tablo, 0);
  console.log(`Pozitif TOPLAM  →  CANLI(app): ${TL(sumCanli)}    BENİM tablo: ${TL(sumTablo)}`);

  // Tabloda olup eşleşmeyen (isim farkı) uyarısı
  const matched = new Set(withTablo.map(r => norm(r.ad)));
  const missing = Object.keys(TABLO).filter(k => !matched.has(k) && !(k === 'abdullah akbaş'));
  if (missing.length) console.log(`\n⚠ Tabloda olup canlıda isimle eşleşmeyen: ${missing.join(', ')}`);

  console.log('\nNOT: CANLI(app) = uygulamanın Maaş Ver ekranındaki net (worked×güncelYevmiye + canlıPrim − avans − ödenen).');
  console.log('canlıPrim çoğu kişide 0 çünkü re-sync sonrası birincil santiyeId boş → uygulama primi İLERİ hesaplamıyor.');
  console.log('snapPrim = donmuş dökümdeki prim; benim tablom bunu geri ekledi, canlı ekran eklemiyor → asıl fark bu.');
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message); process.exit(1); });
