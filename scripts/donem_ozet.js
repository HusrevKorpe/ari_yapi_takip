// Dönem özeti — belirli bir tarih aralığındaki TÜM hareketleri (yoklama, avans,
// borç, maaş ödemeleri) Firestore'dan çeker ve Masaüstüne ÖZET bir PDF üretir.
//
// Yoklama gün bazlıdır (tam gün / yarım gün / gelmedi / izinli); sistemde saat
// verisi tutulmaz. "Saat" yerine gün karşılığı gösterilir: tam=1, yarım=0.5.
//
// Kullanım:
//   node donem_ozet.js                       (varsayılan: 2026-07-02 → 2026-07-08)
//   node donem_ozet.js 2026-07-02 2026-07-08 (başlangıç ve bitiş dahil)
//
// Service account: proje kökünde serviceAccount.json veya SERVICE_ACCOUNT_PATH.

const admin = require('firebase-admin');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

// ---- Tarih aralığı (her ikisi de DAHİL) --------------------------------
const START = process.argv[2] || '2026-07-02';
const END = process.argv[3] || '2026-07-08';
const dOnly = (iso) => String(iso || '').slice(0, 10);
const inRange = (iso) => {
  const d = dOnly(iso);
  return d >= START && d <= END;
};

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

// ---- Yardımcılar --------------------------------------------------------
const TL = (n) =>
  `${(Number(n) || 0).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} ₺`;
const NUM = (n) => (Number(n) || 0).toLocaleString('tr-TR');
const esc = (s) =>
  String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

const AYLAR = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
const fmtGun = (isoDay) => {
  const [y, m, d] = isoDay.split('-');
  return `${Number(d)} ${AYLAR[Number(m) - 1]}`;
};
const fmtGunKisa = (isoDay) => {
  const [, m, d] = isoDay.split('-');
  return `${Number(d)}.${Number(m)}`;
};
const GUNLER = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];
const gunAdi = (isoDay) => {
  const [y, m, d] = isoDay.split('-').map(Number);
  return GUNLER[new Date(y, m - 1, d).getDay()];
};

// Aralıktaki gün listesi (dahil)
function dayList(start, end) {
  const out = [];
  let [y, m, d] = start.split('-').map(Number);
  const cur = new Date(y, m - 1, d);
  const [ey, em, ed] = end.split('-').map(Number);
  const stop = new Date(ey, em - 1, ed);
  while (cur <= stop) {
    out.push(
      `${cur.getFullYear()}-${String(cur.getMonth() + 1).padStart(2, '0')}-${String(
        cur.getDate()
      ).padStart(2, '0')}`
    );
    cur.setDate(cur.getDate() + 1);
  }
  return out;
}
const DAYS = dayList(START, END);

// Yoklama durum → gün karşılığı
const eqOf = (durum) =>
  durum === 'worked' ? 1.0 : durum === 'half_day' || durum === 'halfDay' ? 0.5 : 0;

// Durum → matris rozeti
const badge = (durum) => {
  switch (durum) {
    case 'worked':
      return '<span class="b tam">T</span>';
    case 'half_day':
    case 'halfDay':
      return '<span class="b yarim">Y</span>';
    case 'absent':
      return '<span class="b yok">×</span>';
    case 'leave':
      return '<span class="b izin">İ</span>';
    default:
      return '<span class="b bos">·</span>';
  }
};

