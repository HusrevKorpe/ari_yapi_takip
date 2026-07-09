// Aylık çalışan raporu — tek çalışanın verilen aylardaki gün gün puantajını,
// avans/borç/maaş ödemelerini Firestore'dan çeker ve Masaüstüne PDF üretir.
//
// Kullanım:
//   node aylik_rapor.js "osman bilgiç" 2026-06 2026-07
//   node aylik_rapor.js <workerId> 2026-06
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

const fmtGun = (iso) => {
  const d = new Date(iso);
  if (isNaN(d)) return '';
  return d.toLocaleDateString('tr-TR', { weekday: 'long' });
};

const AYLAR = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
const fmtAy = (key) => {
  const [y, m] = key.split('-');
  return `${AYLAR[Number(m) - 1]} ${y}`;
};

const DURUM = {
  worked: 'Geldi',
  half_day: 'Yarım gün',
  halfDay: 'Yarım gün',
  absent: 'Gelmedi',
  leave: 'İzinli',
};

const esc = (s) =>
  String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

const normalize = (s) =>
  String(s || '')
    .toLocaleLowerCase('tr-TR')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// PayrollCalculator.workedEquivalent ile aynı
const eqOf = (durum) =>
  durum === 'worked' ? 1.0 : durum === 'half_day' || durum === 'halfDay' ? 0.5 : 0;

async function resolveWorker(query) {
  const orgs = await db.collection('organizations').listDocuments();

  if (UUID_RE.test(query)) {
    for (const orgRef of orgs) {
      const snap = await orgRef.collection('calisanlar').doc(query).get();
      if (snap.exists) return { orgRef, workerId: query, w: snap.data() };
    }
    console.error(`workerId bulunamadı: ${query}`);
    process.exit(2);
  }

  const q = normalize(query);
  const matches = [];
  for (const orgRef of orgs) {
    const workers = await orgRef.collection('calisanlar').get();
    workers.forEach((d) => {
      const w = d.data();
      if (w.silinmeTarihi) return;
      if (normalize(w.adSoyad).includes(q)) {
        matches.push({ orgRef, workerId: d.id, w });
      }
    });
  }
  if (matches.length === 0) {
    console.error(`İsim eşleşmedi: "${query}"`);
    process.exit(2);
  }
  if (matches.length > 1) {
    console.error('Birden fazla eşleşme:');
    matches.forEach((m) => console.error(`  - ${m.w.adSoyad}  id=${m.workerId}`));
    process.exit(3);
  }
  return matches[0];
}

function tbl(headers, rows, footer) {
  const th = headers
    .map((h) => `<th class="${h.num ? 'num' : ''}">${esc(h.t)}</th>`)
    .join('');
  const trs = rows
    .map(
      (r) =>
        `<tr>${r
          .map((c, i) => `<td class="${headers[i].num ? 'num' : ''}">${c}</td>`)
          .join('')}</tr>`
    )
    .join('\n');
  const tf = footer
    ? `<tfoot><tr>${footer
        .map((c, i) => `<td class="${headers[i].num ? 'num' : ''}">${c}</td>`)
        .join('')}</tr></tfoot>`
    : '';
  return `<table><thead><tr>${th}</tr></thead><tbody>${trs}</tbody>${tf}</table>`;
}

