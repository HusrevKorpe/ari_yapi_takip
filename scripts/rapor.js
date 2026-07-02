// Çalışan rapor scripti — isim veya ID ile çalışan bul, avans/borç ve
// maaş ödemelerini Firestore'dan çek, terminale yaz; --save ile Masaüstüne
// .txt ve .pdf raporu kaydet.
//
// Kullanım:
//   node rapor.js "ali osman"
//   node rapor.js "çoşkun"           (kısmi eşleşme yeterli)
//   node rapor.js <workerId>
//   node rapor.js "ali osman" --save (Masaüstüne txt+pdf kaydeder)
//
// Service account: proje kökünde serviceAccount.json olmalı,
// veya SERVICE_ACCOUNT_PATH env değişkeniyle yol verilir.

const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');
const os = require('os');
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
  })} ₺`;

const fmtDate = (iso) => {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d)) return String(iso);
  return d.toLocaleDateString('tr-TR');
};

const sum = (arr) => arr.reduce((s, x) => s + (Number(x.tutar) || 0), 0);

const normalize = (s) =>
  String(s || '')
    .toLocaleLowerCase('tr-TR')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// {orgId, workerId, workerDoc} döner. Birden fazla eşleşirse exit 3.
async function resolveWorker(query) {
  const isId = UUID_RE.test(query);
  const orgs = await db.collection('organizations').listDocuments();

  if (isId) {
    for (const orgRef of orgs) {
      const snap = await orgRef.collection('calisanlar').doc(query).get();
      if (snap.exists) {
        return { orgId: orgRef.id, workerId: query, workerDoc: snap.data() };
      }
    }
    console.error(`workerId bulunamadı: ${query}`);
    process.exit(2);
  }

  // İsimden ara
  const q = normalize(query);
  const matches = [];
  for (const orgRef of orgs) {
    const workers = await orgRef.collection('calisanlar').get();
    workers.forEach((d) => {
      const w = d.data();
      if (normalize(w.adSoyad).includes(q)) {
        matches.push({ orgId: orgRef.id, workerId: d.id, workerDoc: w });
      }
    });
  }
  if (matches.length === 0) {
    console.error(`İsim eşleşmedi: "${query}"`);
    process.exit(2);
  }
  if (matches.length > 1) {
    console.error(`Birden fazla eşleşme bulundu:`);
    matches.forEach((m) =>
      console.error(`  - ${m.workerDoc.adSoyad}   id=${m.workerId}`)
    );
    console.error('Lütfen daha spesifik bir arama yap veya workerId ver.');
    process.exit(3);
  }
  return matches[0];
}

async function fetchWorkerData(orgId, workerId) {
  const orgRef = db.collection('organizations').doc(orgId);

  const adSnap = await orgRef
    .collection('avans_borclar')
    .where('calisanId', '==', workerId)
    .get();
  const advances = [];
  const debts = [];
  const adDeleted = [];
  adSnap.forEach((d) => {
    const x = { ...d.data(), _docId: d.id };
    if (x.silinmeTarihi) adDeleted.push(x);
    else if (x.tur === 'advance') advances.push(x);
    else if (x.tur === 'debt') debts.push(x);
  });
  advances.sort((a, b) => new Date(a.islemTarihi) - new Date(b.islemTarihi));
  debts.sort((a, b) => new Date(a.islemTarihi) - new Date(b.islemTarihi));

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

  const ykSnap = await orgRef
    .collection('yoklama')
    .where('calisanId', '==', workerId)
    .get();
  const attendance = [];
  ykSnap.forEach((d) => {
    const x = { ...d.data(), _docId: d.id };
    if (!x.silinmeTarihi) attendance.push(x);
  });
  attendance.sort((a, b) => new Date(a.tarih) - new Date(b.tarih));

  return { advances, debts, adDeleted, payments, paymentsDeleted, attendance };
}

// Uygulamadaki PayrollCalculator ile birebir aynı mantık:
//   worked   → 1.0 gün,  halfDay → 0.5 gün,  absent / leave → 0 gün
function workedEquivalent(attendanceInRange) {
  return attendanceInRange.reduce((acc, a) => {
    if (a.durum === 'worked') return acc + 1.0;
    if (a.durum === 'half_day' || a.durum === 'halfDay') return acc + 0.5;
    return acc;
  }, 0);
}

function dayOnly(d) {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
}

function inRange(iso, start, end) {
  if (!iso) return false;
  const t = dayOnly(new Date(iso)).getTime();
  return t >= start.getTime() && t <= end.getTime();
}

function buildReport({ orgId, workerId, workerDoc }, data) {
  const { advances, debts, adDeleted, payments, paymentsDeleted, attendance } =
    data;
  const w = workerDoc;
  const today = new Date().toLocaleDateString('tr-TR');
  const lines = [];
  const L = (s) => lines.push(s);

  const padRight = (s, n) => String(s).padEnd(n);
  const padLeftMoney = (n) => TL(n).padStart(16);

  L('================================================================');
  L(`ÇALIŞAN RAPORU — ${(w.adSoyad || '').toUpperCase()}`);
  L(`Rapor tarihi: ${today}`);
  L('================================================================');
  L('');
  L('ÇALIŞAN BİLGİLERİ');
  L('-----------------');
  L(`Ad Soyad        : ${w.adSoyad}`);
  L(`Çalışan ID      : ${workerId}`);
  L(`Günlük ücret    : ${TL(w.gunlukUcret)}`);
  L(`Durum           : ${w.aktifMi ? 'Aktif' : 'Pasif'}${w.silinmeTarihi ? '  (SİLİNMİŞ)' : ''}`);
  L('');

  L(`AVANSLAR  (${advances.length} kayıt — Toplam ${TL(sum(advances))})`);
  L('----------------------------------------------------------------');
  if (advances.length > 0) {
    L(`${padRight('Tarih', 13)}${padRight('Tutar', 18)}${padRight('Mahsup', 12)}Not`);
    L(`${padRight('-----------', 13)}${padRight('----------------', 18)}${padRight('----------', 12)}----`);
    advances.forEach((x) => {
      L(
        `${padRight(fmtDate(x.islemTarihi), 13)}${padLeftMoney(x.tutar)}  ${padRight(x.mahsupAy || '-', 12)}${x.not || ''}`
      );
    });
    L(`${padRight('', 13)}${padLeftMoney(sum(advances))}  (TOPLAM)`);
  } else {
    L('Kayıt yok.');
  }
  L('');

  L(`BORÇLAR   (${debts.length} kayıt — Toplam ${TL(sum(debts))})`);
  L('----------------------------------------------------------------');
  if (debts.length > 0) {
    L(`${padRight('Tarih', 13)}${padRight('Tutar', 18)}${padRight('Mahsup', 12)}Not`);
    L(`${padRight('-----------', 13)}${padRight('----------------', 18)}${padRight('----------', 12)}----`);
    debts.forEach((x) => {
      L(
        `${padRight(fmtDate(x.islemTarihi), 13)}${padLeftMoney(x.tutar)}  ${padRight(x.mahsupAy || '-', 12)}${x.not || ''}`
      );
    });
    L(`${padRight('', 13)}${padLeftMoney(sum(debts))}  (TOPLAM)`);
  } else {
    L('Kayıt yok.');
  }
  L('');

  L(`MAAŞ ÖDEMELERİ  (${payments.length} kayıt — Toplam ${TL(sum(payments))})`);
  L('----------------------------------------------------------------');
  if (payments.length > 0) {
    payments.forEach((x) => {
      L(
        `Ödeme: ${fmtDate(x.odemeTarihi)}   Dönem: ${fmtDate(x.donemBaslangici)} → ${fmtDate(x.donemBitisi)}   ${TL(x.tutar)}`
      );
    });
  } else {
    L('Aktif ödeme kaydı yok.');
  }
  L('');

  if (adDeleted.length > 0) {
    L(`SİLİNMİŞ AVANS/BORÇ KAYITLARI (${adDeleted.length})`);
    L('----------------------------------------------------------------');
    adDeleted.forEach((x) => {
      L(
        `[${x.tur}] ${fmtDate(x.islemTarihi)}   ${TL(x.tutar)}   silindi=${fmtDate(x.silinmeTarihi)}${x.not ? '   — ' + x.not : ''}`
      );
    });
    L('');
  }

  if (paymentsDeleted.length > 0) {
    L(`SİLİNMİŞ MAAŞ ÖDEMELERİ (${paymentsDeleted.length})`);
    L('----------------------------------------------------------------');
    paymentsDeleted.forEach((x) => {
      L(
        `${fmtDate(x.odemeTarihi)}   ${TL(x.tutar)}   Dönem: ${fmtDate(x.donemBaslangici)} → ${fmtDate(x.donemBitisi)}   silindi=${fmtDate(x.silinmeTarihi)}`
      );
    });
    L('');
  }

  // Uygulamadaki workerPayrollProvider mantığı:
  //   periodStart = son ödemenin donemBitisi + 1 gün; yoksa çalışanın olusturulmaTarihi
  //   periodEnd   = bugün
  // PayrollCalculator:
  //   gross = workedDayEquivalent × gunlukUcret  (locationBonus burada hesaplanmıyor)
  //   deductions = sum(avans) − sum(borç)        (sadece dönem içindekiler)
  //   net = gross − deductions
  const todayDay = dayOnly(new Date());
  const lastPaidEnd = payments.length
    ? new Date(payments[payments.length - 1].donemBitisi)
    : null;
  const periodStart = lastPaidEnd
    ? new Date(
        lastPaidEnd.getFullYear(),
        lastPaidEnd.getMonth(),
        lastPaidEnd.getDate() + 1
      )
    : dayOnly(new Date(w.olusturulmaTarihi));
  const periodEnd = todayDay;

  const attInRange = attendance.filter((a) =>
    inRange(a.tarih, periodStart, periodEnd)
  );
  const advInRange = advances.filter((x) =>
    inRange(x.islemTarihi, periodStart, periodEnd)
  );
  const debtInRange = debts.filter((x) =>
    inRange(x.islemTarihi, periodStart, periodEnd)
  );

  const workedDays = workedEquivalent(attInRange);
  const advTop = sum(advInRange);
  const debtTop = sum(debtInRange);
  const dailyWage = Number(w.gunlukUcret) || 0;
  const gross = workedDays * dailyWage;
  const deductions = advTop - debtTop;
  const net = gross - deductions;

  const workedCount = attInRange.filter((a) => a.durum === 'worked').length;
  const halfCount = attInRange.filter(
    (a) => a.durum === 'half_day' || a.durum === 'halfDay'
  ).length;
  const absentCount = attInRange.filter((a) => a.durum === 'absent').length;
  const leaveCount = attInRange.filter((a) => a.durum === 'leave').length;

  L('MAAŞ HESABI (uygulama mantığı ile)');
  L('----------------------------------');
  L(
    `Dönem        : ${fmtDate(periodStart.toISOString())} → ${fmtDate(periodEnd.toISOString())}`
  );
  L(
    `Yoklama      : tam ${workedCount} gün, yarım ${halfCount}, gelmedi ${absentCount}, izinli ${leaveCount}   →   ${workedDays.toLocaleString('tr-TR')} gün karşılığı`
  );
  L(
    `Yevmiye top. : ${workedDays.toLocaleString('tr-TR')} × ${TL(dailyWage)} = ${TL(gross)}   (GROSS)`
  );
  L(`Avans (−)    : ${TL(advTop)}`);
  L(`Borç  (+)    : ${TL(debtTop)}`);
  L(`Kesinti      : ${TL(deductions)}   (Avans − Borç)`);
  L(`                                       -----------`);
  if (net > 0) {
    L(`NET ÖDENECEK : ${TL(net)}   (Gross − Kesinti)`);
  } else if (net < 0) {
    L(
      `NET          : −${TL(-net)}   (çalışan ${TL(-net)} fazla almış, gelecek dönemden mahsup)`
    );
  } else {
    L(`NET          : 0,00 ₺   (eşit)`);
  }
  L('');
  L('================================================================');
  L(`Kaynak: Firestore (ari-yapi-takip)`);
  L(`  organizations / ${orgId}`);
  L(`    / calisanlar         / ${workerId}`);
  L(`    / avans_borclar      (calisanId == ${workerId})`);
  L(`    / maas_odemeleri     (calisanId == ${workerId})`);
  L('================================================================');

  return lines.join('\n');
}

function slugify(s) {
  return normalize(s)
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '');
}

async function run() {
  const args = process.argv.slice(2);
  const saveFlag = args.includes('--save');
  const pdfOnlyFlag = args.includes('--pdf');
  const positional = args.filter((a) => !a.startsWith('--'));
  const query = positional[0];

  if (!query) {
    console.error(
      'Kullanım: node rapor.js <isim veya workerId> [--save | --pdf]'
    );
    process.exit(1);
  }

  const resolved = await resolveWorker(query);
  const data = await fetchWorkerData(resolved.orgId, resolved.workerId);
  const report = buildReport(resolved, data);
  console.log(report);

  if (saveFlag || pdfOnlyFlag) {
    const slug = slugify(resolved.workerDoc.adSoyad);
    const desktop = path.join(os.homedir(), 'Desktop');
    const pdfPath = path.join(desktop, `${slug}_rapor.pdf`);
    // PDF üretimi için cupsfilter girdi olarak .txt bekliyor.
    // --pdf modunda txt'yi geçici dizinde üret, PDF çıktıktan sonra sil.
    const txtPath = pdfOnlyFlag
      ? path.join(os.tmpdir(), `${slug}_rapor.txt`)
      : path.join(desktop, `${slug}_rapor.txt`);
    fs.writeFileSync(txtPath, report, 'utf8');
    if (saveFlag) console.log(`\n→ Yazıldı: ${txtPath}`);

    try {
      execSync(`/usr/sbin/cupsfilter "${txtPath}" > "${pdfPath}" 2>/dev/null`);
      console.log(`${saveFlag ? '' : '\n'}→ Yazıldı: ${pdfPath}`);
    } catch (e) {
      console.error(`(PDF üretilemedi: ${e.message})`);
    }

    if (pdfOnlyFlag) {
      try {
        fs.unlinkSync(txtPath);
      } catch (_) {}
    }
  }
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
