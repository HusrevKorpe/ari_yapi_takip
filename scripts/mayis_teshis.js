// SALT OKUNUR teşhis: 04.05.2026 borç→avans dönüşümünün bakiyelere etkisi.
//
// Neden: canlı koddaki kesinti mantığı
//     tur='advance' → kesinti +tutar  (maaşı DÜŞÜRÜR)
//     tur='debt'    → kesinti -tutar  (maaşı YÜKSELTİR)
// Yani bir 'debt' kaydını silip yerine aynı tutarda 'advance' koymak,
// çalışanın bakiyesini tutarın İKİ KATI kadar aşağı çeker.
//
// Kullanım:
//   node mayis_teshis.js            → 2026-05-04
//   node mayis_teshis.js 2026-05-04
//
// Hiçbir yazma yapmaz.

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');

if (!fs.existsSync(serviceAccountPath)) {
  console.error(`Service account JSON bulunamadı: ${serviceAccountPath}`);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});
const db = admin.firestore();

const target = process.argv[2] || '2026-05-04';

const TL = (n) =>
  `${(Number(n) || 0).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} TL`;

const dkey = (v) => {
  if (!v) return null;
  const d = v.toDate ? v.toDate() : new Date(v);
  if (isNaN(d)) return null;
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
    d.getDate()
  ).padStart(2, '0')}`;
};

const fmt = (v) => {
  const k = dkey(v);
  if (!k) return '-';
  const [y, m, d] = k.split('-');
  return `${d}.${m}.${y}`;
};

// Canlı veride görülen durum değerleri: worked / absent / half_day
const eqOf = (durum) => {
  if (durum === 'worked') return 1.0;
  if (durum === 'half_day') return 0.5;
  return 0.0;
};

async function run() {
  const orgs = await db.collection('organizations').listDocuments();

  for (const orgRef of orgs) {
    const [workerSnap, siteSnap, ykSnap, adSnap, paySnap] = await Promise.all([
      orgRef.collection('calisanlar').get(),
      orgRef.collection('santiyeler').get(),
      orgRef.collection('yoklama').get(),
      orgRef.collection('avans_borclar').get(),
      orgRef.collection('maas_odemeleri').get(),
    ]);

    const sites = {};
    siteSnap.forEach((d) => (sites[d.id] = Number(d.data().gunlukPrim) || 0));

    const names = {};
    workerSnap.forEach((d) => (names[d.id] = d.data().adSoyad || '(isimsiz)'));

    // --- 1. Hedef gündeki TÜM avans/borç kayıtları (silinmiş dahil) -------
    console.log('='.repeat(72));
    console.log(`ORG: ${orgRef.id}`);
    console.log(`${target} — AVANS/BORÇ KAYITLARI (silinmişler dahil)`);
    console.log('='.repeat(72));

    const gun = [];
    adSnap.forEach((doc) => {
      const x = doc.data();
      if (dkey(x.islemTarihi) !== target) return;
      gun.push({ id: doc.id, ...x });
    });

    if (gun.length === 0) {
      console.log('  (bu tarihte kayıt yok)\n');
    } else {
      const perWorker = {};
      gun.forEach((g) => (perWorker[g.calisanId] = perWorker[g.calisanId] || []).push(g));

      for (const [wid, list] of Object.entries(perWorker)) {
        console.log(`\n  ${names[wid] || wid}`);
        list.forEach((g) => {
          const durum = g.silinmeTarihi ? `SİLİNMİŞ(${fmt(g.silinmeTarihi)})` : 'AKTİF';
          console.log(
            `    [${String(g.tur).padEnd(7)}] ${TL(g.tutar).padStart(13)}  ${durum.padEnd(22)}` +
              ` giriş:${fmt(g.olusturulmaTarihi)}` +
              (g.not ? `  not:${g.not}` : '')
          );
        });
      }
      console.log('');
    }

    // --- 2. Tüm DB'de kalan aktif 'debt' kayıtları ------------------------
    const kalanBorc = [];
    adSnap.forEach((doc) => {
      const x = doc.data();
      if (x.tur !== 'debt') return;
      if (x.silinmeTarihi) return;
      kalanBorc.push({ id: doc.id, ...x });
    });

    console.log('-'.repeat(72));
    console.log(`AKTİF 'debt' (BORÇ) KAYITLARI — TÜM TARİHLER: ${kalanBorc.length} adet`);
    console.log("  (canlı kod bunları maaşa EKLİYOR; yeni kod tamamen yok sayacak)");
    console.log('-'.repeat(72));
    let borcToplam = 0;
    kalanBorc
      .sort((a, b) => String(dkey(a.islemTarihi)).localeCompare(String(dkey(b.islemTarihi))))
      .forEach((b) => {
        borcToplam += Number(b.tutar) || 0;
        console.log(
          `  ${fmt(b.islemTarihi)}  ${(names[b.calisanId] || b.calisanId).padEnd(24)} ${TL(
            b.tutar
          ).padStart(13)}` + (b.not ? `  not:${b.not}` : '')
        );
      });
    console.log(`  TOPLAM: ${TL(borcToplam)}\n`);

    // --- 3. Her çalışan için bakiye ---------------------------------------
    const byWorker = (snap, field) => {
      const m = {};
      snap.forEach((d) => {
        const x = d.data();
        if (x.silinmeTarihi) return;
        (m[x[field]] = m[x[field]] || []).push(x);
      });
      return m;
    };
    const yk = byWorker(ykSnap, 'calisanId');
    const ad = byWorker(adSnap, 'calisanId');
    const pay = byWorker(paySnap, 'calisanId');

    const rows = [];
    workerSnap.forEach((d) => {
      const w = d.data();
      if (w.silinmeTarihi) return;
      const id = d.id;
      const wage = Number(w.gunlukUcret) || 0;
      const bonus = w.primAliyor !== false;

      const gross = (yk[id] || []).reduce((s, a) => {
        const eq = eqOf(a.durum);
        const p = bonus && a.santiyeId && sites[a.santiyeId] > 0 ? sites[a.santiyeId] * eq : 0;
        return s + eq * wage + p;
      }, 0);

      const ads = ad[id] || [];
      const adv = ads.filter((x) => x.tur === 'advance').reduce((s, x) => s + (Number(x.tutar) || 0), 0);
      const debt = ads.filter((x) => x.tur === 'debt').reduce((s, x) => s + (Number(x.tutar) || 0), 0);
      const paid = (pay[id] || []).reduce((s, x) => s + (Number(x.tutar) || 0), 0);

      // hedef gündeki dönüşümün etkisi
      const gunAdv = ads
        .filter((x) => x.tur === 'advance' && dkey(x.islemTarihi) === target)
        .reduce((s, x) => s + (Number(x.tutar) || 0), 0);

      const netCanli = gross + debt - adv - paid; // canlı kod
      const netYeni = gross - adv - paid; // yeni kod (debt yok sayılır)

      if (Math.abs(netCanli) < 0.005 && gunAdv === 0 && debt === 0) return;
      rows.push({ ad: names[id], netCanli, netYeni, gunAdv, debt, adv, paid, gross });
    });

    rows.sort((a, b) => a.netCanli - b.netCanli);

    console.log('-'.repeat(72));
    console.log('ÇALIŞAN BAKİYELERİ  (net = hakediş + borç − avans − ödenen)');
    console.log('-'.repeat(72));
    console.log(
      `  ${'ÇALIŞAN'.padEnd(24)}${'CANLI NET'.padStart(14)}${'YENİ KOD NET'.padStart(15)}${`${target} AVANS`.padStart(15)}`
    );
    rows.forEach((r) => {
      const flag = r.netCanli < -0.005 ? '  ← EKSİ' : '';
      console.log(
        `  ${r.ad.padEnd(24)}${TL(r.netCanli).padStart(14)}${TL(r.netYeni).padStart(15)}${
          r.gunAdv ? TL(r.gunAdv).padStart(15) : '-'.padStart(15)
        }${flag}`
      );
    });

    const eksi = rows.filter((r) => r.netCanli < -0.005);
    console.log(`\n  Eksi bakiyeli çalışan: ${eksi.length} / ${rows.length}`);
    console.log(`  Eksi toplamı        : ${TL(eksi.reduce((s, r) => s + r.netCanli, 0))}\n`);
  }
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
