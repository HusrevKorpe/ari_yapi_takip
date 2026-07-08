// SALT-OKUNUR teşhis: "veriler gelmiyor" sorununu araştırır.
// - Kaç organizasyon var? (org-forking kontrolü)
// - users/{uid}.organizationId kim nereye bağlı?
// - Auth'taki her kullanıcının users kaydı var mı?
// - Her org'da yoklama sayısı + son yazılan yoklamalar (dün/bugün odaklı)
//
// Hiçbir şey YAZMAZ. node scripts/teshis.js

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

const COLLECTIONS = [
  'calisanlar', 'santiyeler', 'yoklama', 'giderler', 'gelirler',
  'ortak_odemeleri', 'avans_borclar', 'maas_odemeleri', 'maas_ozetleri',
  'santiye_notlari',
];

const short = (s) => (s ? String(s).slice(0, 8) : '—');
const dt = (v) => {
  if (!v) return '—';
  if (typeof v === 'object' && v.toDate) return v.toDate().toISOString().slice(0, 16);
  return String(v).slice(0, 16);
};

async function run() {
  console.log('=== 1) AUTH KULLANICILARI ===');
  const authUsers = [];
  let pageToken;
  do {
    const res = await auth.listUsers(1000, pageToken);
    authUsers.push(...res.users);
    pageToken = res.pageToken;
  } while (pageToken);
  for (const u of authUsers) {
    console.log(`  uid=${short(u.uid)}  email=${u.email || '—'}  sonGiris=${u.metadata.lastSignInTime || '—'}`);
  }

  console.log('\n=== 2) users/{uid} DOKÜMANLARI (organizationId eşlemesi) ===');
  const usersSnap = await db.collection('users').get();
  const userOrg = {};
  usersSnap.forEach((d) => {
    const org = d.data().organizationId;
    userOrg[d.id] = org;
    console.log(`  users/${short(d.id)}  ->  organizationId=${org ? short(org) : '!!! YOK !!!'}  (tam: ${org || 'YOK'})`);
  });
  // Auth'ta olup users kaydı olmayanlar (org-forking / permission-denied adayı)
  const eksik = authUsers.filter((u) => !(u.uid in userOrg));
  if (eksik.length) {
    console.log('\n  ⚠️  Auth\'ta VAR ama users/{uid} kaydı YOK olan hesaplar:');
    eksik.forEach((u) => console.log(`     - ${u.email || short(u.uid)} (uid=${u.uid})`));
    console.log('     Bu hesaplar "Organizasyon yüklenemedi" ekranı görür ya da eski sürümdeyse kendi org\'una fork olmuştur.');
  }

  console.log('\n=== 3) ORGANİZASYONLAR ===');
  const orgRefs = await db.collection('organizations').listDocuments();
  console.log(`  Toplam org sayısı: ${orgRefs.length}`);
  if (orgRefs.length > 1) {
    console.log('  ⚠️  BİRDEN FAZLA ORG VAR — veri farklı org\'lara bölünmüş olabilir (forking).');
  }

  for (const orgRef of orgRefs) {
    console.log(`\n  ── organizations/${orgRef.id} ──`);
    const orgDoc = await orgRef.get();
    if (orgDoc.exists) {
      const o = orgDoc.data();
      console.log(`     ownerUid=${short(o.ownerUid)}  email=${o.email || '—'}  createdAt=${dt(o.createdAt)}`);
    }
    // Bu org'a bağlı users
    const members = Object.entries(userOrg).filter(([, org]) => org === orgRef.id).map(([uid]) => short(uid));
    console.log(`     üyeler (users.organizationId==bu org): ${members.length ? members.join(', ') : 'HİÇ YOK'}`);

    for (const c of COLLECTIONS) {
      const snap = await orgRef.collection(c).get();
      let deleted = 0;
      snap.forEach((d) => { if (d.data().silinmeTarihi) deleted++; });
      const live = snap.size - deleted;
      if (snap.size > 0) {
        console.log(`     ${c.padEnd(18)} toplam=${String(snap.size).padStart(4)}  canlı=${String(live).padStart(4)}  silinmiş=${deleted}`);
      }
    }

    // Yoklama detay: en son yazılanlar
    const yk = await orgRef.collection('yoklama').get();
    const rows = [];
    yk.forEach((d) => {
      const x = d.data();
      rows.push({
        id: d.id,
        tarih: x.tarih,
        durum: x.durum,
        olus: x.olusturulmaTarihi,
        guncel: x.guncellenmeTarihi,
        cihaz: x.cihazId,
        degistiren: x.sonDegistiren,
        silindi: !!x.silinmeTarihi,
      });
    });
    const byCreated = [...rows].sort((a, b) => String(b.olus || '').localeCompare(String(a.olus || '')));
    console.log(`     → EN SON OLUŞTURULAN 12 YOKLAMA (olusturulmaTarihi'ne göre):`);
    byCreated.slice(0, 12).forEach((r) => {
      console.log(
        `        tarih=${dt(r.tarih)}  durum=${String(r.durum).padEnd(9)}  olus=${dt(r.olus)}  cihaz=${short(r.cihaz)}  by=${short(r.degistiren)}${r.silindi ? '  [SİLİNMİŞ]' : ''}`
      );
    });

    // Cihaz bazında sayım — hangi cihaz kaç yoklama yazmış
    const cihazSay = {};
    rows.forEach((r) => { cihazSay[r.cihaz || '—'] = (cihazSay[r.cihaz || '—'] || 0) + 1; });
    console.log(`     → yoklama yazan cihazlar:`);
    Object.entries(cihazSay).sort((a, b) => b[1] - a[1]).forEach(([c, n]) => {
      console.log(`        cihaz=${short(c)}  adet=${n}`);
    });
  }

  console.log('\n=== BİTTİ ===');
}

run().then(() => process.exit(0)).catch((e) => { console.error('HATA:', e); process.exit(1); });
