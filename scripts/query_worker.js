// Bir çalışanın avans/borç ve maaş ödemelerini Firestore'dan listeler.
// Kullanım:
//   node query_worker.js <workerId> [orgId]
// Service account anahtarı: proje kökünde serviceAccount.json
// veya SERVICE_ACCOUNT_PATH env değişkeni ile yol verilebilir.

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');

if (!fs.existsSync(serviceAccountPath)) {
  console.error(`Service account JSON bulunamadı: ${serviceAccountPath}`);
  console.error('Firebase Console → Project Settings → Service Accounts → "Generate new private key"');
  console.error('İndirdiğin dosyayı proje köküne "serviceAccount.json" olarak koy.');
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const db = admin.firestore();

const TL = (n) =>
  `${(Number(n) || 0).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} ₺`;

const fmtDate = (iso) => {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d)) return String(iso);
  return d.toLocaleDateString('tr-TR');
};

const sum = (arr) => arr.reduce((s, x) => s + (Number(x.tutar) || 0), 0);

async function findOrgIdsContainingWorker(workerId) {
  const orgs = await db.collection('organizations').listDocuments();
  const matched = [];
  for (const orgRef of orgs) {
    const worker = await orgRef.collection('calisanlar').doc(workerId).get();
    if (worker.exists) matched.push(orgRef.id);
  }
  return matched;
}

async function run() {
  const workerId = process.argv[2];
  let orgId = process.argv[3];

  if (!workerId) {
    console.error('Kullanım: node query_worker.js <workerId> [orgId]');
    process.exit(1);
  }

  if (!orgId) {
    console.log('OrgId verilmedi, organizations koleksiyonu taranıyor...');
    const matches = await findOrgIdsContainingWorker(workerId);
    if (matches.length === 0) {
      console.error(`Bu workerId hiçbir organizasyonda bulunamadı: ${workerId}`);
      process.exit(2);
    }
    if (matches.length > 1) {
      console.error(`Birden fazla org bulundu: ${matches.join(', ')}`);
      console.error('Lütfen orgId\'yi 2. argüman olarak ver.');
      process.exit(3);
    }
    orgId = matches[0];
    console.log(`Bulundu → orgId = ${orgId}\n`);
  }

  const orgRef = db.collection('organizations').doc(orgId);

  // Çalışan
  const workerSnap = await orgRef.collection('calisanlar').doc(workerId).get();
  if (!workerSnap.exists) {
    console.error(`calisanlar/${workerId} bulunamadı (org=${orgId}).`);
    process.exit(4);
  }
  const w = workerSnap.data();
  console.log('================================================');
  console.log(`ÇALIŞAN : ${w.adSoyad}   (id=${workerId})`);
  console.log(`Günlük ücret: ${TL(w.gunlukUcret)}    Aktif: ${w.aktifMi}`);
  if (w.silinmeTarihi) console.log(`!! Silinmiş: ${fmtDate(w.silinmeTarihi)}`);
  console.log('================================================\n');

  // Avans / Borç
  const adSnap = await orgRef
    .collection('avans_borclar')
    .where('calisanId', '==', workerId)
    .get();

  const advances = [];
  const debts = [];
  const deleted = [];
  adSnap.forEach((d) => {
    const x = { ...d.data(), _docId: d.id };
    if (x.silinmeTarihi) deleted.push(x);
    else if (x.tur === 'advance') advances.push(x);
    else if (x.tur === 'debt') debts.push(x);
    else console.warn(`  ! Bilinmeyen tur="${x.tur}" docId=${d.id}`);
  });
  advances.sort((a, b) => new Date(a.islemTarihi) - new Date(b.islemTarihi));
  debts.sort((a, b) => new Date(a.islemTarihi) - new Date(b.islemTarihi));

  console.log(`--- AVANS  (${advances.length} kayıt, toplam ${TL(sum(advances))}) ---`);
  advances.forEach((x) => {
    console.log(
      `  ${fmtDate(x.islemTarihi).padEnd(11)}  ${TL(x.tutar).padStart(14)}  mahsupAy=${x.mahsupAy || '-'}${x.not ? '   — ' + x.not : ''}`
    );
  });

  console.log(`\n--- BORÇ   (${debts.length} kayıt, toplam ${TL(sum(debts))}) ---`);
  debts.forEach((x) => {
    console.log(
      `  ${fmtDate(x.islemTarihi).padEnd(11)}  ${TL(x.tutar).padStart(14)}  mahsupAy=${x.mahsupAy || '-'}${x.not ? '   — ' + x.not : ''}`
    );
  });

  if (deleted.length) {
    console.log(`\n--- SİLİNMİŞ AVANS/BORÇ (${deleted.length}) ---`);
    deleted.forEach((x) => {
      console.log(
        `  [${x.tur}] ${fmtDate(x.islemTarihi)}  ${TL(x.tutar)}   silindi=${fmtDate(x.silinmeTarihi)}`
      );
    });
  }

  // Maaş ödemeleri
  const paySnap = await orgRef
    .collection('maas_odemeleri')
    .where('calisanId', '==', workerId)
    .get();

  const payments = [];
  const paymentsDeleted = [];
  paySnap.forEach((d) => {
    const x = { ...d.data(), _docId: d.id };
    if (x.silinmeTarihi) paymentsDeleted.push(x);
    else payments.push(x);
  });
  payments.sort((a, b) => new Date(a.odemeTarihi) - new Date(b.odemeTarihi));

  console.log(
    `\n--- MAAŞ ÖDEMELERİ (${payments.length} kayıt, toplam ${TL(sum(payments))}) ---`
  );
  payments.forEach((x) => {
    console.log(
      `  Ödeme: ${fmtDate(x.odemeTarihi).padEnd(11)}  Dönem: ${fmtDate(x.donemBaslangici)} → ${fmtDate(x.donemBitisi)}   ${TL(x.tutar)}`
    );
  });
  if (paymentsDeleted.length) {
    console.log(`\n--- SİLİNMİŞ ÖDEMELER (${paymentsDeleted.length}) ---`);
    paymentsDeleted.forEach((x) => {
      console.log(
        `  ${fmtDate(x.odemeTarihi)}  ${TL(x.tutar)}   silindi=${fmtDate(x.silinmeTarihi)}`
      );
    });
  }

  // Özet
  console.log('\n=== ÖZET ===');
  console.log(`Avans toplamı : ${TL(sum(advances))}`);
  console.log(`Borç toplamı  : ${TL(sum(debts))}`);
  console.log(`Ödenen maaş   : ${TL(sum(payments))}`);
  console.log(`Net (avans+borç − ödeme) : ${TL(sum(advances) + sum(debts) - sum(payments))}`);
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