async function run() {
  const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  const query = args[0];
  const months = args.slice(1).filter((a) => /^\d{4}-\d{2}$/.test(a)).sort();

  if (!query || months.length === 0) {
    console.error('Kullanım: node aylik_rapor.js <isim|workerId> <YYYY-MM> [YYYY-MM ...]');
    process.exit(1);
  }

  const { orgRef, workerId, w } = await resolveWorker(query);
  const wage = Number(w.gunlukUcret) || 0;
  const receivesBonus = w.primAliyor !== false;

  const [siteSnap, ykSnap, adSnap, paySnap] = await Promise.all([
    orgRef.collection('santiyeler').get(),
    orgRef.collection('yoklama').where('calisanId', '==', workerId).get(),
    orgRef.collection('avans_borclar').where('calisanId', '==', workerId).get(),
    orgRef.collection('maas_odemeleri').where('calisanId', '==', workerId).get(),
  ]);

  const sites = {};
  siteSnap.forEach((d) => {
    const s = d.data();
    sites[d.id] = { ad: s.ad || s.isim || d.id, prim: Number(s.gunlukPrim) || 0 };
  });

  const live = (snap) => {
    const arr = [];
    snap.forEach((d) => {
      const x = { ...d.data(), _docId: d.id };
      if (!x.silinmeTarihi) arr.push(x);
    });
    return arr;
  };

  const att = live(ykSnap).sort((a, b) => new Date(a.tarih) - new Date(b.tarih));
  const adAll = live(adSnap).sort(
    (a, b) => new Date(a.islemTarihi) - new Date(b.islemTarihi)
  );
  const pays = live(paySnap).sort(
    (a, b) => new Date(a.odemeTarihi) - new Date(b.odemeTarihi)
  );

  const primOf = (a) => {
    if (!receivesBonus) return 0;
    const eq = eqOf(a.durum);
    if (eq === 0 || !a.santiyeId) return 0;
    const s = sites[a.santiyeId];
    return s && s.prim > 0 ? s.prim * eq : 0;
  };

  const inMonth = (iso, key) => String(iso || '').slice(0, 7) === key;

  const sum = (arr) => arr.reduce((s, x) => s + (Number(x.tutar) || 0), 0);

  // ---- Ay bölümleri ----
  const H = [];
  const genel = { eq: 0, yevmiye: 0, prim: 0, avans: 0, borc: 0, odenen: 0 };

  for (const key of months) {
    const attM = att.filter((a) => inMonth(a.tarih, key));
    const adsM = adAll.filter((x) => x.tur === 'advance' && inMonth(x.islemTarihi, key));
    const debtsM = adAll.filter((x) => x.tur === 'debt' && inMonth(x.islemTarihi, key));
    const paysM = pays.filter((x) => inMonth(x.odemeTarihi, key));

    const eq = attM.reduce((s, a) => s + eqOf(a.durum), 0);
    const yevmiye = eq * wage;
    const prim = attM.reduce((s, a) => s + primOf(a), 0);
    const avans = sum(adsM);
    const borc = sum(debtsM);
    const odenen = sum(paysM);

    genel.eq += eq;
    genel.yevmiye += yevmiye;
    genel.prim += prim;
    genel.avans += avans;
    genel.borc += borc;
    genel.odenen += odenen;

    H.push(`<section class="ay"><h2>${fmtAy(key)}</h2>`);

    // Gün gün puantaj
    H.push(`<h3>Puantaj — gün gün (${attM.length} kayıt)</h3>`);
    if (attM.length) {
      H.push(
        tbl(
          [
            { t: 'Tarih' },
            { t: 'Gün' },
            { t: 'Durum' },
            { t: 'Şantiye' },
            { t: 'Gün karş.', num: 1 },
            { t: 'Yevmiye', num: 1 },
            { t: 'Prim', num: 1 },
            { t: 'Toplam', num: 1 },
          ],
          attM.map((a) => {
            const e = eqOf(a.durum);
            const p = primOf(a);
            const site = a.santiyeId ? (sites[a.santiyeId] || {}).ad || '-' : '-';
            return [
              fmtDate(a.tarih),
              fmtGun(a.tarih),
              DURUM[a.durum] || esc(a.durum),
              esc(site),
              NUM(e),
              TL(e * wage),
              TL(p),
              `<b>${TL(e * wage + p)}</b>`,
            ];
          }),
          [
            '<b>TOPLAM</b>', '', '', '',
            `<b>${NUM(eq)}</b>`,
            `<b>${TL(yevmiye)}</b>`,
            `<b>${TL(prim)}</b>`,
            `<b>${TL(yevmiye + prim)}</b>`,
          ]
        )
      );
    } else {
      H.push(`<p class="empty">Bu ay yoklama kaydı yok.</p>`);
    }

    // Avanslar
    H.push(`<h3>Avanslar (${adsM.length} kayıt — ${TL(avans)})</h3>`);
    if (adsM.length) {
      H.push(
        tbl(
          [{ t: 'Tarih' }, { t: 'Tutar', num: 1 }, { t: 'Not' }],
          adsM.map((x) => [fmtDate(x.islemTarihi), TL(x.tutar), esc(x.not || '')]),
          ['<b>TOPLAM</b>', `<b>${TL(avans)}</b>`, '']
        )
      );
    } else {
      H.push(`<p class="empty">Kayıt yok.</p>`);
    }

    // Borçlar
    H.push(`<h3>İşveren borçları (${debtsM.length} kayıt — ${TL(borc)})</h3>`);
    if (debtsM.length) {
      H.push(
        tbl(
          [{ t: 'Tarih' }, { t: 'Tutar', num: 1 }, { t: 'Not' }],
          debtsM.map((x) => [fmtDate(x.islemTarihi), TL(x.tutar), esc(x.not || '')]),
          ['<b>TOPLAM</b>', `<b>${TL(borc)}</b>`, '']
        )
      );
    } else {
      H.push(`<p class="empty">Kayıt yok.</p>`);
    }

    // Maaş ödemeleri
    H.push(`<h3>Maaş ödemeleri (${paysM.length} kayıt — ${TL(odenen)})</h3>`);
    if (paysM.length) {
      H.push(
        tbl(
          [
            { t: 'Ödeme tarihi' },
            { t: 'Dönem' },
            { t: 'Tutar', num: 1 },
            { t: 'Not' },
          ],
          paysM.map((x) => [
            fmtDate(x.odemeTarihi),
            `${fmtDate(x.donemBaslangici)} → ${fmtDate(x.donemBitisi)}`,
            TL(x.tutar),
            esc(x.not || ''),
          ]),
          ['<b>TOPLAM</b>', '', `<b>${TL(odenen)}</b>`, '']
        )
      );
    } else {
      H.push(`<p class="empty">Bu ay ödeme yok.</p>`);
    }

    // Ay özeti
    const ayNet = yevmiye + prim + borc - avans - odenen;
    H.push(`<h3>${fmtAy(key)} özeti</h3>
<table class="ozet"><tbody>
  <tr><td>Yevmiye hakedişi (${NUM(eq)} gün × ${TL(wage)})</td><td class="num">${TL(yevmiye)}</td></tr>
  <tr><td>Şantiye primi</td><td class="num">+ ${TL(prim)}</td></tr>
  <tr><td>İşveren borcu</td><td class="num">+ ${TL(borc)}</td></tr>
  <tr><td>Avanslar</td><td class="num">− ${TL(avans)}</td></tr>
  <tr><td>Ödenen maaşlar</td><td class="num">− ${TL(odenen)}</td></tr>
  <tr class="sonuc ${ayNet >= 0.005 ? 'pos' : ayNet <= -0.005 ? 'neg' : ''}">
    <td><b>AY NET ETKİSİ</b></td><td class="num"><b>${TL(ayNet)}</b></td></tr>
</tbody></table>`);

    H.push(`</section>`);
  }

  // ---- Genel özet (kapsanan aylar) ----
  const hakedis = genel.yevmiye + genel.prim;
  const net = hakedis + genel.borc - genel.avans - genel.odenen;
  const kapsam = months.map(fmtAy).join(' + ');

  const stamp = new Date().toLocaleDateString('tr-TR');
  const html = `<!DOCTYPE html>
<html lang="tr"><head><meta charset="utf-8">
<title>${esc(w.adSoyad)} — ${esc(kapsam)}</title>
<style>
  * { box-sizing: border-box; }
  body {
    font: 10pt/1.5 -apple-system, "Helvetica Neue", Arial, sans-serif;
    color: #1a1a1a; margin: 0; padding: 24px 28px;
  }
  h1 { font-size: 16pt; margin: 0 0 2px; }
  h2 { font-size: 13pt; margin: 0 0 6px; border-bottom: 2px solid #1a1a1a; padding-bottom: 3px; }
  h3 { font-size: 10.5pt; margin: 14px 0 4px; }
  .sub { color: #555; margin: 0 0 14px; }
  .meta { color: #444; margin: 0 0 6px; }
  .empty { color: #888; font-style: italic; margin: 2px 0 6px; }
  table { border-collapse: collapse; width: 100%; margin: 2px 0 8px; }
  th, td { border: 1px solid #bbb; padding: 3.5px 7px; text-align: left; }
  th { background: #f0f0f0; font-weight: 600; }
  td.num, th.num { text-align: right; white-space: nowrap; }
  tfoot td { background: #f7f7f7; }
  .ozet { width: 60%; }
  .ozet .sonuc td { border-top: 2px solid #1a1a1a; font-size: 11pt; }
  .pos { color: #0a6b2d; }
  .neg { color: #b00020; }
  .ay { page-break-before: always; }
  .ay:first-of-type { page-break-before: auto; }
  .foot { margin-top: 16px; color: #777; font-size: 8pt; }
  @page { margin: 12mm 10mm; }
</style></head><body>

<h1>${esc((w.adSoyad || '').toLocaleUpperCase('tr-TR'))} — ${esc(kapsam.toLocaleUpperCase('tr-TR'))} RAPORU</h1>
<p class="sub">Rapor tarihi: ${stamp} &middot; Yevmiye: <b>${TL(wage)}</b>${receivesBonus ? '' : ' &middot; Prim almıyor'} &middot; Durum: ${w.aktifMi !== false ? 'Aktif' : 'Ayrıldı'}</p>

<h3>Genel özet — ${esc(kapsam)}</h3>
<table class="ozet"><tbody>
  <tr><td>Yevmiye hakedişi (${NUM(genel.eq)} gün × ${TL(wage)})</td><td class="num">${TL(genel.yevmiye)}</td></tr>
  <tr><td>Şantiye primi</td><td class="num">+ ${TL(genel.prim)}</td></tr>
  <tr><td>İşveren borcu</td><td class="num">+ ${TL(genel.borc)}</td></tr>
  <tr><td>Avanslar</td><td class="num">− ${TL(genel.avans)}</td></tr>
  <tr><td>Ödenen maaşlar</td><td class="num">− ${TL(genel.odenen)}</td></tr>
  <tr class="sonuc ${net >= 0.005 ? 'pos' : net <= -0.005 ? 'neg' : ''}">
    <td><b>DÖNEM NET ETKİSİ</b></td><td class="num"><b>${TL(net)}</b></td></tr>
</tbody></table>
<p class="meta">Bu tutar yalnızca ${esc(kapsam)} kayıtlarının net etkisidir; çalışanın genel
bakiyesi için tüm geçmişi kapsayan tam_rapor.js çıktısına bakılmalıdır.</p>

${H.join('\n')}

<p class="foot">Kaynak: Firestore &middot; organizations/${esc(orgRef.id)} &middot; calisanlar/${esc(workerId)} &middot; silinmiş kayıtlar hariç &middot; uygulamadaki PayrollCalculator mantığıyla birebir.</p>
</body></html>`;

  const slug = normalize(w.adSoyad).replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '');
  const base = `${slug}_${months.join('_')}`;
  const htmlPath = path.join(os.tmpdir(), `${base}.html`);
  const pdfPath = path.join(os.homedir(), 'Desktop', `${base}.pdf`);
  fs.writeFileSync(htmlPath, html, 'utf8');

  const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
  try {
    execSync(
      `"${CHROME}" --headless --disable-gpu --no-pdf-header-footer ` +
        `--print-to-pdf="${pdfPath}" "file://${htmlPath}" 2>/dev/null`
    );
    console.log(`→ PDF yazıldı: ${pdfPath}`);
  } catch (e) {
    const fallback = path.join(os.homedir(), 'Desktop', `${base}.html`);
    fs.copyFileSync(htmlPath, fallback);
    console.error(`(PDF üretilemedi: ${e.message}) → HTML: ${fallback}`);
  }

  // Terminale kısa özet
  console.log(`\n${w.adSoyad} — ${kapsam}`);
  console.log(`  Gün karşılığı : ${NUM(genel.eq)}`);
  console.log(`  Yevmiye       : ${TL(genel.yevmiye)}`);
  console.log(`  Prim          : ${TL(genel.prim)}`);
  console.log(`  Borç (+)      : ${TL(genel.borc)}`);
  console.log(`  Avans (−)     : ${TL(genel.avans)}`);
  console.log(`  Ödenen (−)    : ${TL(genel.odenen)}`);
  console.log(`  Dönem net     : ${TL(net)}`);
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
