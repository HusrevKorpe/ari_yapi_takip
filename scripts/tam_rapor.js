// Tam veri raporu — Firestore'daki TÜM geçmiş veriyi (yoklama, avans, borç,
// şantiye primi, maaş ödemeleri) her çalışan için çeker, hesaplar ve
// Masaüstüne PDF raporu üretir.
//
// Hesap (çalışan başına, tüm geçmiş — workerLifetimeStats mantığı):
//   Hakediş  = gün karşılığı × yevmiye + şantiye primi
//   Bakiye   = Hakediş + işveren borcu − avans − ödenen maaş
//   (pozitif bakiye = işveren çalışana borçlu)
//
// Kullanım:
//   node tam_rapor.js            (Masaüstüne PDF + HTML yazar)
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
  })} ₺`;

const NUM = (n) => (Number(n) || 0).toLocaleString('tr-TR');

const fmtDate = (iso) => {
  if (!iso) return '-';
  const d = new Date(iso);
  if (isNaN(d)) return String(iso);
  return d.toLocaleDateString('tr-TR');
};

const AYLAR = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
const fmtAy = (key) => {
  const [y, m] = key.split('-');
  return `${AYLAR[Number(m) - 1]} ${y}`;
};

const esc = (s) =>
  String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

// PayrollCalculator.workedEquivalent ile aynı
const eqOf = (durum) =>
  durum === 'worked' ? 1.0 : durum === 'half_day' || durum === 'halfDay' ? 0.5 : 0;

async function fetchOrg(orgRef) {
  const [workerSnap, siteSnap, ykSnap, adSnap, paySnap] = await Promise.all([
    orgRef.collection('calisanlar').get(),
    orgRef.collection('santiyeler').get(),
    orgRef.collection('yoklama').get(),
    orgRef.collection('avans_borclar').get(),
    orgRef.collection('maas_odemeleri').get(),
  ]);

  const sites = {};
  siteSnap.forEach((d) => {
    const s = d.data();
    sites[d.id] = {
      ad: s.ad || s.isim || d.id,
      prim: Number(s.gunlukPrim) || 0,
    };
  });

  const byWorker = (snap, field) => {
    const m = {};
    snap.forEach((d) => {
      const x = { ...d.data(), _docId: d.id };
      if (x.silinmeTarihi) return; // uygulama gibi: silinmişler hariç
      (m[x[field]] = m[x[field]] || []).push(x);
    });
    return m;
  };

  const workers = [];
  workerSnap.forEach((d) => {
    const w = d.data();
    if (w.silinmeTarihi) return;
    workers.push({ id: d.id, ...w });
  });
  workers.sort((a, b) => {
    const act = (b.aktifMi !== false) - (a.aktifMi !== false);
    if (act !== 0) return act;
    return String(a.adSoyad || '').localeCompare(String(b.adSoyad || ''), 'tr');
  });

  return {
    workers,
    sites,
    yk: byWorker(ykSnap, 'calisanId'),
    ad: byWorker(adSnap, 'calisanId'),
    pay: byWorker(paySnap, 'calisanId'),
  };
}

function computeWorker(w, org) {
  const wage = Number(w.gunlukUcret) || 0;
  // primAliyor alanı yoksa uygulama true varsayar
  const receivesBonus = w.primAliyor !== false;

  const att = (org.yk[w.id] || [])
    .slice()
    .sort((a, b) => new Date(a.tarih) - new Date(b.tarih));
  const ads = (org.ad[w.id] || [])
    .filter((x) => x.tur === 'advance')
    .sort((a, b) => new Date(a.islemTarihi) - new Date(b.islemTarihi));
  const debts = (org.ad[w.id] || [])
    .filter((x) => x.tur === 'debt')
    .sort((a, b) => new Date(a.islemTarihi) - new Date(b.islemTarihi));
  const pays = (org.pay[w.id] || [])
    .slice()
    .sort((a, b) => new Date(a.odemeTarihi) - new Date(b.odemeTarihi));

  const primOf = (a) => {
    if (!receivesBonus) return 0;
    const eq = eqOf(a.durum);
    if (eq === 0 || !a.santiyeId) return 0;
    const s = org.sites[a.santiyeId];
    return s && s.prim > 0 ? s.prim * eq : 0;
  };

  // Aylık kırılım
  const months = {};
  att.forEach((a) => {
    const key = String(a.tarih).slice(0, 7); // YYYY-MM
    const m = (months[key] = months[key] || {
      tam: 0, yarim: 0, gelmedi: 0, izin: 0, eq: 0, yevmiye: 0, prim: 0,
    });
    const eq = eqOf(a.durum);
    if (a.durum === 'worked') m.tam++;
    else if (a.durum === 'half_day' || a.durum === 'halfDay') m.yarim++;
    else if (a.durum === 'absent') m.gelmedi++;
    else if (a.durum === 'leave') m.izin++;
    m.eq += eq;
    m.yevmiye += eq * wage;
    m.prim += primOf(a);
  });

  const sum = (arr) => arr.reduce((s, x) => s + (Number(x.tutar) || 0), 0);

  const totals = {
    tam: att.filter((a) => a.durum === 'worked').length,
    yarim: att.filter((a) => a.durum === 'half_day' || a.durum === 'halfDay').length,
    gelmedi: att.filter((a) => a.durum === 'absent').length,
    izin: att.filter((a) => a.durum === 'leave').length,
    eq: att.reduce((s, a) => s + eqOf(a.durum), 0),
    yevmiye: att.reduce((s, a) => s + eqOf(a.durum) * wage, 0),
    prim: att.reduce((s, a) => s + primOf(a), 0),
    avans: sum(ads),
    borc: sum(debts),
    odenen: sum(pays),
  };
  totals.hakedis = totals.yevmiye + totals.prim;
  totals.bakiye = totals.hakedis + totals.borc - totals.avans - totals.odenen;

  return { w, att, ads, debts, pays, months, totals, wage, receivesBonus };
}

// ---------------------------------------------------------------- HTML

function tbl(headers, rows, footer) {
  const th = headers
    .map((h) => `<th class="${h.num ? 'num' : ''}">${esc(h.t)}</th>`)
    .join('');
  const trs = rows
    .map(
      (r) =>
        `<tr>${r
          .map(
            (c, i) =>
              `<td class="${headers[i].num ? 'num' : ''}">${c}</td>`
          )
          .join('')}</tr>`
    )
    .join('\n');
  const tf = footer
    ? `<tfoot><tr>${footer
        .map(
          (c, i) =>
            `<td class="${headers[i].num ? 'num' : ''}">${c}</td>`
        )
        .join('')}</tr></tfoot>`
    : '';
  return `<table><thead><tr>${th}</tr></thead><tbody>${trs}</tbody>${tf}</table>`;
}

function workerSection(r, orgSites) {
  const { w, ads, debts, pays, months, totals, wage } = r;
  const H = [];
  const aktif = w.aktifMi !== false;

  H.push(`<section class="worker">`);
  H.push(
    `<h2>${esc(w.adSoyad)}${aktif ? '' : ' <span class="badge">ayrıldı</span>'}</h2>`
  );
  H.push(`<p class="meta">Yevmiye: <b>${TL(wage)}</b>`);
  if (!r.receivesBonus) H.push(` &middot; Prim almıyor`);
  if (w.olusturulmaTarihi)
    H.push(` &middot; Kayıt: ${fmtDate(w.olusturulmaTarihi)}`);
  H.push(`</p>`);

  // Aylık puantaj + hakediş
  const mkeys = Object.keys(months).sort();
  if (mkeys.length) {
    H.push(`<h3>Puantaj ve hakediş (aylık)</h3>`);
    H.push(
      tbl(
        [
          { t: 'Ay' },
          { t: 'Tam', num: 1 },
          { t: 'Yarım', num: 1 },
          { t: 'Gelmedi', num: 1 },
          { t: 'İzin', num: 1 },
          { t: 'Gün karş.', num: 1 },
          { t: 'Yevmiye', num: 1 },
          { t: 'Prim', num: 1 },
          { t: 'Hakediş', num: 1 },
        ],
        mkeys.map((k) => {
          const m = months[k];
          return [
            fmtAy(k),
            NUM(m.tam),
            NUM(m.yarim),
            NUM(m.gelmedi),
            NUM(m.izin),
            NUM(m.eq),
            TL(m.yevmiye),
            TL(m.prim),
            `<b>${TL(m.yevmiye + m.prim)}</b>`,
          ];
        }),
        [
          '<b>TOPLAM</b>',
          `<b>${NUM(totals.tam)}</b>`,
          `<b>${NUM(totals.yarim)}</b>`,
          `<b>${NUM(totals.gelmedi)}</b>`,
          `<b>${NUM(totals.izin)}</b>`,
          `<b>${NUM(totals.eq)}</b>`,
          `<b>${TL(totals.yevmiye)}</b>`,
          `<b>${TL(totals.prim)}</b>`,
          `<b>${TL(totals.hakedis)}</b>`,
        ]
      )
    );
  } else {
    H.push(`<p class="empty">Yoklama kaydı yok.</p>`);
  }

  // Avanslar
  H.push(`<h3>Avanslar (${ads.length} kayıt — ${TL(totals.avans)})</h3>`);
  if (ads.length) {
    H.push(
      tbl(
        [{ t: 'Tarih' }, { t: 'Tutar', num: 1 }, { t: 'Not' }],
        ads.map((x) => [fmtDate(x.islemTarihi), TL(x.tutar), esc(x.not || '')]),
        ['<b>TOPLAM</b>', `<b>${TL(totals.avans)}</b>`, '']
      )
    );
  } else {
    H.push(`<p class="empty">Kayıt yok.</p>`);
  }

  // Borçlar
  H.push(
    `<h3>İşveren borçları (${debts.length} kayıt — ${TL(totals.borc)})</h3>`
  );
  if (debts.length) {
    H.push(
      tbl(
        [{ t: 'Tarih' }, { t: 'Tutar', num: 1 }, { t: 'Not' }],
        debts.map((x) => [fmtDate(x.islemTarihi), TL(x.tutar), esc(x.not || '')]),
        ['<b>TOPLAM</b>', `<b>${TL(totals.borc)}</b>`, '']
      )
    );
  } else {
    H.push(`<p class="empty">Kayıt yok.</p>`);
  }

  // Maaş ödemeleri
  H.push(
    `<h3>Maaş ödemeleri (${pays.length} kayıt — ${TL(totals.odenen)})</h3>`
  );
  if (pays.length) {
    H.push(
      tbl(
        [
          { t: 'Ödeme tarihi' },
          { t: 'Dönem' },
          { t: 'Tutar', num: 1 },
          { t: 'Not' },
        ],
        pays.map((x) => [
          fmtDate(x.odemeTarihi),
          `${fmtDate(x.donemBaslangici)} → ${fmtDate(x.donemBitisi)}`,
          TL(x.tutar),
          esc(x.not || ''),
        ]),
        ['<b>TOPLAM</b>', '', `<b>${TL(totals.odenen)}</b>`, '']
      )
    );
  } else {
    H.push(`<p class="empty">Ödeme kaydı yok.</p>`);
  }

  // Hesap özeti
  const b = totals.bakiye;
  H.push(`<h3>Hesap özeti</h3>`);
  H.push(`<table class="ozet"><tbody>
    <tr><td>Yevmiye hakedişi (${NUM(totals.eq)} gün × ${TL(wage)})</td><td class="num">${TL(totals.yevmiye)}</td></tr>
    <tr><td>Şantiye primi</td><td class="num">+ ${TL(totals.prim)}</td></tr>
    <tr><td>İşveren borcu</td><td class="num">+ ${TL(totals.borc)}</td></tr>
    <tr><td>Avanslar</td><td class="num">− ${TL(totals.avans)}</td></tr>
    <tr><td>Ödenen maaşlar</td><td class="num">− ${TL(totals.odenen)}</td></tr>
    <tr class="sonuc ${b >= 0.005 ? 'pos' : b <= -0.005 ? 'neg' : ''}">
      <td><b>KALAN BAKİYE</b> ${
        b >= 0.005
          ? '(işveren çalışana borçlu)'
          : b <= -0.005
            ? '(çalışan hakedişinden fazla almış)'
            : '(hesap kapalı)'
      }</td>
      <td class="num"><b>${TL(b)}</b></td></tr>
  </tbody></table>`);

  H.push(`</section>`);
  return H.join('\n');
}

function buildHtml(orgId, results, sites) {
  const today = new Date();
  const stamp = today.toLocaleDateString('tr-TR');

  const grand = results.reduce(
    (g, r) => {
      for (const k of [
        'eq', 'yevmiye', 'prim', 'hakedis', 'avans', 'borc', 'odenen', 'bakiye',
      ])
        g[k] += r.totals[k];
      return g;
    },
    { eq: 0, yevmiye: 0, prim: 0, hakedis: 0, avans: 0, borc: 0, odenen: 0, bakiye: 0 }
  );

  const ozetRows = results.map((r) => {
    const aktif = r.w.aktifMi !== false;
    const b = r.totals.bakiye;
    return [
      `${esc(r.w.adSoyad)}${aktif ? '' : ' <span class="badge">ayrıldı</span>'}`,
      NUM(r.totals.eq),
      TL(r.totals.yevmiye),
      TL(r.totals.prim),
      TL(r.totals.borc),
      TL(r.totals.avans),
      TL(r.totals.odenen),
      `<b class="${b >= 0.005 ? 'pos' : b <= -0.005 ? 'neg' : ''}">${TL(b)}</b>`,
    ];
  });

  const siteList = Object.values(sites)
    .map((s) => `${esc(s.ad)}${s.prim > 0 ? ` (prim ${TL(s.prim)}/gün)` : ''}`)
    .join(' &middot; ');

  return `<!DOCTYPE html>
