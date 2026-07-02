// İsme veya id parçasına göre çalışan ara.
// Kullanım:
//   node find_worker.js <arama-metni>
//   örn: node find_worker.js "çoşkun"

const admin = require('firebase-admin');
const path = require('path');

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

const db = admin.firestore();

const normalize = (s) =>
  String(s || '')
    .toLocaleLowerCase('tr-TR')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');

async function run() {
  const query = process.argv[2];
  if (!query) {
    console.error('Kullanım: node find_worker.js <arama-metni>');
    process.exit(1);
  }
  const q = normalize(query);

  const orgs = await db.collection('organizations').listDocuments();
  console.log(`${orgs.length} organizasyon bulundu.\n`);

  let totalWorkers = 0;
  for (const orgRef of orgs) {
    const workers = await orgRef.collection('calisanlar').get();
    totalWorkers += workers.size;
    console.log(`── org=${orgRef.id}  (${workers.size} çalışan)`);

    const matches = [];
    workers.forEach((d) => {
      const w = d.data();
      const name = normalize(w.adSoyad);
      if (
        name.includes(q) ||
        d.id.toLowerCase().includes(q.toLowerCase())
      ) {
        matches.push({ id: d.id, ...w });
      }
    });

    if (matches.length > 0) {
      matches.forEach((m) => {
        const silinmis = m.silinmeTarihi ? ' [SİLİNMİŞ]' : '';
        const aktif = m.aktifMi === false ? ' [PASİF]' : '';
        console.log(
          `   ★ ${m.adSoyad}   id=${m.id}${silinmis}${aktif}`
        );
      });
    }
  }
  console.log(`\nToplam ${totalWorkers} çalışan tarandı.`);
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
