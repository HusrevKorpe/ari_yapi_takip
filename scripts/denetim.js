// Çalışan alacak denetimi — uygulamanın "Maaş Ver" ekranında görünen tutar ile
// tüm geçmiş kayıtlardan hesaplanan gerçek alacağı her çalışan için karşılaştırır.
//
// "Ekran" : son ödemenin dönem bitişinden bugüne yapılan hesap
//           (workerPayrollProvider mantığı).
// "Gerçek": tüm geçmiş — gün karşılığı × yevmiye + şantiye primi
//           + işveren borcu − avans − ödenen (workerLifetimeStats mantığı).
// Fark ≠ 0 ise ödenmiş döneme sonradan kayıt girilmiş demektir.
//
// Kullanım:
//   node denetim.js            (tabloyu terminale yazar)
//   node denetim.js --save     (Masaüstüne txt + pdf raporu da kaydeder)
//
// Service account: proje kökünde serviceAccount.json
// veya SERVICE_ACCOUNT_PATH env değişkeni.

const admin = require('firebase-admin');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

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

const TL = (n) =>
  `${(Number(n) || 0).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} TL`;

const dayOnly = (iso) => {
  const d = new Date(iso);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
};

// PayrollCalculator.workedEquivalent ile aynı: worked=1, half_day=0.5, diğer=0
const eqOf = (durum) =>
  durum === 'worked' ? 1.0 : durum === 'half_day' || durum === 'halfDay' ? 0.5 : 0;

