// Kesilme (senkron kesintisi) analizi — Firestore'un her belge için tuttuğu
// SUNUCU zaman damgalarından, verinin Firebase'e ulaşmasının geciktiği
// dönemleri (kesilmeleri) OTOMATİK tespit eder ve Masaüstüne PDF üretir.
//
// Mantık:
//   olusturulmaTarihi = kullanıcının cihazda kaydı girdiği an (uygulama offline-first)
//   createTime        = belgenin Firestore'a İLK ulaştığı an (sunucu, değişmez)
//   Bu ikisi arasındaki gecikme (lag) büyükse, o kayıt bir kesilme sırasında
//   cihazda birikmiş, kesilme bitince toptan akmış demektir.
//
// Bir "kesilme" = aynı toplu-akışta (recovery) sunucuya ulaşan, girişleri günlere
// yayılmış gecikmeli kayıtlar kümesi. Kesilme penceresi = en erken giriş → kurtarma anı.
//
// Kullanım:
//   node kesilme_analizi.js            (varsayılan gecikme eşiği 24 saat)
//   node kesilme_analizi.js 12         (eşiği 12 saate düşür — daha hassas)
//
// Salt-okunurdur, hiçbir şey yazmaz. Service account: serviceAccount.json.

const admin = require('firebase-admin');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

const LAG_SAAT = Number(process.argv[2]) || 12; // gecikme eşiği (saat)

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

// ---- Zaman yardımcıları (Türkiye saati, UTC+3) --------------------------
const TR_OFFSET = 3 * 3600 * 1000;
const trStr = (ms) =>
  ms == null ? '—' : new Date(ms + TR_OFFSET).toISOString().slice(0, 19).replace('T', ' ');
const trDay = (ms) => (ms == null ? null : new Date(ms + TR_OFFSET).toISOString().slice(0, 10));
const dayOfIso = (iso) => String(iso || '').slice(0, 10);
const esc = (s) =>
  String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const AYLAR = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
const fmtGun = (isoDay) => {
  if (!isoDay) return '—';
  const [y, m, d] = isoDay.split('-');
  return `${Number(d)} ${AYLAR[Number(m) - 1]} ${y}`;
};
const KOL_AD = {
  yoklama: 'Yoklama',
  avans_borclar: 'Avans/Borç',
  maas_odemeleri: 'Maaş ödemesi',
  calisanlar: 'Çalışan',
  santiyeler: 'Şantiye',
};

// ---- Veri çek -----------------------------------------------------------
const COLS = ['yoklama', 'avans_borclar', 'maas_odemeleri', 'calisanlar', 'santiyeler'];

async function fetchDocs(orgRef) {
  const docs = [];
  for (const c of COLS) {
    const snap = await orgRef.collection(c).get();
    snap.forEach((d) => {
      const x = d.data();
      const arrival = d.createTime ? d.createTime.toMillis() : null;   // sunucuya ulaşma
      const rewrite = d.updateTime ? d.updateTime.toMillis() : null;   // son sunucu yazması
      const entry = x.olusturulmaTarihi ? Date.parse(x.olusturulmaTarihi) : null; // cihaz girişi
      docs.push({ col: c, id: d.id, arrival, rewrite, entry });
    });
  }
  return docs;
}

// ---- Kesilmeleri tespit et ----------------------------------------------
// Yöntem: kaydın GİRİLDİĞİ gün (olusturulmaTarihi) ile Firebase'e ULAŞTIĞI gün
// (createTime) karşılaştırılır. Ulaşma, girişten LAG_SAAT sonrasına sarkmışsa o
// kayıt "gecikmeli"dir. Gecikmeli kayıtların giriş günleri ardışıksa (aralarında
// sağlıklı senkronla geçen bir gün yoksa) bunlar TEK bir kesilme penceresidir.
const DAY = 86400000;
const trMidnightUtc = (dayStr) => Date.parse(dayStr + 'T00:00:00Z') - TR_OFFSET;
const nextDay = (dayStr) => new Date(Date.parse(dayStr + 'T00:00:00Z') + DAY).toISOString().slice(0, 10);

