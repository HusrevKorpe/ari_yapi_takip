// SALT-OKUNUR teşhis: Osman Bilgiç, 08.06.2026–27.06.2026 döneminde
// "Çalışılan Gün" (snapshot) 12 iken günlük detay 13 (11 tam + 4 yarım) neden
// gösteriyor? Bu script HİÇBİR ŞEY YAZMAZ. node scripts/osman_haziran_teshis.js
//
// Çıktı:
//  - Dönemdeki tüm yoklama kayıtları (durum, gün karşılığı, oluşturulma/güncelleme,
//    silinmiş mi) — ödeme tarihinden SONRA girilenler ⚑ ile işaretlenir.
//  - Ödeme (maas_odemeleri): tarih + tutar.
//  - Snapshot (maas_ozetleri): donmuş çalışılan gün + gunlukDetay var mı.
//  - Canlı toplam vs donmuş toplam karşılaştırması ve teşhis.

const admin = require('firebase-admin');
const path = require('path');

const START = process.argv[2] || '2026-06-08';
const END = process.argv[3] || '2026-06-27';
const ARANAN = (process.argv[4] || 'osman').toLowerCase();

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});
const db = admin.firestore();

const dOnly = (iso) => String(iso || '').slice(0, 10);
const inRange = (iso) => {
  const d = dOnly(iso);
  return d >= START && d <= END;
};
const norm = (s) =>
  String(s || '').toLocaleLowerCase('tr-TR').normalize('NFD').replace(/[̀-ͯ]/g, '');
const eqOf = (durum) =>
  durum === 'worked' ? 1.0 : durum === 'half_day' || durum === 'halfDay' ? 0.5 : 0;
const durumAd = (d) =>
  d === 'worked' ? 'TAM  ' : d === 'half_day' || d === 'halfDay' ? 'YARIM' :
  d === 'absent' ? 'YOK  ' : d === 'leave' ? 'IZIN ' : (d || '?');