// ---- Firestore'dan çek --------------------------------------------------
async function fetchOrg(orgRef) {
  const [workerSnap, siteSnap, ykSnap, adSnap, paySnap] = await Promise.all([
    orgRef.collection('calisanlar').get(),
    orgRef.collection('santiyeler').get(),
    orgRef.collection('yoklama').get(),
    orgRef.collection('avans_borclar').get(),
    orgRef.collection('maas_odemeleri').get(),
  ]);

  const sites = {};
  const sitePrim = {};
  siteSnap.forEach((d) => {
    const s = d.data();
    sites[d.id] = s.ad || s.isim || d.id;
    sitePrim[d.id] = Number(s.gunlukPrim) || 0;
  });

  const workers = {};
  workerSnap.forEach((d) => {
    const w = d.data();
    if (w.silinmeTarihi) return;
    workers[d.id] = {
      id: d.id,
      ad: w.adSoyad || d.id,
      aktif: w.aktifMi !== false,
      yevmiye: Number(w.gunlukUcret) || 0,
      primAliyor: w.primAliyor !== false,
    };
  });

  const attendance = [];
  ykSnap.forEach((d) => {
    const x = d.data();
    if (x.silinmeTarihi) return;
    if (!inRange(x.tarih)) return;
    attendance.push({
      calisanId: x.calisanId,
      gun: dOnly(x.tarih),
      durum: x.durum,
      santiyeId: x.santiyeId || null,
    });
  });

  const advances = [];
  const debts = [];
  adSnap.forEach((d) => {
    const x = d.data();
    if (x.silinmeTarihi) return;
    if (!inRange(x.islemTarihi)) return;
    const rec = {
      calisanId: x.calisanId,
      gun: dOnly(x.islemTarihi),
      tutar: Number(x.tutar) || 0,
      not: x.not || '',
    };
    if (x.tur === 'advance') advances.push(rec);
    else if (x.tur === 'debt') debts.push(rec);
  });

  const payments = [];
  paySnap.forEach((d) => {
    const x = d.data();
    if (x.silinmeTarihi) return;
    if (!inRange(x.odemeTarihi)) return;
    payments.push({
      calisanId: x.calisanId,
      gun: dOnly(x.odemeTarihi),
      tutar: Number(x.tutar) || 0,
      donem: `${dOnly(x.donemBaslangici)} → ${dOnly(x.donemBitisi)}`,
      not: x.not || '',
    });
  });

  return { workers, sites, sitePrim, attendance, advances, debts, payments };
}

// ---- Çalışan bazlı topla -----------------------------------------------
function buildWorkerRows(org) {
  const map = {};
  const ensure = (id) => {
    if (!map[id]) {
      const w = org.workers[id] || {
        id, ad: id, aktif: true, yevmiye: 0, primAliyor: true,
      };
      map[id] = {
        ...w,
        tam: 0, yarim: 0, yok: 0, izin: 0, eq: 0,
        cells: {}, // gun -> {durum, santiyeId}
        santiyeler: new Set(),
        avans: 0, avansAdet: 0,
        borc: 0, borcAdet: 0,
        odenen: 0, odenenAdet: 0,
        prim: 0,
      };
    }
    return map[id];
  };

  org.attendance.forEach((a) => {
    const r = ensure(a.calisanId);
    r.cells[a.gun] = { durum: a.durum, santiyeId: a.santiyeId };
    if (a.durum === 'worked') r.tam++;
    else if (a.durum === 'half_day' || a.durum === 'halfDay') r.yarim++;
    else if (a.durum === 'absent') r.yok++;
    else if (a.durum === 'leave') r.izin++;
    const dayEq = eqOf(a.durum);
    r.eq += dayEq;
    if (a.santiyeId && dayEq > 0) r.santiyeler.add(a.santiyeId);
    // Prim = şantiyenin günlük primi × gün karşılığı; sadece prim alan personel
    // ve şantiyeye yazılmış çalışılan günler için (uygulamadaki "Bölge Primi").
    if (r.primAliyor && a.santiyeId && dayEq > 0) {
      r.prim += (org.sitePrim[a.santiyeId] || 0) * dayEq;
    }
  });
  org.advances.forEach((x) => {
    const r = ensure(x.calisanId);
    r.avans += x.tutar;
    r.avansAdet++;
  });
  org.debts.forEach((x) => {
    const r = ensure(x.calisanId);
    r.borc += x.tutar;
    r.borcAdet++;
  });
  org.payments.forEach((x) => {
    const r = ensure(x.calisanId);
    r.odenen += x.tutar;
    r.odenenAdet++;
  });

  const rows = Object.values(map);
  rows.sort((a, b) => {
    const act = (b.aktif ? 1 : 0) - (a.aktif ? 1 : 0);
    if (act !== 0) return act;
    return String(a.ad).localeCompare(String(b.ad), 'tr');
  });
  return rows;
}