function detectOutages(docs) {
  const THRESH = LAG_SAAT * 3600 * 1000;
  const isDelayed = (d) => d.entry != null && d.arrival != null && d.arrival - d.entry > THRESH;

  // Gecikmeli kayıtları giriş gününe göre grupla
  const dayMap = {}; // entryDay -> [docs]
  docs.filter(isDelayed).forEach((d) => {
    const g = trDay(d.entry);
    (dayMap[g] = dayMap[g] || []).push(d);
  });
  const outageDays = Object.keys(dayMap).sort();
  if (!outageDays.length) return [];

  // Sağlıklı senkronla (zamanında) ulaşan kayıtların giriş günleri — pencereyi böler
  const healthyDays = new Set();
  docs.forEach((d) => {
    if (d.entry != null && d.arrival != null && d.arrival - d.entry <= THRESH)
      healthyDays.add(trDay(d.entry));
  });

  // Ardışık gecikmeli giriş günlerini pencerelere birleştir
  // (aralarındaki BOŞ günler pencereyi bölmez; ancak SAĞLIKLI bir gün bölerse ayrı kesilme)
  const windows = [];
  let cur = null;
  for (const day of outageDays) {
    if (cur) {
      let broken = false;
      for (let ds = nextDay(cur.lastDay); ds < day; ds = nextDay(ds)) {
        if (healthyDays.has(ds)) { broken = true; break; }
      }
      if (broken) cur = null;
    }
    if (!cur) { cur = { days: [], lastDay: day }; windows.push(cur); }
    cur.days.push(day);
    cur.lastDay = day;
  }

  // Zamanında ulaşan tüm yazmalar — "son sağlıklı yazma" için
  const healthyArrivals = docs
    .filter((d) => d.arrival != null && (d.entry == null || d.arrival - d.entry <= THRESH))
    .map((d) => d.arrival)
    .sort((a, b) => a - b);

  return windows.map((w) => {
    const wdocs = w.days.flatMap((day) => dayMap[day]);
    const arrivals = wdocs.map((d) => d.arrival);
    const flushStart = Math.min(...arrivals);
    const flushEnd = Math.max(...arrivals);
    const winStartUtc = trMidnightUtc(w.days[0]);
    const lastGood = healthyArrivals.filter((t) => t < winStartUtc).pop() || null;

    const byCol = {};
    wdocs.forEach((d) => { byCol[d.col] = (byCol[d.col] || 0) + 1; });
    const byDay = {};
    wdocs.forEach((d) => { const g = trDay(d.entry); byDay[g] = (byDay[g] || 0) + 1; });

    return {
      adet: wdocs.length,
      startDay: w.days[0],           // takılan verinin ilk giriş günü
      endDay: w.days[w.days.length - 1], // takılan verinin son giriş günü
      lastGood,                      // kesinti öncesi son sağlıklı yazma (ms)
      flushStart,                    // kurtarmanın başladığı an (ms)
      flushEnd,                      // kurtarmanın bittiği an (ms)
      byCol,
      byDay,
    };
  });
}

// ---- Terminal raporu ----------------------------------------------------
function printOutage(o, i) {
  const durationDays = o.lastGood ? ((o.flushStart - o.lastGood) / DAY).toFixed(1) : '?';
  console.log(`\n──────── KESİLME #${i + 1} ────────`);
  console.log(`  Takılan veri      : ${o.startDay} – ${o.endDay} arası girilen ${o.adet} kayıt Firebase'e ulaşamadı`);
  console.log(`  Son sağlıklı yazma: ${trStr(o.lastGood)} TR`);
  console.log(`  Kesinti süresi    : ~${durationDays} gün (son sağlıklı yazmadan kurtarmaya)`);
  console.log(`  Kurtarma (akış)   : ${trStr(o.flushStart)} → ${trStr(o.flushEnd)} TR`);
  console.log(`  Etki              : ${Object.entries(o.byCol).map(([c, n]) => `${KOL_AD[c] || c}: ${n}`).join('  ·  ')}`);
}

