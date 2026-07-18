// SALT-OKUNUR teşhis: 4 Mayıs "borç → avans" çevirme işleminin izini sürer.
// Hiçbir şey yazmaz/silmez. Sadece .get() yapar.
//
// Amaç: son günlerde OLUŞTURULAN aktif avansları (çevirme sonucu eklenenler) ve
// son günlerde SİLİNEN borçları (çevirmede silinenler) listeler, eşleştirir.
//
// Kullanım:
//   node scripts/mayis_avans_teshis.js            (son 3 gün penceresi, varsayılan)
//   node scripts/mayis_avans_teshis.js 7          (son 7 gün)

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const GUN = Number(process.argv[2]) || 3; // kaç günlük pencere

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error(`Service account JSON bulunamadı: ${serviceAccountPath}`);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(require(serviceAccountPath)) });
const db = admin.firestore();

const TR = 3 * 3600 * 1000;
const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} TL`;
const trStamp = (ms) => (ms == null ? '—' : new Date(ms + TR).toISOString().slice(0, 16).replace('T', ' '));
const gun = (iso) => (iso ? new Date(iso).toLocaleDateString('tr-TR') : '—');
const dOnly = (iso) => String(iso || '').slice(0, 10);

async function run() {
  const nowMs = Date.now();
  const esik = nowMs - GUN * 86400000;

  const orgs = await db.collection('organizations').listDocuments();
  for (const orgRef of orgs) {
    const [wS, aS] = await Promise.all([
      orgRef.collection('calisanlar').get(),
      orgRef.collection('avans_borclar').get(),
    ]);
    const names = {};
    wS.forEach((d) => (names[d.id] = d.data().adSoyad || '(isimsiz)'));

    const yeniAvans = []; // son GUN günde OLUŞTURULMUŞ aktif avanslar
    const silinenBorc = []; // son GUN günde SİLİNMİŞ borçlar

    aS.forEach((doc) => {
      const x = doc.data();
      const createMs = doc.createTime ? doc.createTime.toMillis() : null;
      const ad = names[x.calisanId] || `(bilinmeyen:${x.calisanId})`;

      // A) Yeni oluşturulmuş aktif avanslar
      if (x.tur === 'advance' && !x.silinmeTarihi && createMs && createMs >= esik) {
        yeniAvans.push({
          id: doc.id, ad, tutar: Number(x.tutar) || 0,
          islem: dOnly(x.islemTarihi), createMs, not: x.not || '',
        });
      }
      // B) Son günlerde silinmiş borçlar
      if (x.tur === 'debt' && x.silinmeTarihi) {
        const silMs = Date.parse(x.silinmeTarihi);
        if (silMs && silMs >= esik) {
          silinenBorc.push({
            id: doc.id, ad, tutar: Number(x.tutar) || 0,
            islem: dOnly(x.islemTarihi), silinme: x.silinmeTarihi,
          });
        }
      }
    });

    yeniAvans.sort((a, b) => a.ad.localeCompare(b.ad, 'tr'));
    silinenBorc.sort((a, b) => a.ad.localeCompare(b.ad, 'tr'));

    console.log('\n════════════════════════════════════════════════════════════');
    console.log(`ORG: ${orgRef.id}   ·   pencere: son ${GUN} gün`);
    console.log('════════════════════════════════════════════════════════════');

    console.log(`\n▶ SON ${GUN} GÜNDE OLUŞTURULAN AKTİF AVANSLAR (geri alınacaklar):`);
    if (!yeniAvans.length) {
      console.log('  (yok)');
    } else {
      let t = 0;
      yeniAvans.forEach((r, i) => {
        t += r.tutar;
        console.log(`  ${String(i + 1).padStart(2)}. ${r.ad.padEnd(22)} ${TL(r.tutar).padStart(14)}   işlemT: ${r.islem}   oluşturuldu: ${trStamp(r.createMs)}${r.not ? '   not: ' + r.not : ''}`);
      });
      console.log(`  ─────────────────────────────────────────`);
      console.log(`  TOPLAM: ${TL(t)}   (${yeniAvans.length} avans)`);
    }

    console.log(`\n▶ SON ${GUN} GÜNDE SİLİNEN BORÇLAR (çevirmede silinenler):`);
    if (!silinenBorc.length) {
      console.log('  (yok)');
    } else {
      let t = 0;
      silinenBorc.forEach((r, i) => {
        t += r.tutar;
        console.log(`  ${String(i + 1).padStart(2)}. ${r.ad.padEnd(22)} ${TL(r.tutar).padStart(14)}   işlemT: ${r.islem}   silindi: ${gun(r.silinme)}`);
      });
      console.log(`  ─────────────────────────────────────────`);
      console.log(`  TOPLAM: ${TL(t)}   (${silinenBorc.length} borç)`);
    }

    // Eşleştirme: aynı kişi+tutar hem yeni avansta hem silinen borçta varsa → çevirme
    console.log(`\n▶ EŞLEŞME (kişi + tutar → çevirme olduğu kesin):`);
    const kullanildi = new Set();
    let eslesenToplam = 0, eslesenAdet = 0;
    yeniAvans.forEach((a) => {
      const m = silinenBorc.find((b, idx) => !kullanildi.has(idx) && b.ad === a.ad && Math.abs(b.tutar - a.tutar) < 0.005);
      if (m) {
        const idx = silinenBorc.indexOf(m);
        kullanildi.add(idx);
        eslesenToplam += a.tutar; eslesenAdet++;
        console.log(`  ✓ ${a.ad.padEnd(22)} ${TL(a.tutar).padStart(14)}   (borç silindi → avans eklendi)`);
      }
    });
    if (!eslesenAdet) console.log('  (net eşleşme bulunamadı — tutarlar farklı olabilir, yukarıdaki iki listeyi elle karşılaştır)');
    else console.log(`  ─────────────────────────────────────────\n  EŞLEŞEN TOPLAM: ${TL(eslesenToplam)}   (${eslesenAdet} çevirme)`);

    console.log(`\n  → Bu ${TL(yeniAvans.reduce((s, r) => s + r.tutar, 0))} tutarındaki avanslar silinirse işverenin "alacak" fazlası geri iner.`);
  }
}

run().then(() => process.exit(0)).catch((e) => { console.error('HATA:', e); process.exit(99); });