// ---- HTML ---------------------------------------------------------------
function buildHtml(orgId, org, rows) {
  const gt = {
    tam: 0, yarim: 0, yok: 0, izin: 0, eq: 0,
    avans: 0, avansAdet: 0, borc: 0, borcAdet: 0, odenen: 0, odenenAdet: 0,
    prim: 0,
  };
  rows.forEach((r) => {
    for (const k of ['tam', 'yarim', 'yok', 'izin', 'eq', 'avans', 'avansAdet', 'borc', 'borcAdet', 'odenen', 'odenenAdet', 'prim'])
      gt[k] += r[k];
  });

  const aralik = `${fmtGun(START)} – ${fmtGun(END)} ${END.slice(0, 4)}`;

  // Genel özet kartları
  const kart = (etiket, deger, alt) =>
    `<div class="kart"><div class="k-deger">${deger}</div><div class="k-etiket">${etiket}</div>${
      alt ? `<div class="k-alt">${alt}</div>` : ''
    }</div>`;

  const kartlar = [
    kart('Çalışan (hareketli)', NUM(rows.length), `${DAYS.length} günlük dönem`),
    kart('Gün karşılığı', NUM(gt.eq), `${NUM(gt.tam)} tam · ${NUM(gt.yarim)} yarım`),
    kart('Gelmedi / İzin', `${NUM(gt.yok)} / ${NUM(gt.izin)}`, 'gün'),
    kart('Prim', TL(gt.prim), 'şantiye günlük primi'),
    kart('Avans', TL(gt.avans), `${gt.avansAdet} işlem`),
    kart('Borç', TL(gt.borc), `${gt.borcAdet} işlem`),
    ...(gt.odenenAdet
      ? [kart('Maaş ödemesi', TL(gt.odenen), `${gt.odenenAdet} işlem`)]
      : []),
  ].join('');

  // Çalışan bazlı özet tablo
  const workerRows = rows
    .map((r) => {
      const santiyeAd = [...r.santiyeler]
        .map((sid) => esc(org.sites[sid] || sid))
        .join(', ');
      return `<tr>
        <td>${esc(r.ad)}${r.aktif ? '' : ' <span class="ayrildi">ayrıldı</span>'}</td>
        <td class="c">${r.tam || '·'}</td>
        <td class="c">${r.yarim || '·'}</td>
        <td class="c">${r.yok || '·'}</td>
        <td class="c">${r.izin || '·'}</td>
        <td class="c"><b>${NUM(r.eq)}</b></td>
        <td class="s">${santiyeAd || '<span class="mut">—</span>'}</td>
        <td class="n">${
          r.prim
            ? TL(r.prim)
            : `<span class="mut">${r.primAliyor ? '—' : 'prim yok'}</span>`
        }</td>
        <td class="n">${r.avans ? TL(r.avans) : '<span class="mut">—</span>'}</td>
        <td class="n">${r.borc ? TL(r.borc) : '<span class="mut">—</span>'}</td>
      </tr>`;
    })
    .join('\n');

  const workerFoot = `<tr class="foot">
    <td><b>TOPLAM (${rows.length} çalışan)</b></td>
    <td class="c"><b>${NUM(gt.tam)}</b></td>
    <td class="c"><b>${NUM(gt.yarim)}</b></td>
    <td class="c"><b>${NUM(gt.yok)}</b></td>
    <td class="c"><b>${NUM(gt.izin)}</b></td>
    <td class="c"><b>${NUM(gt.eq)}</b></td>
    <td></td>
    <td class="n"><b>${TL(gt.prim)}</b></td>
    <td class="n"><b>${TL(gt.avans)}</b></td>
    <td class="n"><b>${TL(gt.borc)}</b></td>
  </tr>`;

  // Günlük yoklama matrisi
  const matrisHead = DAYS.map(
    (g) => `<th class="c"><div>${fmtGunKisa(g)}</div><div class="wd">${gunAdi(g)}</div></th>`
  ).join('');
  const matrisRows = rows
    .map((r) => {
      const cells = DAYS.map((g) => {
        const c = r.cells[g];
        if (!c) return `<td class="c">${badge(null)}</td>`;
        const st = c.santiyeId ? esc(org.sites[c.santiyeId] || '') : '';
        const title = st ? ` title="${st}"` : '';
        return `<td class="c"${title}>${badge(c.durum)}</td>`;
      }).join('');
      return `<tr><td class="wname">${esc(r.ad)}</td>${cells}<td class="c"><b>${NUM(
        r.eq
      )}</b></td></tr>`;
    })
    .join('\n');

  // Avans detay
  const avansDetay = org.advances
    .slice()
    .sort((a, b) => a.gun.localeCompare(b.gun))
    .map(
      (x) => `<tr>
        <td>${fmtGun(x.gun)}</td>
        <td>${esc((org.workers[x.calisanId] || {}).ad || x.calisanId)}</td>
        <td class="n">${TL(x.tutar)}</td>
        <td>${esc(x.not) || '<span class="mut">—</span>'}</td>
      </tr>`
    )
    .join('\n');

  const borcDetay = org.debts
    .slice()
    .sort((a, b) => a.gun.localeCompare(b.gun))
    .map(
      (x) => `<tr>
        <td>${fmtGun(x.gun)}</td>
        <td>${esc((org.workers[x.calisanId] || {}).ad || x.calisanId)}</td>
        <td class="n">${TL(x.tutar)}</td>
        <td>${esc(x.not) || '<span class="mut">—</span>'}</td>
      </tr>`
    )
    .join('\n');

  const now = new Date().toLocaleString('tr-TR');

  return `<!DOCTYPE html>
<html lang="tr"><head><meta charset="utf-8">
<title>Dönem Özeti — ${aralik}</title>
<style>
  * { box-sizing: border-box; }
  body { font: 9.5pt/1.4 -apple-system, "Helvetica Neue", Arial, sans-serif; color: #1a1a1a; margin: 0; padding: 20px 24px; }
  h1 { font-size: 17pt; margin: 0 0 2px; }
  h2 { font-size: 12pt; margin: 18px 0 6px; border-bottom: 2px solid #1a1a1a; padding-bottom: 3px; }
  .sub { color: #555; margin: 0 0 14px; }
  .kartlar { display: flex; flex-wrap: wrap; gap: 8px; margin: 4px 0 6px; }
  .kart { flex: 1; min-width: 120px; border: 1px solid #ccc; border-radius: 8px; padding: 8px 10px; background: #fafafa; }
  .k-deger { font-size: 15pt; font-weight: 700; }
  .k-etiket { font-size: 8pt; color: #555; text-transform: uppercase; letter-spacing: .3px; margin-top: 2px; }
  .k-alt { font-size: 8pt; color: #888; margin-top: 1px; }
  table { border-collapse: collapse; width: 100%; margin: 4px 0 8px; }
  th, td { border: 1px solid #ccc; padding: 3px 6px; text-align: left; vertical-align: middle; }
  th { background: #f0f0f0; font-weight: 600; font-size: 8.5pt; }
  td.c, th.c { text-align: center; white-space: nowrap; }
  td.n, th.n { text-align: right; white-space: nowrap; }
  td.s { font-size: 8.5pt; color: #444; }
  .wd { font-size: 7pt; color: #999; font-weight: 400; }
  .wname { font-size: 8.5pt; }
  tr.foot td { background: #f7f7f7; }
  .ayrildi { font-size: 7.5pt; background: #eee; border: 1px solid #ccc; border-radius: 3px; padding: 0 4px; color: #777; }
  .mut { color: #bbb; }
  .b { display: inline-block; width: 17px; height: 17px; line-height: 17px; text-align: center; border-radius: 4px; font-size: 8.5pt; font-weight: 700; }
  .b.tam  { background: #d6f0dc; color: #0a6b2d; }
  .b.yarim{ background: #fdeecb; color: #9a6b00; }
  .b.yok  { background: #f6d4d8; color: #b00020; }
  .b.izin { background: #dbe6fb; color: #1f4fa8; }
  .b.bos  { background: #f2f2f2; color: #ccc; }
  .lgnd { font-size: 8pt; color: #666; margin: 2px 0 8px; }
  .foot-note { margin-top: 14px; color: #888; font-size: 7.5pt; }
  @page { size: A4 landscape; margin: 10mm; }
</style></head><body>

<h1>ARI SAHA — DÖNEM ÖZETİ</h1>
<p class="sub">Dönem: <b>${aralik}</b> (${START} → ${END}, her iki gün dahil) &middot; ${DAYS.length} gün &middot; Rapor: ${esc(now)}</p>

<div class="kartlar">${kartlar}</div>

<h2>Çalışan bazlı özet</h2>
<table>
  <thead><tr>
    <th>Çalışan</th><th class="c">Tam</th><th class="c">Yarım</th><th class="c">Gelmedi</th>
    <th class="c">İzin</th><th class="c">Gün karş.</th><th>Şantiye(ler)</th>
    <th class="n">Prim</th><th class="n">Avans</th><th class="n">Borç</th>
  </tr></thead>
  <tbody>${workerRows}${workerFoot}</tbody>
</table>

<h2>Günlük yoklama (${fmtGunKisa(START)}–${fmtGunKisa(END)})</h2>
<p class="lgnd">
  <span class="b tam">T</span> Tam gün &nbsp;
  <span class="b yarim">Y</span> Yarım gün &nbsp;
  <span class="b yok">×</span> Gelmedi &nbsp;
  <span class="b izin">İ</span> İzinli &nbsp;
  <span class="b bos">·</span> Kayıt yok
  &nbsp;— Not: yoklama gün bazlıdır, sistemde saat verisi tutulmaz (tam=1, yarım=0.5).
</p>
<table>
  <thead><tr><th>Çalışan</th>${matrisHead}<th class="c">Gün karş.</th></tr></thead>
  <tbody>${matrisRows}</tbody>
</table>

<h2>Avans detayı (${org.advances.length} işlem — ${TL(gt.avans)})</h2>
${
  org.advances.length
    ? `<table><thead><tr><th>Tarih</th><th>Çalışan</th><th class="n">Tutar</th><th>Not</th></tr></thead><tbody>${avansDetay}</tbody></table>`
    : '<p class="mut">Bu dönemde avans kaydı yok.</p>'
}

<h2>Borç detayı (${org.debts.length} işlem — ${TL(gt.borc)})</h2>
${
  org.debts.length
    ? `<table><thead><tr><th>Tarih</th><th>Çalışan</th><th class="n">Tutar</th><th>Not</th></tr></thead><tbody>${borcDetay}</tbody></table>`
    : '<p class="mut">Bu dönemde borç kaydı yok.</p>'
}

<p class="foot-note">Kaynak: Firestore &middot; organizations/${esc(orgId)} &middot; silinmiş kayıtlar hariç &middot; avans: işveren çalışandan alacaklı, borç: işveren çalışana borçlu.</p>

</body></html>`;
}

