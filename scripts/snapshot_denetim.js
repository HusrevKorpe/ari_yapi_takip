// SALT-OKUNUR: TÜM çalışanların ödeme snapshot'larını (maas_ozetleri) bugünkü
// canlı puantajla karşılaştırır ve donmuş brüt ≠ canlı hesap durumlarını,
// SEBEBİYLE (prim kaybı / ücret değişimi / gün devri) sınıflandırır.
// HİÇBİR ŞEY YAZMAZ.  node scripts/snapshot_denetim.js

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const d = (x) => String(x || '').slice(0, 10);
const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);
const reqSite = (s) => s === 'worked' || s === 'half_day' || s === 'halfDay';
const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}₺`;
const near = (a, b) => Math.abs(a - b) < 0.5;

function groupBy(snap, key) {
  const m = new Map();
  snap.forEach((doc) => {
    const r = doc.data();
    if (r.silinmeTarihi) return;
    if (!m.has(r[key])) m.set(r[key], []);
    m.get(r[key]).push({ _id: doc.id, ...r });
  });
  return m;
}

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  const [wSnap, sSnap, ySnap, ozSnap] = await Promise.all([
    org.collection('calisanlar').get(),
    org.collection('santiyeler').get(),
    org.collection('yoklama').get(),
    org.collection('maas_ozetleri').get(),
  ]);

  const workers = new Map();
  wSnap.forEach((doc) => workers.set(doc.id, { _id: doc.id, ...doc.data() }));
  const prim = {};
  sSnap.forEach((doc) => (prim[doc.id] = Number(doc.data().gunlukPrim) || 0));
  const yByW = groupBy(ySnap, 'calisanId');
  const ozByW = groupBy(ozSnap, 'calisanId');

  console.log(`Çalışan:${workers.size} Şantiye:${sSnap.size} Snapshot:${ozSnap.size} Yoklama:${ySnap.size}\n`);

  const R = { primKayip: [], ucretDus: [], ucretArt: [], belirsizFazla: [], gunDevir: 0, gunAzal: [] };

  for (const [wid, w] of workers) {
    const wage = Number(w.gunlukUcret) || 0;
    const primAliyor = w.primAliyor === true;
    const ozs = (ozByW.get(wid) || []).slice().sort((a, b) => String(a.ay).localeCompare(String(b.ay)));
    if (!ozs.length) continue;
    const days = yByW.get(wid) || [];
    const rows = [];

    for (const o of ozs) {
      const [s, e] = String(o.ay || '').split('_');
      if (!s || !e) continue;
      let liveWorked = 0, livePrim = 0;
      for (const g of days) {
        const gg = d(g.tarih);
        if (gg < d(s) || gg > d(e)) continue;
        liveWorked += eqOf(g.durum);
        if (primAliyor && reqSite(g.durum) && g.siteId) livePrim += (prim[g.siteId] || 0) * eqOf(g.durum);
      }
      const snapGun = Number(o.calisilanGunEsdegeri) || 0;
      const brut = Number(o.brut) || 0;
      const extra = brut - snapGun * wage;         // brüt, gün×GÜNCEL ücretten fazlası
      const implied = snapGun > 0 ? brut / snapGun : 0;

      // gunlukDetay varsa donmuş prim/ücreti kesin oku
      let frozenPrim = null, frozenDaily = null;
      if (o.gunlukDetay) {
        try {
          const arr = JSON.parse(o.gunlukDetay);
          frozenPrim = arr.reduce((a, x) => a + (Number(x.siteBonus) || 0), 0);
          const wd = arr.filter((x) => (Number(x.dayEquivalent) || 0) > 0);
          if (wd.length) frozenDaily = (Number(wd[0].dailyAmount) || 0) / (Number(wd[0].dayEquivalent) || 1);
        } catch (_) {}
      }

      const flags = [];
      if (liveWorked - snapGun > 0.01) { flags.push(`↑gün ${snapGun}→${liveWorked}`); R.gunDevir++; }
      if (snapGun - liveWorked > 0.01) { flags.push(`↓gün ${snapGun}→${liveWorked}`); R.gunAzal.push(`${w.adSoyad} ${o.ay}`); }

      if (Math.abs(extra) >= 1) {
        let sinif;
        if (frozenPrim !== null && frozenPrim > 0.5) {
          sinif = `PRİM_KAYIP(donmuş prim ${TL(frozenPrim)}, bugün ${TL(livePrim)})`;
          R.primKayip.push({ w: w.adSoyad, ay: o.ay, tutar: frozenPrim });
        } else if (frozenDaily !== null && !near(frozenDaily, wage)) {
          if (frozenDaily > wage) { sinif = `ÜCRET_DÜŞMÜŞ(o gün ${TL(frozenDaily)}/gün → şimdi ${TL(wage)})`; R.ucretDus.push({ w: w.adSoyad, ay: o.ay }); }
          else { sinif = `ÜCRET_ARTMIŞ(o gün ${TL(frozenDaily)}/gün → şimdi ${TL(wage)})`; R.ucretArt.push({ w: w.adSoyad, ay: o.ay }); }
        } else if (extra > 0) {
          // döküm yok — prim mi eski ücret mi kesinleşmiyor
          if (!primAliyor) { sinif = `ÜCRET_DÜŞMÜŞ?(≈${TL(implied)}/gün → şimdi ${TL(wage)}, döküm yok)`; R.ucretDus.push({ w: w.adSoyad, ay: o.ay }); }
          else { sinif = `PRİM/ESKİ_ÜCRET?(+${TL(extra)}, döküm yok)`; R.belirsizFazla.push({ w: w.adSoyad, ay: o.ay, tutar: extra }); }
        } else {
          sinif = `ÜCRET_ARTMIŞ?(≈${TL(implied)}/gün → şimdi ${TL(wage)})`; R.ucretArt.push({ w: w.adSoyad, ay: o.ay });
        }
        flags.push(sinif);
      }

      if (flags.length && (Math.abs(extra) >= 1)) {
        rows.push(`   ${d(s)}–${d(e)}  donmuş:${snapGun}g ${TL(brut)}  canlı:${liveWorked}g prim:${TL(livePrim)}  ${o.gunlukDetay ? '[döküm✓]' : '[döküm✗]'}\n       → ${flags.join('  ')}`);
      }
    }

    if (rows.length) {
      console.log(`★ ${w.adSoyad}  yevmiye:${TL(wage)} prim:${primAliyor ? 'evet' : 'hayır'}${w.silinmeTarihi ? ' [SİLİNMİŞ]' : ''}${w.aktifMi === false ? ' [PASİF]' : ''}`);
      rows.forEach((r) => console.log(r));
      console.log('');
    }
  }

  console.log('════════════════ ÖZET ════════════════');
  const sum = (arr) => arr.reduce((a, x) => a + (x.tutar || 0), 0);
  console.log(`⚑ PRİM KAYIP (kesin, döküm var): ${R.primKayip.length} snapshot · toplam ${TL(sum(R.primKayip))}`);
  R.primKayip.forEach((x) => console.log(`     ${x.w}  ${x.ay}  ${TL(x.tutar)}`));
  console.log(`? PRİM/ESKİ ÜCRET belirsiz (döküm yok, prim alan): ${R.belirsizFazla.length} snapshot · ~${TL(sum(R.belirsizFazla))}`);
  R.belirsizFazla.forEach((x) => console.log(`     ${x.w}  ${x.ay}  +${TL(x.tutar)}`));
  console.log(`↓ ÜCRET DÜŞMÜŞ (o gün yevmiye bugünden yüksekti): ${R.ucretDus.length} snapshot`);
  R.ucretDus.forEach((x) => console.log(`     ${x.w}  ${x.ay}`));
  console.log(`↑ ÜCRET ARTMIŞ (o gün yevmiye bugünden düşüktü → çalışan lehine olabilir): ${R.ucretArt.length} snapshot`);
  R.ucretArt.forEach((x) => console.log(`     ${x.w}  ${x.ay}`));
  console.log(`+ GÜN DEVRETMİŞ (ödemeden sonra gün girilmiş, devreden bakiye): ${R.gunDevir} snapshot`);
  console.log(`- GÜN AZALMIŞ (ödemeden sonra gün silinmiş): ${R.gunAzal.length}${R.gunAzal.length ? ' → ' + R.gunAzal.join(', ') : ''}`);
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message); process.exit(1); });