async function auditOrg(orgRef) {
  const today = dayOnly(new Date().toISOString());

  const [workerSnap, siteSnap, ykSnap, adSnap, paySnap] = await Promise.all([
    orgRef.collection('calisanlar').get(),
    orgRef.collection('santiyeler').get(),
    orgRef.collection('yoklama').get(),
    orgRef.collection('avans_borclar').get(),
    orgRef.collection('maas_odemeleri').get(),
  ]);

  const sites = {};
  siteSnap.forEach((d) => {
    sites[d.id] = { prim: Number(d.data().gunlukPrim) || 0 };
  });

  const byWorker = (snap, field) => {
    const m = {};
    snap.forEach((d) => {
      const x = d.data();
      if (x.silinmeTarihi) return; // uygulama gibi: silinmişler hariç
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
    // primAliyor alanı yoksa uygulama true varsayar (pull_sync_service fallback)
    const receivesBonus = w.primAliyor !== false;

    const att = (yk[id] || []).map((x) => ({ ...x, _d: dayOnly(x.tarih) }));
    const ads = ad[id] || [];
    const pays = pay[id] || [];

    const primOf = (a) => {
      if (!receivesBonus) return 0;
      const eq = eqOf(a.durum);
      if (eq === 0 || !a.santiyeId) return 0;
      const s = sites[a.santiyeId];
      return s && s.prim > 0 ? s.prim * eq : 0;
    };

    // Gerçek alacak (tüm geçmiş)
    const grossAll = att.reduce((s, a) => s + eqOf(a.durum) * wage + primOf(a), 0);
    const advAll = ads
      .filter((x) => x.tur === 'advance')
      .reduce((s, x) => s + (Number(x.tutar) || 0), 0);
    const debtAll = ads
      .filter((x) => x.tur === 'debt')
      .reduce((s, x) => s + (Number(x.tutar) || 0), 0);
    const paidAll = pays.reduce((s, x) => s + (Number(x.tutar) || 0), 0);
    const real = grossAll + debtAll - advAll - paidAll;

    // Ekran değeri (son ödeme sonrası dönem)
    let ps;
    if (pays.length) {
      const lastEnd = pays.map((x) => dayOnly(x.donemBitisi)).sort((a, b) => b - a)[0];
      ps = new Date(lastEnd.getFullYear(), lastEnd.getMonth(), lastEnd.getDate() + 1);
    } else {
      const created = w.olusturulmaTarihi ? dayOnly(w.olusturulmaTarihi) : today;
      const earliest = att.length ? att.map((a) => a._d).sort((a, b) => a - b)[0] : null;
      ps = earliest && earliest < created ? earliest : created;
    }

    let screen = 0;
    if (ps <= today) {
      const inR = (t) => t >= ps.getTime() && t <= today.getTime();
      const attR = att.filter((a) => inR(a._d.getTime()));
      const gross = attR.reduce((s, a) => s + eqOf(a.durum) * wage + primOf(a), 0);
      const advR = ads
        .filter((x) => x.tur === 'advance' && inR(dayOnly(x.islemTarihi).getTime()))
        .reduce((s, x) => s + (Number(x.tutar) || 0), 0);
      const debtR = ads
        .filter((x) => x.tur === 'debt' && inR(dayOnly(x.islemTarihi).getTime()))
        .reduce((s, x) => s + (Number(x.tutar) || 0), 0);
      screen = gross - (advR - debtR);
    }

    rows.push({ ad: w.adSoyad, aktif: w.aktifMi !== false, screen, real, diff: real - screen });
  });

  return rows;
}

function buildReport(orgId, rows) {
  const degisenler = rows
    .filter((r) => Math.abs(r.diff) >= 0.01)
    .sort((a, b) => b.diff - a.diff);
  const toplamFark = degisenler.reduce((s, r) => s + r.diff, 0);

  const L = [];
  const P = (s = '') => L.push(s);

  P('================================================================');
  P('ÇALIŞAN ALACAK DENETİM RAPORU');
  P(`Rapor tarihi: ${new Date().toLocaleDateString('tr-TR')}`);
  P(`Organizasyon: ${orgId}`);
  P('================================================================');
  P('');
  P(`Taranan çalışan          : ${rows.length}`);
  P(`Ekran = gerçek (tutarlı) : ${rows.length - degisenler.length}`);
  P(`Farklı görünen           : ${degisenler.length}`);
  P(`Toplam görünmeyen alacak : ${TL(toplamFark)}`);
  P('');
  P('Çalışan                       Ekranda        Gerçek          Fark');
  P('----------------------------------------------------------------');
  const sorted = [...rows].sort((a, b) => {
    const da = Math.abs(b.diff) - Math.abs(a.diff);
    if (Math.abs(da) > 0.001) return da;
    return a.ad.localeCompare(b.ad, 'tr');
  });
  sorted.forEach((r) => {
    const name = r.ad + (r.aktif ? '' : ' (ayrıldı)');
    const flag = Math.abs(r.diff) >= 0.01 ? '  ← FARK' : '';
    P(
      `${name.padEnd(26)}${TL(r.screen).padStart(14)}${TL(r.real).padStart(15)}${TL(r.diff).padStart(14)}${flag}`
    );
  });
  P('----------------------------------------------------------------');
  P('');
  P('Ekranda : uygulamanın "Maaş Ver" ekranının bugün önerdiği tutar.');
  P('Gerçek  : tüm geçmiş kayıtlardan hesaplanan alacak (çalışan detay');
  P('          sayfasındaki genel bakiye ile aynı formül).');
  P('Eksi değer: çalışan hakedişinden fazla almış (şirket alacaklı).');
  P('');
  P('Fark ≠ 0 ise: ödeme yapıldıktan sonra o ödemenin dönemi içine');
  P('puantaj/avans/borç girilmiş demektir. Kayıtlar kaybolmaz; bu');
  P('rapor gizli kalan tutarı gösterir.');

  return L.join('\n');
}

async function run() {
  const saveFlag = process.argv.includes('--save');

  const orgs = await db.collection('organizations').listDocuments();
  for (const orgRef of orgs) {
    const rows = await auditOrg(orgRef);
    if (rows.length === 0) continue;
    const report = buildReport(orgRef.id, rows);
    console.log(report);

    if (saveFlag) {
      const desktop = path.join(os.homedir(), 'Desktop');
      const stamp = new Date().toISOString().slice(0, 10);
      const base = `denetim_${stamp}`;
      const txtPath = path.join(desktop, `${base}.txt`);
      const pdfPath = path.join(desktop, `${base}.pdf`);
      fs.writeFileSync(txtPath, report, 'utf8');
      console.log(`\n→ Yazıldı: ${txtPath}`);
      try {
        execSync(`/usr/sbin/cupsfilter "${txtPath}" > "${pdfPath}" 2>/dev/null`);
        console.log(`→ Yazıldı: ${pdfPath}`);
      } catch (e) {
        console.error(`(PDF üretilemedi: ${e.message})`);
      }
    }
  }
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