async function run() {
  console.log(`\n=== Osman teşhis: ${START} → ${END} (dahil) ===`);
  const orgs = await db.collection('organizations').listDocuments();

  for (const orgRef of orgs) {
    const workers = await orgRef.collection('calisanlar').get();
    const matches = [];
    workers.forEach((d) => {
      const w = d.data();
      if (norm(w.adSoyad).includes(ARANAN)) {
        matches.push({ id: d.id, ...w });
      }
    });
    if (matches.length === 0) continue;

    console.log(`\n────────── org=${orgRef.id} ──────────`);
    for (const w of matches) {
      console.log(
        `\n★ ÇALIŞAN: ${w.adSoyad}  id=${w.id}` +
        `${w.silinmeTarihi ? ' [SİLİNMİŞ]' : ''}` +
        `${w.aktifMi === false ? ' [PASİF]' : ''}  yevmiye=${w.gunlukUcret ?? w.yevmiye ?? '?'}`
      );

      // --- ÖDEME ---
      const paySnap = await orgRef.collection('maas_odemeleri')
        .where('calisanId', '==', w.id).get();
      const pays = [];
      paySnap.forEach((d) => {
        const p = d.data();
        // Dönemi bu ödemenin kapsayıp kapsamadığını başlangıç/bitişle eşleştir.
        if (dOnly(p.donemBaslangici) === START && dOnly(p.donemBitisi) === END) {
          pays.push({ id: d.id, ...p });
        }
      });
      let odemeAni = null;
      if (pays.length === 0) {
        console.log('  ⚠ Bu döneme (tam eşleşen) ödeme bulunamadı. Tüm ödemeler:');
        paySnap.forEach((d) => {
          const p = d.data();
          console.log(`     ${dOnly(p.donemBaslangici)}–${dOnly(p.donemBitisi)}  ${p.tutar}₺  odeme=${dOnly(p.odemeTarihi)}${p.silinmeTarihi ? ' [SİLİNMİŞ]' : ''}`);
        });
      } else {
        for (const p of pays) {
          console.log(
            `  ÖDEME: ${p.tutar}₺  odemeTarihi=${p.odemeTarihi}` +
            `${p.silinmeTarihi ? `  [SİLİNMİŞ ${p.silinmeTarihi}]` : ''}`
          );
          if (!p.silinmeTarihi) odemeAni = p.odemeTarihi;
        }
      }

      // --- YOKLAMA ---
      const yokSnap = await orgRef.collection('yoklama')
        .where('calisanId', '==', w.id).get();
      const gunler = [];
      yokSnap.forEach((d) => {
        const y = d.data();
        if (inRange(y.tarih)) gunler.push({ id: d.id, ...y });
      });
      gunler.sort((a, b) => dOnly(a.tarih).localeCompare(dOnly(b.tarih)));

      console.log(`\n  --- YOKLAMA (${gunler.length} kayıt, dönem içi) ---`);
      let canliEq = 0, tam = 0, yarim = 0, silik = 0, sonraGirilen = 0;
      const gunSayac = {};
      for (const g of gunler) {
        const gün = dOnly(g.tarih);
        gunSayac[gün] = (gunSayac[gün] || 0) + (g.silinmeTarihi ? 0 : 1);
        const eq = eqOf(g.durum);
        const silinmis = !!g.silinmeTarihi;
        // Kayıt ödemeden SONRA mı oluşturuldu/güncellendi?
        const olus = g.olusturulmaTarihi || '';
        const gunc = g.guncellenmeTarihi || '';
        const sonraOlus = odemeAni && olus && olus > odemeAni;
        const sonraGunc = odemeAni && gunc && gunc > odemeAni;
        const bayrak = silinmis ? '  ✖SİLİNMİŞ' :
          sonraOlus ? '  ⚑ÖDEMEDEN SONRA GİRİLDİ' :
          sonraGunc ? '  ⚑ödemeden sonra GÜNCELLENDİ' : '';
        if (!silinmis) {
          canliEq += eq;
          if (g.durum === 'worked') tam++;
          else if (g.durum === 'half_day' || g.durum === 'halfDay') yarim++;
          if (sonraOlus || sonraGunc) sonraGirilen += eq;
        } else {
          silik++;
        }
        console.log(
          `   ${gün}  ${durumAd(g.durum)} (${eq})  olus=${dOnly(olus)}  gunc=${dOnly(gunc)}` +
          `  cihaz=${(g.cihazId || '—').toString().slice(0, 8)}${bayrak}`
        );
      }
      // Aynı güne birden fazla AKTİF kayıt = kopya
      const kopyalar = Object.entries(gunSayac).filter(([, n]) => n > 1);

      console.log(
        `\n  CANLI toplam (silinmemiş): ${canliEq} gün karş.  ` +
        `(${tam} tam + ${yarim} yarım, silinmiş ${silik} kayıt)`
      );
      if (sonraGirilen > 0) {
        console.log(`  ⚑ Ödemeden SONRA girilen/güncellenen gün karşılığı: ${sonraGirilen}`);
      }
      if (kopyalar.length > 0) {
        console.log(`  ⚠ AYNI GÜNE BİRDEN FAZLA AKTİF KAYIT (kopya): ${kopyalar.map(([g, n]) => `${g}×${n}`).join(', ')}`);
      }

      // --- SNAPSHOT ---
      const ozSnap = await orgRef.collection('maas_ozetleri')
        .where('calisanId', '==', w.id).get();
      let bulundu = false;
      ozSnap.forEach((d) => {
        const o = d.data();
        const [s, e] = String(o.ay || '').split('_');
        if (dOnly(s) === START && dOnly(e) === END) {
          bulundu = true;
          let dokumEq = null, dokumSatir = null;
          if (o.gunlukDetay) {
            try {
              const days = JSON.parse(o.gunlukDetay);
              dokumSatir = days.length;
              dokumEq = days.reduce((a, x) => a + (Number(x.dayEquivalent) || 0), 0);
            } catch (_) {}
          }
          console.log(
            `\n  --- SNAPSHOT (maas_ozetleri, ay=${o.ay}) ---\n` +
            `   DONMUŞ calisilanGunEsdegeri = ${o.calisilanGunEsdegeri}\n` +
            `   brut=${o.brut}  kesintiler=${o.kesintiler}  net=${o.net}\n` +
            `   gunlukDetay: ${o.gunlukDetay ? `VAR (${dokumSatir} satır, toplam ${dokumEq} gün karş.)` : 'YOK (eski sürüm → detay canlı hesaplanır)'}` +
            `${o.silinmeTarihi ? `  [SİLİNMİŞ ${o.silinmeTarihi}]` : ''}\n` +
            `   olus=${dOnly(o.olusturulmaTarihi)}  gunc=${dOnly(o.guncellenmeTarihi)}  senkronSurumu=${o.senkronSurumu}`
          );
        }
      });
      if (!bulundu) console.log('\n  --- SNAPSHOT: bu döneme ait maas_ozetleri kaydı YOK ---');
    }
  }
}

run().then(() => process.exit(0)).catch((e) => { console.error('HATA:', e); process.exit(99); });
