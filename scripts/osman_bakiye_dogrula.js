// SALT-OKUNUR: Osman Bilgiç'in bugünkü bakiyesini uygulamayla BİREBİR aynı
// formülle hesaplar ve 27.06.2026 gününün bakiyeye devredip devretmediğini
// kanıtlar. HİÇBİR ŞEY YAZMAZ. node scripts/osman_bakiye_dogrula.js
//
// Formül (lib: _lifetimeNet / workerLifetimeStatsProvider ile aynı):
//   netPosition = calisilanGun_TÜM × yevmiye + prim_TÜM − avans_TÜM − ödenen_TÜM
//   netPosition > 0  ⇒  İŞVEREN VERECEKLİ (Osman'a borçlu)

const admin = require('firebase-admin');
const path = require('path');

const ARANAN = 'osman bilgiç';
const SINIR = '2026-06-27'; // ödenen dönemin bitişi

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');
admin.initializeApp({ credential: admin.credential.cert(require(serviceAccountPath)) });
const db = admin.firestore();

const dOnly = (iso) => String(iso || '').slice(0, 10);
const norm = (s) => String(s || '').toLocaleLowerCase('tr-TR').normalize('NFD').replace(/[̀-ͯ]/g, '');
const eqOf = (d) => (d === 'worked' ? 1.0 : d === 'half_day' || d === 'halfDay' ? 0.5 : 0);
const reqSite = (d) => d === 'worked' || d === 'half_day' || d === 'halfDay';
const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ₺`;

async function run() {
  const orgs = await db.collection('organizations').listDocuments();
  for (const orgRef of orgs) {
    const workers = await orgRef.collection('calisanlar').get();
    let W = null;
    workers.forEach((d) => { if (norm(d.data().adSoyad) === norm(ARANAN)) W = { id: d.id, ...d.data() }; });
    if (!W) continue;

    const wage = Number(W.gunlukUcret) || 0;
    const primAliyor = W.primAliyor === true;
    console.log(`\n★ ${W.adSoyad}  id=${W.id}  yevmiye=${TL(wage)}  primAliyor=${primAliyor}`);

    // Santiye prim tablosu
    const sitesSnap = await orgRef.collection('santiyeler').get();
    const primBySite = {};
    sitesSnap.forEach((d) => { primBySite[d.id] = Number(d.data().gunlukPrim) || 0; });

    // --- YOKLAMA (tüm zaman, silinmemiş) ---
    const yokSnap = await orgRef.collection('yoklama').where('calisanId', '==', W.id).get();
    let workedAll = 0, bonusAll = 0;
    let workedUpto = 0, bonusUpto = 0, workedAfter = 0, bonusAfter = 0;
    let g2706 = null;
    yokSnap.forEach((d) => {
      const y = d.data();
      if (y.silinmeTarihi) return;
      const eq = eqOf(y.durum);
      let prim = 0;
      if (primAliyor && reqSite(y.durum) && y.siteId) prim = (primBySite[y.siteId] || 0) * eq;
      workedAll += eq; bonusAll += prim;
      const gün = dOnly(y.tarih);
      if (gün <= SINIR) { workedUpto += eq; bonusUpto += prim; }
      else { workedAfter += eq; bonusAfter += prim; }
      if (gün === SINIR && eq > 0) g2706 = { eq, prim, durum: y.durum, siteId: y.siteId, olus: y.olusturulmaTarihi };
    });

    // --- AVANS (tüm zaman, silinmemiş, tur=advance) ---
    const avSnap = await orgRef.collection('avans_borclar').where('calisanId', '==', W.id).get();
    let advAll = 0, advUpto = 0, advAfter = 0;
    avSnap.forEach((d) => {
      const a = d.data();
      if (a.silinmeTarihi || a.tur !== 'advance') return;
      const t = Number(a.tutar) || 0;
      advAll += t;
      if (dOnly(a.islemTarihi) <= SINIR) advUpto += t; else advAfter += t;
    });

    // --- ÖDEME (tüm zaman, silinmemiş) ---
    const paySnap = await orgRef.collection('maas_odemeleri').where('calisanId', '==', W.id).get();
    let paidAll = 0;
    const pays = [];
    paySnap.forEach((d) => {
      const p = d.data();
      if (p.silinmeTarihi) return;
      paidAll += Number(p.tutar) || 0;
      pays.push(p);
    });
    pays.sort((a, b) => dOnly(a.donemBitisi).localeCompare(dOnly(b.donemBitisi)));

    // --- NET POZİSYON (uygulama formülü) ---
    const earnedAll = workedAll * wage + bonusAll;
    const netPosition = earnedAll - advAll - paidAll;

    console.log(`\n--- ÖDEMELER (${pays.length}) ---`);
    pays.forEach((p) => console.log(`   ${dOnly(p.donemBaslangici)}–${dOnly(p.donemBitisi)}  ${TL(p.tutar)}  odeme=${dOnly(p.odemeTarihi)}`));
    console.log(`   TOPLAM ödenen: ${TL(paidAll)}`);

    console.log(`\n--- TÜM ZAMAN ---`);
    console.log(`   çalışılan gün karş. : ${workedAll}   (× ${TL(wage)} = ${TL(workedAll * wage)})`);
    console.log(`   prim (tüm)          : ${TL(bonusAll)}`);
    console.log(`   kazanılan (brüt)    : ${TL(earnedAll)}`);
    console.log(`   avans (tüm)         : ${TL(advAll)}`);
    console.log(`   ödenen (tüm)        : ${TL(paidAll)}`);
    console.log(`   ───────────────────────────────`);
    console.log(`   NET POZİSYON        : ${TL(netPosition)}   ${netPosition > 0.5 ? '⇒ İŞVEREN VERECEKLİ (Osman alacaklı)' : netPosition < -0.5 ? '⇒ İşveren alacaklı' : '⇒ kapalı'}`);

    // --- 27.06 gününün katkısı ---
    if (g2706) {
      const kat = g2706.eq * wage + g2706.prim;
      console.log(`\n--- 27.06.2026 GÜNÜ (ödemeden sonra girilen) ---`);
      console.log(`   durum=${g2706.durum} (${g2706.eq})  prim=${TL(g2706.prim)}  → değeri = ${TL(kat)}`);
      console.log(`   Bu gün olmasaydı net pozisyon: ${TL(netPosition - kat)}`);
      console.log(`   ⇒ 27.06 günü net pozisyonu tam ${TL(kat)} artırıyor; yani BAKİYEDE DURUYOR.`);
    } else {
      console.log(`\n⚠ 27.06.2026 için çalışılan (>0) yoklama bulunamadı.`);
    }

    // --- Ödenmiş dönemler mutabakatı: ≤27.06 kazanılan vs ödenen ---
    const kapananKazanc = workedUpto * wage + bonusUpto;
    const kapananFark = kapananKazanc - advUpto - paidAll;
    console.log(`\n--- ÖDENMİŞ DÖNEMLER MUTABAKATI (gün ≤ ${SINIR}) ---`);
    console.log(`   ≤27.06 kazanılan: ${TL(kapananKazanc)}  − avans ${TL(advUpto)} − ödenen ${TL(paidAll)} = ${TL(kapananFark)}`);
    console.log(`   (Bu fark, ödenmiş dönemlerden devreden tutar; 27.06 günü buranın içinde.)`);
    console.log(`\n--- AÇIK DÖNEM (gün > ${SINIR}) ---`);
    console.log(`   >27.06 kazanılan: ${TL(workedAfter * wage + bonusAfter)}  (çalışılan ${workedAfter} gün)  − avans ${TL(advAfter)}`);
  }
}

run().then(() => process.exit(0)).catch((e) => { console.error('HATA:', e); process.exit(99); });