// ---- HTML / PDF ---------------------------------------------------------
function buildHtml(orgId, outages, docCount) {
  const now = new Date().toLocaleString('tr-TR');

  const section = (o, i) => {
    const durationDays = o.lastGood ? ((o.flushStart - o.lastGood) / DAY).toFixed(1) : '?';
    const dayRows = Object.keys(o.byDay).sort()
      .map((g) => `<tr><td>${fmtGun(g)}</td><td class="n">${o.byDay[g]}</td></tr>`).join('');
    const colChips = Object.entries(o.byCol)
      .map(([c, n]) => `<span class="chip">${esc(KOL_AD[c] || c)}: <b>${n}</b></span>`).join(' ');
    return `
    <section>
      <h2>Kesilme #${i + 1} — ${fmtGun(o.startDay)} → ${fmtGun(o.endDay)} arası girilen veri</h2>
      <div class="grid">
        <div class="box"><div class="v">~${durationDays} gün</div><div class="l">Kesinti süresi</div></div>
        <div class="box"><div class="v">${o.adet}</div><div class="l">Takılan kayıt (kurtarıldı)</div></div>
        <div class="box"><div class="v">0</div><div class="l">Kaybolan kayıt</div></div>
      </div>
      <table class="kv">
        <tr><td>Son sağlıklı Firebase yazması</td><td><b>${esc(trStr(o.lastGood))}</b> (TR)</td></tr>
        <tr><td>Kesinti boyunca Firebase'e ulaşan veri</td><td><b>0 kayıt</b> — ${fmtGun(o.startDay)} – ${fmtGun(o.endDay)} arası girilenlerin tamamı cihazlarda bekledi</td></tr>
        <tr><td>Kurtarma (kuyruğun aktığı an)</td><td><b>${esc(trStr(o.flushStart))}</b> → ${esc(trStr(o.flushEnd))} (TR)</td></tr>
        <tr><td>Etki</td><td>${colChips}</td></tr>
      </table>
      <h3>Kesinti boyunca biriken ve sonradan kurtarılan kayıtlar (girildiği güne göre)</h3>
      <table class="hist"><thead><tr><th>Verinin girildiği gün</th><th class="n">Kayıt</th></tr></thead>
        <tbody>${dayRows}<tr class="foot"><td><b>TOPLAM</b></td><td class="n"><b>${o.adet}</b></td></tr></tbody></table>
    </section>`;
  };

  const body = outages.length
    ? outages.map(section).join('\n')
    : `<section><p class="ok">✓ İncelenen ${docCount} kayıtta ${LAG_SAAT} saati aşan senkron kesilmesi bulunamadı. Tüm veriler girildikten kısa süre sonra Firebase'e ulaşmış.</p></section>`;

  return `<!DOCTYPE html>
<html lang="tr"><head><meta charset="utf-8">
<title>Firebase Senkron Kesilme Analizi</title>
<style>
  * { box-sizing: border-box; }
  body { font: 10pt/1.5 -apple-system,"Helvetica Neue",Arial,sans-serif; color:#1a1a1a; margin:0; padding:26px 30px; }
  h1 { font-size:18pt; margin:0 0 2px; }
  .sub { color:#555; margin:0 0 6px; }
  .lead { background:#f4f7fb; border:1px solid #dbe6fb; border-radius:8px; padding:10px 14px; margin:12px 0 20px; color:#28406b; }
  h2 { font-size:13pt; margin:22px 0 8px; border-bottom:2px solid #1a1a1a; padding-bottom:4px; }
  h3 { font-size:10pt; margin:14px 0 4px; color:#444; }
  .grid { display:flex; gap:10px; margin:8px 0 12px; }
  .box { flex:1; border:1px solid #ccc; border-radius:8px; padding:10px 12px; background:#fafafa; text-align:center; }
  .box .v { font-size:16pt; font-weight:700; color:#b00020; }
  .box .l { font-size:8pt; color:#666; text-transform:uppercase; letter-spacing:.3px; }
  table { border-collapse:collapse; margin:4px 0 8px; }
  td, th { border:1px solid #ccc; padding:4px 9px; text-align:left; vertical-align:top; }
  th { background:#f0f0f0; font-size:8.5pt; }
  td.n, th.n { text-align:right; white-space:nowrap; }
  table.kv { width:100%; } table.kv td:first-child { width:38%; color:#444; }
  table.hist { width:52%; } tr.foot td { background:#f7f7f7; }
  .chip { display:inline-block; background:#eef1f5; border:1px solid #d5dbe3; border-radius:12px; padding:1px 9px; margin:0 3px 3px 0; font-size:8.5pt; }
  .ok { background:#e7f6ec; border:1px solid #b7e0c4; border-radius:8px; padding:12px 16px; color:#0a6b2d; }
  .foot-note { margin-top:22px; color:#888; font-size:8pt; border-top:1px solid #eee; padding-top:8px; }
  @page { size:A4; margin:14mm; }
</style></head><body>
  <h1>Firebase Senkron Kesilme Analizi</h1>
  <p class="sub">Rapor: ${esc(now)} &middot; Organizasyon: ${esc(orgId)} &middot; İncelenen kayıt: ${docCount} &middot; Gecikme eşiği: ${LAG_SAAT} saat</p>
  <p class="lead"><b>Bu rapor nasıl üretildi?</b> Firestore her belge için, verinin sunucuya <i>ilk ulaştığı</i> anı (createTime) değiştirmeden saklar. Uygulama çevrimdışı çalıştığı için kaydın cihazda girildiği an ile Firebase'e ulaştığı an karşılaştırılır. Aradaki gecikme bir kesintiye işaret eder. <b>Kesinti boyunca girilen veri kaybolmaz</b> — cihazda birikir ve bağlantı/erişim düzelince toptan Firebase'e akar. Aşağıda bu akışların tarih ve saatleri yer alır.</p>
  ${body}
  <p class="foot-note">Kaynak: Firestore sunucu zaman damgaları (createTime / updateTime) + uygulama giriş damgası (olusturulmaTarihi). Salt-okunur analiz; hiçbir veri değiştirilmedi. Saatler Türkiye saatidir (UTC+3).</p>
</body></html>`;
}