<html lang="tr"><head><meta charset="utf-8">
<title>Tam Veri Raporu — ${stamp}</title>
<style>
  * { box-sizing: border-box; }
  body {
    font: 9.5pt/1.45 -apple-system, "Helvetica Neue", Arial, sans-serif;
    color: #1a1a1a; margin: 0; padding: 24px 28px;
  }
  h1 { font-size: 17pt; margin: 0 0 2px; }
  h2 { font-size: 13pt; margin: 0 0 4px; border-bottom: 2px solid #1a1a1a; padding-bottom: 3px; }
  h3 { font-size: 10pt; margin: 12px 0 4px; }
  .sub { color: #555; margin: 0 0 14px; }
  .meta { color: #444; margin: 0 0 6px; }
  .empty { color: #888; font-style: italic; margin: 2px 0 6px; }
  .badge { font-size: 8pt; background: #eee; border: 1px solid #ccc; border-radius: 3px;
           padding: 0 4px; color: #666; vertical-align: middle; }
  table { border-collapse: collapse; width: 100%; margin: 2px 0 8px; }
  th, td { border: 1px solid #bbb; padding: 3px 6px; text-align: left; }
  th { background: #f0f0f0; font-weight: 600; }
  td.num, th.num { text-align: right; white-space: nowrap; }
  tfoot td { background: #f7f7f7; }
  .ozet { width: 62%; }
  .ozet .sonuc td { border-top: 2px solid #1a1a1a; font-size: 10.5pt; }
  .pos { color: #0a6b2d; }
  .neg { color: #b00020; }
  .worker { page-break-before: always; }
  .genel { page-break-after: always; }
  .foot { margin-top: 16px; color: #777; font-size: 8pt; }
  @page { margin: 12mm 10mm; }
</style></head><body>

<div class="genel">
  <h1>ARI SAHA — TAM VERİ RAPORU</h1>
  <p class="sub">Rapor tarihi: ${stamp} &middot; Organizasyon: ${esc(orgId)} &middot; Kapsam: tüm geçmiş kayıtlar (yoklama, avans, borç, prim, maaş ödemeleri)</p>
  ${siteList ? `<p class="meta">Şantiyeler: ${siteList}</p>` : ''}

  <h3>Genel özet — tüm çalışanlar</h3>
  ${tbl(
    [
      { t: 'Çalışan' },
      { t: 'Gün karş.', num: 1 },
      { t: 'Yevmiye', num: 1 },
      { t: 'Prim', num: 1 },
      { t: 'Borç (+)', num: 1 },
      { t: 'Avans (−)', num: 1 },
      { t: 'Ödenen (−)', num: 1 },
      { t: 'Kalan bakiye', num: 1 },
    ],
    ozetRows,
    [
      `<b>TOPLAM (${results.length} çalışan)</b>`,
      `<b>${NUM(grand.eq)}</b>`,
      `<b>${TL(grand.yevmiye)}</b>`,
      `<b>${TL(grand.prim)}</b>`,
      `<b>${TL(grand.borc)}</b>`,
      `<b>${TL(grand.avans)}</b>`,
      `<b>${TL(grand.odenen)}</b>`,
      `<b>${TL(grand.bakiye)}</b>`,
    ]
  )}
  <p class="meta">Kalan bakiye = yevmiye + prim + işveren borcu − avans − ödenen.
  Pozitif: işveren çalışana borçlu. Negatif: çalışan hakedişinden fazla almış.</p>
  <p class="foot">Kaynak: Firestore &middot; organizations/${esc(orgId)} &middot; silinmiş kayıtlar hariç &middot; uygulamadaki PayrollCalculator / workerLifetimeStats mantığıyla birebir.</p>
</div>

${results.map((r) => workerSection(r, sites)).join('\n')}

</body></html>`;
}

// ---------------------------------------------------------------- main

const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

async function run() {
  const orgs = await db.collection('organizations').listDocuments();
  const desktop = path.join(os.homedir(), 'Desktop');
  const stamp = new Date().toISOString().slice(0, 10);

  for (const orgRef of orgs) {
    const org = await fetchOrg(orgRef);
    if (org.workers.length === 0) continue;

    const results = org.workers.map((w) => computeWorker(w, org));
    const html = buildHtml(orgRef.id, results, org.sites);

    const base =
      orgs.length > 1 ? `tam_rapor_${orgRef.id}_${stamp}` : `tam_rapor_${stamp}`;
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
      // Chrome yoksa HTML'i Masaüstüne bırak
      const fallback = path.join(desktop, `${base}.html`);
      fs.copyFileSync(htmlPath, fallback);
      console.error(`(PDF üretilemedi: ${e.message}) → HTML: ${fallback}`);
    }

    // Terminale kısa özet
    console.log(`\nOrganizasyon: ${orgRef.id} — ${results.length} çalışan`);
    for (const r of results) {
      const b = r.totals.bakiye;
      console.log(
        `  ${String(r.w.adSoyad).padEnd(28)} hakediş ${TL(r.totals.hakedis).padStart(14)}  ödenen ${TL(r.totals.odenen).padStart(14)}  bakiye ${TL(b).padStart(14)}`
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
