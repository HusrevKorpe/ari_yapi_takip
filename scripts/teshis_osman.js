// SALT-OKUNUR teşhis: Osman Bilgiç'e girilen 10.300 TL'lik kayıt Firestore'da
// var mı; hangi cihazlar en son ne zaman senkron yazmış?
// Hiçbir şey YAZMAZ. node scripts/teshis_osman.js

const admin = require('firebase-admin');
const path = require('path');

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});
const db = admin.firestore();
const auth = admin.auth();

const PARA_KOLEKSIYONLARI = [
  'maas_odemeleri',
  'avans_borclar',
  'giderler',
  'gelirler',
  'ortak_odemeleri',
];
const TUM_KOLEKSIYONLAR = [
  'calisanlar', 'santiyeler', 'yoklama', 'giderler', 'gelirler',
  'ortak_odemeleri', 'avans_borclar', 'maas_odemeleri', 'maas_ozetleri',
  'santiye_notlari', 'islem_kayitlari',
];

const ARANAN_TUTARLAR = [10300, 10300.0, 1030000]; // TL ve olası kuruş
const ARANAN_ISIM = 'osman';

const normalize = (s) =>
  String(s || '')
    .toLocaleLowerCase('tr-TR')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');

const dt = (v) => {
  if (!v) return '—';
  if (v.toDate) return v.toDate().toISOString();
  return String(v);
};

async function run() {
  // 1) Kullanıcılar: kim hangi org'a bağlı?
  console.log('=== KULLANICILAR ===');
  const authUsers = await auth.listUsers();
  const usersSnap = await db.collection('users').get();
  const userDocs = new Map();
  usersSnap.forEach((d) => userDocs.set(d.id, d.data()));
  for (const u of authUsers.users) {
    const ud = userDocs.get(u.uid) || {};
    console.log(
      `  ${u.email || u.phoneNumber || '?'}  uid=${u.uid}\n` +
      `    org=${ud.organizationId || '—'}  rol=${ud.role || '—'}  ` +
      `sonGiris=${u.metadata.lastSignInTime || '—'}`
    );
  }

  const orgs = await db.collection('organizations').listDocuments();
  console.log(`\n=== ${orgs.length} ORGANIZASYON ===`);

  for (const orgRef of orgs) {
    console.log(`\n────────── org=${orgRef.id} ──────────`);

    // 2) Osman'ı bul
    const workers = await orgRef.collection('calisanlar').get();
    const osmanIds = [];
    workers.forEach((d) => {
      const w = d.data();
      if (normalize(w.adSoyad).includes(ARANAN_ISIM)) {
        osmanIds.push(d.id);
        console.log(
          `  ★ ÇALIŞAN: ${w.adSoyad}  id=${d.id}` +
          `${w.silinmeTarihi ? ' [SİLİNMİŞ]' : ''}` +
          `${w.aktifMi === false ? ' [PASİF]' : ''}`
        );
      }
    });
    if (osmanIds.length === 0) {
      console.log(`  (bu org'da "${ARANAN_ISIM}" isimli çalışan yok, ${workers.size} çalışan tarandı)`);
    }

    // 3) Parasal kayıtlar: Osman'a ait HERŞEY + tutarı 10300 olan HERŞEY
    for (const col of PARA_KOLEKSIYONLARI) {
      const snap = await orgRef.collection(col).get();
      snap.forEach((d) => {
        const r = d.data();
        const osmanKaydi = osmanIds.includes(r.calisanId);
        const tutarUyusuyor = ARANAN_TUTARLAR.includes(Number(r.tutar));
        if (osmanKaydi || tutarUyusuyor) {
          console.log(
            `  [${col}] id=${d.id}\n` +
            `     tutar=${r.tutar}  calisanId=${r.calisanId || '—'}  tarih=${r.tarih || '—'}\n` +
            `     tur=${r.tur || r.kategori || '—'}  aciklama=${(r.aciklama || r.not || '—').toString().slice(0, 60)}\n` +
            `     cihazId=${r.cihazId || '—'}  sonDegistiren=${r.sonDegistiren || '—'}\n` +
            `     olusturulma=${r.olusturulmaTarihi || '—'}  _syncedAt=${r._syncedAt || '—'}` +
            `${r.silinmeTarihi ? `  [SİLİNMİŞ ${r.silinmeTarihi}]` : ''}`
          );
        }
      });
    }

    // 4) İşlem kayıtları (audit log) — son 7 günde osman/10300 izi
    try {
      const audit = await orgRef.collection('islem_kayitlari').get();
      let auditHits = 0;
      audit.forEach((d) => {
        const r = d.data();
        const blob = normalize(JSON.stringify(r));
        if (blob.includes(ARANAN_ISIM) || blob.includes('10300') || blob.includes('10.300')) {
          auditHits++;
          console.log(`  [AUDIT] id=${d.id}  ${JSON.stringify(r).slice(0, 300)}`);
        }
      });
      console.log(`  (islem_kayitlari: ${audit.size} kayıt, ${auditHits} eşleşme)`);
    } catch (e) {
      console.log(`  (islem_kayitlari okunamadı: ${e.message})`);
    }

    // 5) Cihaz bazında en son senkron yazımı — müşterinin cihazı en son ne
    //    zaman BAŞARILI push yaptı?
    const deviceLast = new Map(); // cihazId -> {syncedAt, col, docId}
    let totalDocs = 0;
    for (const col of TUM_KOLEKSIYONLAR) {
      const snap = await orgRef.collection(col).get().catch(() => null);
      if (!snap) continue;
      totalDocs += snap.size;
      snap.forEach((d) => {
        const r = d.data();
        const dev = r.cihazId || r.deviceId || '(cihazsız)';
        const at = r._syncedAt || '';
        const prev = deviceLast.get(dev);
        if (!prev || String(at) > String(prev.syncedAt)) {
          deviceLast.set(dev, { syncedAt: at, col, docId: d.id, kim: r.sonDegistiren || '—' });
        }
      });
    }
    console.log(`  --- Cihaz bazında son başarılı senkron (${totalDocs} doküman tarandı) ---`);
    for (const [dev, info] of deviceLast) {
      console.log(
        `    cihaz=${dev}  son=${dt(info.syncedAt)}  (${info.col}/${info.docId})  kim=${info.kim}`
      );
    }
  }
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