// ---- main ---------------------------------------------------------------
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

async function run() {
  const orgs = await db.collection('organizations').listDocuments();
  const desktop = path.join(os.homedir(), 'Desktop');
  const stamp = new Date().toISOString().slice(0, 10);

  for (const orgRef of orgs) {
    const docs = await fetchDocs(orgRef);
    const outages = detectOutages(docs);

    console.log(`\n══════════════════════════════════════════════`);
    console.log(`Organizasyon: ${orgRef.id}`);
    console.log(`İncelenen kayıt: ${docs.length} · Gecikme eşiği: ${LAG_SAAT} saat`);
    if (!outages.length) {
      console.log(`✓ Kesilme bulunamadı — tüm veriler zamanında Firebase'e ulaşmış.`);
    } else {
      console.log(`⚠ ${outages.length} kesilme tespit edildi:`);
      outages.forEach(printOutage);
    }

    const html = buildHtml(orgRef.id, outages, docs.length);
    const base = orgs.length > 1
      ? `kesilme_analizi_${orgRef.id}_${stamp}`
      : `kesilme_analizi_${stamp}`;
    const htmlPath = path.join(os.tmpdir(), `${base}.html`);
    const pdfPath = path.join(desktop, `${base}.pdf`);
    fs.writeFileSync(htmlPath, html, 'utf8');
    try {
      execSync(
        `"${CHROME}" --headless --disable-gpu --no-pdf-header-footer ` +
          `--print-to-pdf="${pdfPath}" "file://${htmlPath}" 2>/dev/null`
      );
      console.log(`\n→ PDF yazıldı: ${pdfPath}`);
    } catch (e) {
      const fb = path.join(desktop, `${base}.html`);
      fs.copyFileSync(htmlPath, fb);
      console.error(`(PDF üretilemedi: ${e.message}) → HTML: ${fb}`);
    }
  }
}

run().then(() => process.exit(0)).catch((e) => {
  console.error('HATA:', e);
  process.exit(99);
});
