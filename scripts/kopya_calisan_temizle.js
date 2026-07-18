// Kopya çalışan temizleme — yanlışlıkla oluşmuş boş bir "Abdullah Akbaş" kaydını
// güvenle kaldırır ve üstünde takılı kalan puantajı gerçek çalışana taşır.
//
// NE YAPAR:
//   1) Kopya çalışana bağlı SİLİNMEMİŞ yoklama kayıtlarını gerçek çalışana taşır
//      (calisanId değişir; gün gerçek kişinin devreden bakiyesine yansır).
//      Gerçek çalışanda aynı gün zaten varsa (workerId+workDate benzersiz kısıtı)
//      o günü ATLAR.
//   2) Kopya çalışanı SOFT-DELETE eder (silinmeTarihi + senkronSurumu+1).
//
// NEDEN BÖYLE: Canlıda hard delete YASAK — pull sync canlı snapshot dinlediği
// için silinen doküman telefona geri yazılır. Çakışmayı yalnızca senkronSurumu
// belirler (telefon: uzak surum >= yerel ise uygular). Bu yüzden her yazımda
// senkronSurumu+1 ve script'e özel cihazId veriyoruz (echo sanılmasın).
//
// KULLANIM:
//   node scripts/kopya_calisan_temizle.js            # KURU ÇALIŞMA (hiçbir şey yazmaz)
//   node scripts/kopya_calisan_temizle.js --apply    # Gerçekten uygular
//
// Service account: proje kökünde serviceAccount.json veya SERVICE_ACCOUNT_PATH.

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

// ---- HEDEF (Abdullah Akbaş kopyası) ------------------------------------
const ORG = 'St4QMcJf9ccsRbac4CM6S01gjvn1';
const DUP_WORKER = 'a48e6931-7b70-4a88-828b-086f651a3dbc'; // silinecek boş kopya
const REAL_WORKER = '8fab16f4-6d90-4ada-935d-d623f88fbb63'; // gerçek çalışan
const ACTOR = 'admin-cleanup-script'; // cihazId + sonDegistiren

// Güvenlik eşiği: kopyada bundan fazla yoklama ya da herhangi bir ödeme varsa
// yanlış id'ye bakıyor olabiliriz — DURDUR.
const MAX_ATT_ON_DUP = 5;

const APPLY = process.argv.includes('--apply');

const saPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');
if (!fs.existsSync(saPath)) {
  console.error(`Service account JSON bulunamadı: ${saPath}`);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(require(saPath)) });
const db = admin.firestore();

const d10 = (v) => String(v || '').slice(0, 10);
const nowIso = () => new Date().toISOString();
const bump = (v) => (Number(v) || 0) + 1;
const norm = (s) => String(s || '').toLocaleLowerCase('tr');

function die(code, msg) {
  console.error(`\n⛔ DURDU: ${msg}`);
  process.exit(code);
}

