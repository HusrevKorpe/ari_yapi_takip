// Belirli bir günde BORÇ (tur='debt') girilen çalışanları listeler.
//
// "Girilen" iki farklı tarih olabilir:
//   islemTarihi        = borcun kayda geçirilen iş tarihi (kullanıcının seçtiği gün)
//   olusturulmaTarihi  = kaydın cihazda fiilen oluşturulduğu an (offline-first)
// Bu script varsayılan olarak islemTarihi'ne göre eşleştirir, ikisini de gösterir.
//
// Kullanım:
//   node borc_gunu.js               → 4 Mayıs (her yıl) borçları
//   node borc_gunu.js 05-04         → aynı (AA-GG)
//   node borc_gunu.js 2026-05-04    → sadece 2026-05-04
//   node borc_gunu.js 05-04 --olusturulma   → islemTarihi yerine olusturulmaTarihi'ne göre
//
// Service account: proje kökünde serviceAccount.json (veya SERVICE_ACCOUNT_PATH).

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

// ---- argümanlar ----
const args = process.argv.slice(2);
const useOlusturulma = args.includes('--olusturulma');
const dateArg = args.find((a) => !a.startsWith('--')) || '05-04';

// AA-GG veya YYYY-AA-GG kabul et
let wantYear = null;
let wantMonth; // 1-12
let wantDay;
const parts = dateArg.split('-').map((p) => parseInt(p, 10));
if (parts.length === 3) {
  [wantYear, wantMonth, wantDay] = parts;
} else if (parts.length === 2) {
  [wantMonth, wantDay] = parts;
} else {
  console.error(`Tarih formatı hatalı: "${dateArg}". Örn: 05-04 veya 2026-05-04`);
  process.exit(1);
}

const dateField = useOlusturulma ? 'olusturulmaTarihi' : 'islemTarihi';

const TL = (n) =>
  `${(Number(n) || 0).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} TL`;

const fmtDate = (iso) => {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d)) return String(iso);
  return d.toLocaleDateString('tr-TR');
};

// Tarih eşleşmesi: yerel gün bileşenleri (diğer scriptlerle tutarlı)
const matches = (iso) => {
  if (!iso) return false;
  const d = new Date(iso);
  if (isNaN(d)) return false;
  if (d.getMonth() + 1 !== wantMonth) return false;
  if (d.getDate() !== wantDay) return false;
  if (wantYear !== null && d.getFullYear() !== wantYear) return false;
  return true;
};

async function run() {
  const orgs = await db.collection('organizations').listDocuments();
  const hits = [];

  for (const orgRef of orgs) {
    const [workerSnap, adSnap] = await Promise.all([
      orgRef.collection('calisanlar').get(),
      orgRef.collection('avans_borclar').get(),
    ]);

    const names = {};
    workerSnap.forEach((d) => {
      names[d.id] = d.data().adSoyad || '(isimsiz)';
    });

    adSnap.forEach((doc) => {
      const x = doc.data();
      if (x.tur !== 'debt') return;
      if (!matches(x[dateField])) return;
      hits.push({
        org: orgRef.id,
        id: doc.id,
        ad: names[x.calisanId] || `(bilinmeyen: ${x.calisanId})`,
        tutar: Number(x.tutar) || 0,
        islemTarihi: x.islemTarihi,
        olusturulmaTarihi: x.olusturulmaTarihi,
        silinme: x.silinmeTarihi,
        not: x.not,
        mahsupAy: x.mahsupAy,
      });
    });
  }

  const etiket = wantYear
    ? `${String(wantDay).padStart(2, '0')}.${String(wantMonth).padStart(2, '0')}.${wantYear}`
    : `${String(wantDay).padStart(2, '0')}.${String(wantMonth).padStart(2, '0')} (her yıl)`;

  console.log('================================================================');
  console.log(`BORÇ GİRİLEN KİŞİLER — ${etiket}`);
  console.log(`Eşleşme alanı: ${dateField}`);
  console.log('================================================================\n');

  if (hits.length === 0) {
    console.log('Bu tarihte borç kaydı bulunamadı.');
    process.exit(0);
  }

  // isme göre sırala
  hits.sort((a, b) => a.ad.localeCompare(b.ad, 'tr'));

  let toplam = 0;
  let aktifToplam = 0;
  hits.forEach((h, i) => {
    toplam += h.tutar;
    const silindi = h.silinme ? `  [SİLİNMİŞ: ${fmtDate(h.silinme)}]` : '';
    if (!h.silinme) aktifToplam += h.tutar;
    console.log(`${String(i + 1).padStart(2)}. ${h.ad.padEnd(24)} ${TL(h.tutar).padStart(14)}${silindi}`);
    console.log(
      `    işlem: ${fmtDate(h.islemTarihi)}   giriş(cihaz): ${fmtDate(h.olusturulmaTarihi)}` +
        (h.mahsupAy ? `   mahsupAy: ${h.mahsupAy}` : '') +
        (h.not ? `   not: ${h.not}` : '')
    );
  });

  console.log('\n----------------------------------------------------------------');
  console.log(`Kayıt sayısı        : ${hits.length}`);
  const silinmisSayisi = hits.filter((h) => h.silinme).length;
  if (silinmisSayisi) {
    console.log(`  (silinmiş)        : ${silinmisSayisi}`);
    console.log(`Toplam (silinmiş dahil): ${TL(toplam)}`);
    console.log(`Toplam (aktif)         : ${TL(aktifToplam)}`);
  } else {
    console.log(`Toplam borç         : ${TL(toplam)}`);
  }
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