// ---- main ---------------------------------------------------------------
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

async function run() {
  const orgs = await db.collection('organizations').listDocuments();
  const desktop = path.join(os.homedir(), 'Desktop');

  for (const orgRef of orgs) {
    const org = await fetchOrg(orgRef);
    const rows = buildWorkerRows(org);
    if (rows.length === 0) {
      console.log(`Organizasyon ${orgRef.id}: ${START}–${END} aralığında kayıt yok.`);
      continue;
    }
    const html = buildHtml(orgRef.id, org, rows);

    const base =
      orgs.length > 1
        ? `donem_ozet_${orgRef.id}_${START}_${END}`
        : `donem_ozet_${START}_${END}`;
    const htmlPath = path.join(os.tmpdir(), `${base}.html`);
    const pdfPath = path.join(desktop, `${base}.pdf`);
    fs.writeFileSync(htmlPath, html, 'utf8');

    try {
      execSync(
        `"${CHROME}" --headless --disable-gpu --no-pdf-header-footer ` +
          `--print-to-pdf="${pdfPath}" "file://${htmlPath}" 2>/dev/null`
      );
      console.log(`→ PDF yazıldı: ${pdfPath}`);
    } catch (e) {
      const fallback = path.join(desktop, `${base}.html`);
      fs.copyFileSync(htmlPath, fallback);
      console.error(`(PDF üretilemedi: ${e.message}) → HTML: ${fallback}`);
    }

    // Terminal özeti
    const gt = rows.reduce(
      (a, r) => {
        a.tam += r.tam; a.yarim += r.yarim; a.yok += r.yok; a.izin += r.izin;
        a.eq += r.eq; a.avans += r.avans; a.borc += r.borc; a.prim += r.prim;
        return a;
      },
      { tam: 0, yarim: 0, yok: 0, izin: 0, eq: 0, avans: 0, borc: 0, prim: 0 }
    );
    console.log(
      `\n${START} → ${END} özeti (${rows.length} çalışan):\n` +
        `  Tam ${gt.tam} · Yarım ${gt.yarim} · Gelmedi ${gt.yok} · İzin ${gt.izin} · Gün karş. ${NUM(gt.eq)}\n` +
        `  Prim ${TL(gt.prim)} · Avans ${TL(gt.avans)} · Borç ${TL(gt.borc)}`
    );
  }
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