async function main() {
  const orgRef = db.collection('organizations').doc(ORG);

  console.log(`Mod: ${APPLY ? '*** UYGULA (--apply) ***' : 'KURU ÇALIŞMA (yazma yok)'}`);
  console.log(`Org: ${ORG}\n`);

  // --- Çalışanları doğrula ---
  const [dupSnap, realSnap] = await Promise.all([
    orgRef.collection('calisanlar').doc(DUP_WORKER).get(),
    orgRef.collection('calisanlar').doc(REAL_WORKER).get(),
  ]);
  if (!dupSnap.exists) die(2, `Kopya çalışan bulunamadı: ${DUP_WORKER}`);
  if (!realSnap.exists) die(2, `Gerçek çalışan bulunamadı: ${REAL_WORKER}`);
  const dup = dupSnap.data();
  const real = realSnap.data();

  console.log(`Kopya  : "${dup.adSoyad}"  (${DUP_WORKER})`);
  console.log(`         silinme=${dup.silinmeTarihi || '—'}  surum=${dup.senkronSurumu}`);
  console.log(`Gerçek : "${real.adSoyad}"  (${REAL_WORKER})`);
  console.log(`         silinme=${real.silinmeTarihi || '—'}  surum=${real.senkronSurumu}`);

  // Güvenlik: adlar birbirine benzemeli (aynı kişi olduğundan emin ol)
  if (!(norm(dup.adSoyad).includes('abdullah') || norm(dup.adSoyad).includes('akba'))) {
    die(3, `Kopya çalışanın adı beklenenle uyuşmuyor ("${dup.adSoyad}"). Yanlış id olabilir.`);
  }
  if (dup.silinmeTarihi) {
    console.log('\nℹ Kopya zaten silinmiş görünüyor; yine de takılı kayıt taşıma kontrolü yapılıyor.');
  }

  // --- Kopyaya bağlı TÜM kayıtları tara ---
  const cols = ['yoklama', 'avans_borclar', 'maas_odemeleri', 'maas_ozetleri'];
  const attached = {};
  for (const c of cols) {
    const qs = await orgRef.collection(c).where('calisanId', '==', DUP_WORKER).get();
    attached[c] = [];
    qs.forEach((d) => attached[c].push({ id: d.id, ...d.data() }));
  }
  console.log('\nKopyaya bağlı kayıtlar:');
  for (const c of cols) {
    const alive = attached[c].filter((x) => !x.silinmeTarihi).length;
    console.log(`  ${c.padEnd(16)}: ${attached[c].length} (silinmemiş ${alive})`);
  }

  // Güvenlik: kopyada ödeme/avans/borç/özet OLMAMALI
  const risky = ['avans_borclar', 'maas_odemeleri', 'maas_ozetleri']
    .flatMap((c) => attached[c].filter((x) => !x.silinmeTarihi).map((x) => ({ c, x })));
  if (risky.length) {
    console.error('\n⚠ Kopyada beklenmeyen (avans/borç/ödeme/özet) SİLİNMEMİŞ kayıt var:');
    risky.forEach(({ c, x }) => console.error(`   [${c}] ${x.id}`, JSON.stringify(x).slice(0, 200)));
    die(4, 'Kopya beklendiği gibi boş değil. Elle incele; script hiçbir şey yazmadı.');
  }

  const dupAtt = attached['yoklama'].filter((x) => !x.silinmeTarihi);
  if (dupAtt.length > MAX_ATT_ON_DUP) {
    die(5, `Kopyada ${dupAtt.length} yoklama var (eşik ${MAX_ATT_ON_DUP}). Bu gerçek bir çalışan olabilir — güvenlik için durdu.`);
  }

  // --- Gerçek çalışanın gün kümesi (unique çakışma kontrolü) ---
  const realAttSnap = await orgRef.collection('yoklama').where('calisanId', '==', REAL_WORKER).get();
  const realDays = new Set();
  realAttSnap.forEach((d) => {
    const x = d.data();
    if (!x.silinmeTarihi) realDays.add(d10(x.tarih));
  });

  // --- Taşıma planı ---
  console.log(`\nTaşınacak yoklama (silinmemiş): ${dupAtt.length}`);
  const moves = [];
  for (const a of dupAtt) {
    const g = d10(a.tarih);
    if (realDays.has(g)) {
      console.log(`  ${g}  ${a.durum}  → ATLA (gerçek çalışanda ${g} zaten var; taşınırsa unique çakışır)`);
    } else {
      console.log(`  ${g}  ${a.durum}  santiye=${a.santiyeId || '—'}  → TAŞI  (surum ${a.senkronSurumu}→${bump(a.senkronSurumu)})`);
      moves.push(a);
    }
  }

  console.log(`\nKopya çalışan SOFT-DELETE edilecek: surum ${dup.senkronSurumu}→${bump(dup.senkronSurumu)}, silinmeTarihi=<şimdi>`);

  if (!APPLY) {
    console.log('\n[KURU ÇALIŞMA] Hiçbir şey yazılmadı.');
    console.log('Uygulamak için: node scripts/kopya_calisan_temizle.js --apply');
    return;
  }

  // --- Uygula ---
  console.log('\n--apply verildi, yazılıyor...');
  for (const a of moves) {
    await orgRef.collection('yoklama').doc(a.id).update({
      calisanId: REAL_WORKER,
      guncellenmeTarihi: nowIso(),
      sonDegistiren: ACTOR,
      cihazId: ACTOR,
      senkronSurumu: bump(a.senkronSurumu),
    });
    console.log(`  ✓ yoklama ${d10(a.tarih)} gerçek çalışana taşındı (${a.id})`);
  }
  await orgRef.collection('calisanlar').doc(DUP_WORKER).update({
    silinmeTarihi: nowIso(),
    aktifMi: false,
    guncellenmeTarihi: nowIso(),
    sonDegistiren: ACTOR,
    cihazId: ACTOR,
    senkronSurumu: bump(dup.senkronSurumu),
  });
  console.log(`  ✓ kopya çalışan soft-delete edildi (${DUP_WORKER})`);

  console.log('\nBitti. Telefonlar senkron olduğunda:');
  console.log(`  • Taşınan gün(ler) "${real.adSoyad}" hesabında devreden bakiye olarak görünecek.`);
  console.log('  • Kopya çalışan listeden kaybolacak.');
  console.log('  (senkronSurumu+1 sayesinde değişiklikler telefon verisini yener.)');
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
