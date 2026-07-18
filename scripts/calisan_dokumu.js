// Çalışan dökümü — tek bir çalışanın TÜM hareketlerini (yoklama, prim, avans,
// borç, maaş ödemeleri) Firestore'dan çeker ve Masaüstüne detaylı PDF üretir.
//
// Prim ayrı bir kayıt değildir: şantiyenin günlük primi × gün karşılığı olarak
// hesaplanır; sadece primAliyor=true olan personel ve şantiyeye yazılmış
// çalışılan günler için (uygulamadaki "Bölge Primi" ile aynı formül).
//
// Hesap formülü (payroll_repository.dart ile birebir):
//   (gün karşılığı × yevmiye) + prim + borç − avans − ödenen = kalan
//
// Kullanım:
//   node calisan_dokumu.js "abdullah akbaş"              (tüm zamanlar)
//   node calisan_dokumu.js "abdullah akbaş" 2026-07-07   (bu tarihten itibaren)
//   node calisan_dokumu.js "abdullah akbaş" 2026-07-01 2026-07-15
//
// Service account: proje kökünde serviceAccount.json veya SERVICE_ACCOUNT_PATH.

const admin = require('firebase-admin');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

const QUERY = process.argv[2];
const START = process.argv[3] || '0000-01-01';
const END = process.argv[4] || '9999-12-31';

if (!QUERY) {
  console.error('Kullanım: node calisan_dokumu.js <isim> [başlangıç] [bitiş]');
  process.exit(1);
}

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

const normalize = (s) =>
  String(s || '')
    .toLocaleLowerCase('tr-TR')
    .replace(/i̇/g, 'i')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '');

const AYLAR = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
const fmtGun = (isoDay) => {
  const [, m, d] = isoDay.split('-');
  return `${Number(d)} ${AYLAR[Number(m) - 1]}`;
};
const GUNLER = ['Paz', 'Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt'];
const gunAdi = (isoDay) => {
  const [y, m, d] = isoDay.split('-').map(Number);
  return GUNLER[new Date(y, m - 1, d).getDay()];
};

const eqOf = (durum) =>
  durum === 'worked' ? 1.0 : durum === 'half_day' || durum === 'halfDay' ? 0.5 : 0;

const DURUM_AD = {
  worked: ['Tam gün', 'tam'],
  half_day: ['Yarım gün', 'yarim'],
  halfDay: ['Yarım gün', 'yarim'],
  absent: ['Gelmedi', 'yok'],
  leave: ['İzinli', 'izin'],
};
const durumEtiket = (durum) => {
  const [ad, cls] = DURUM_AD[durum] || [durum || '—', 'bos'];
  return `<span class="tag ${cls}">${esc(ad)}</span>`;
};

// ---- Firestore'dan çek --------------------------------------------------
async function fetchWorker(orgRef, worker) {
  const id = worker.id;
  const [ykSnap, adSnap, paySnap] = await Promise.all([
    orgRef.collection('yoklama').where('calisanId', '==', id).get(),
    orgRef.collection('avans_borclar').where('calisanId', '==', id).get(),
    orgRef.collection('maas_odemeleri').where('calisanId', '==', id).get(),
  ]);

  const attendance = [];
  ykSnap.forEach((d) => {
    const x = d.data();
    if (x.silinmeTarihi) return;
    if (!inRange(x.tarih)) return;
    attendance.push({
      gun: dOnly(x.tarih),
      durum: x.durum,
      santiyeId: x.santiyeId || null,
    });
  });
  attendance.sort((a, b) => a.gun.localeCompare(b.gun));

  const hareketler = [];
  adSnap.forEach((d) => {
    const x = d.data();
    if (x.silinmeTarihi) return;
    if (!inRange(x.islemTarihi)) return;
    hareketler.push({
      gun: dOnly(x.islemTarihi),
      tur: x.tur,
      tutar: Number(x.tutar) || 0,
      not: x.not || '',
    });
  });
  hareketler.sort((a, b) => a.gun.localeCompare(b.gun));

  const payments = [];
  paySnap.forEach((d) => {
    const x = d.data();
    if (x.silinmeTarihi) return;
    if (!inRange(x.odemeTarihi)) return;
    payments.push({
      gun: dOnly(x.odemeTarihi),
      tutar: Number(x.tutar) || 0,
      donem:
        x.donemBaslangici && x.donemBitisi
          ? `${fmtGun(dOnly(x.donemBaslangici))} – ${fmtGun(dOnly(x.donemBitisi))}`
          : '—',
      not: x.not || '',
    });
  });
  payments.sort((a, b) => a.gun.localeCompare(b.gun));

  return { worker, attendance, hareketler, payments };
}

// ---- Hesapla ------------------------------------------------------------
function compute(data, sitePrim) {
  const t = {
    tam: 0, yarim: 0, yok: 0, izin: 0, eq: 0,
    prim: 0, avans: 0, borc: 0, odenen: 0,
  };
  const gunler = data.attendance.map((a) => {
    const dayEq = eqOf(a.durum);
    if (a.durum === 'worked') t.tam++;
    else if (a.durum === 'half_day' || a.durum === 'halfDay') t.yarim++;
    else if (a.durum === 'absent') t.yok++;
    else if (a.durum === 'leave') t.izin++;
    t.eq += dayEq;

    let prim = 0;
    if (data.worker.primAliyor && a.santiyeId && dayEq > 0) {
      prim = (sitePrim[a.santiyeId] || 0) * dayEq;
    }
    t.prim += prim;
    const yevmiye = data.worker.yevmiye * dayEq;
    return { ...a, dayEq, yevmiye, prim, toplam: yevmiye + prim };
  });

  data.hareketler.forEach((x) => {
    if (x.tur === 'advance') t.avans += x.tutar;
    else if (x.tur === 'debt') t.borc += x.tutar;
  });
  data.payments.forEach((p) => (t.odenen += p.tutar));

  t.hakedis = t.eq * data.worker.yevmiye;
  t.brut = t.hakedis + t.prim;
  // avans: işveren çalışandan alacaklı (düşülür)
  // borç:  işveren çalışana borçlu (eklenir)
  t.kesinti = t.avans - t.borc;
  t.net = t.brut - t.kesinti;
  t.kalan = t.net - t.odenen;
  return { gunler, t };
}

// ---- HTML ---------------------------------------------------------------
function buildHtml(orgId, sites, sitePrim, data, calc) {
  const { worker } = data;
  const { gunler, t } = calc;
  const now = new Date().toLocaleString('tr-TR');
  const aralikYazi =
    START === '0000-01-01' && END === '9999-12-31'
      ? 'Tüm kayıtlar'
      : `${START} → ${END}`;
  const ilk = data.attendance.length ? data.attendance[0].gun : null;
  const son = data.attendance.length
    ? data.attendance[data.attendance.length - 1].gun
    : null;

  const kart = (etiket, deger, alt, cls) =>
    `<div class="kart ${cls || ''}"><div class="k-deger">${deger}</div><div class="k-etiket">${etiket}</div>${
      alt ? `<div class="k-alt">${alt}</div>` : ''
    }</div>`;

  const kartlar = [
    kart('Gün karşılığı', NUM(t.eq), `${NUM(t.tam)} tam · ${NUM(t.yarim)} yarım`),
    kart('Hakediş', TL(t.hakedis), `${NUM(t.eq)} × ${TL(worker.yevmiye)}`),
    kart('Prim', TL(t.prim), worker.primAliyor ? 'şantiye primi' : 'prim almıyor'),
    kart('Avans', TL(t.avans), 'çalışandan alacak'),
    kart('Borç', TL(t.borc), 'çalışana borç'),
    kart('Ödenen', TL(t.odenen), `${data.payments.length} ödeme`),
    kart(
      t.kalan >= 0 ? 'Kalan (ödenecek)' : 'Fazla ödenmiş',
      TL(Math.abs(t.kalan)),
      'net − ödenen',
      t.kalan >= 0 ? 'vurgu' : 'vurgu eksi'
    ),
  ].join('');

  // Yoklama tablosu
  const ykRows = gunler
    .map(
      (g) => `<tr>
      <td class="c">${fmtGun(g.gun)}</td>
      <td class="c mut">${gunAdi(g.gun)}</td>
      <td>${durumEtiket(g.durum)}</td>
      <td class="s">${
        g.santiyeId
          ? esc(sites[g.santiyeId] || g.santiyeId)
          : '<span class="mut">—</span>'
      }</td>
      <td class="c">${g.dayEq ? NUM(g.dayEq) : '<span class="mut">0</span>'}</td>
      <td class="n">${g.yevmiye ? TL(g.yevmiye) : '<span class="mut">—</span>'}</td>
      <td class="n">${g.prim ? TL(g.prim) : '<span class="mut">—</span>'}</td>
      <td class="n">${g.toplam ? `<b>${TL(g.toplam)}</b>` : '<span class="mut">—</span>'}</td>
    </tr>`
    )
    .join('\n');

  const ykFoot = `<tr class="foot">
    <td colspan="4"><b>TOPLAM (${gunler.length} kayıt)</b></td>
    <td class="c"><b>${NUM(t.eq)}</b></td>
    <td class="n"><b>${TL(t.hakedis)}</b></td>
    <td class="n"><b>${TL(t.prim)}</b></td>
    <td class="n"><b>${TL(t.brut)}</b></td>
  </tr>`;

  // Prim özeti (şantiye bazlı)
  const primBySite = {};
  gunler.forEach((g) => {
    if (!g.prim) return;
    if (!primBySite[g.santiyeId]) primBySite[g.santiyeId] = { eq: 0, tutar: 0 };
    primBySite[g.santiyeId].eq += g.dayEq;
    primBySite[g.santiyeId].tutar += g.prim;
  });
  const primRows = Object.entries(primBySite)
    .map(
      ([sid, v]) => `<tr>
      <td>${esc(sites[sid] || sid)}</td>
      <td class="n">${TL(sitePrim[sid] || 0)}</td>
      <td class="c">${NUM(v.eq)}</td>
      <td class="n"><b>${TL(v.tutar)}</b></td>
    </tr>`
    )
    .join('\n');

  // Avans / borç
  let bakiye = 0;
  const abRows = data.hareketler
    .map((x) => {
      const isAvans = x.tur === 'advance';
      bakiye += isAvans ? x.tutar : -x.tutar;
      return `<tr>
      <td class="c">${fmtGun(x.gun)}</td>
      <td>${
        isAvans
          ? '<span class="tag yok">Avans</span>'
          : '<span class="tag izin">Borç</span>'
      }</td>
      <td class="n">${isAvans ? TL(x.tutar) : '<span class="mut">—</span>'}</td>
      <td class="n">${!isAvans ? TL(x.tutar) : '<span class="mut">—</span>'}</td>
      <td class="n">${TL(bakiye)}</td>
      <td class="s">${esc(x.not) || '<span class="mut">—</span>'}</td>
    </tr>`;
    })
    .join('\n');

  const abFoot = `<tr class="foot">
    <td colspan="2"><b>TOPLAM (${data.hareketler.length} işlem)</b></td>
    <td class="n"><b>${TL(t.avans)}</b></td>
    <td class="n"><b>${TL(t.borc)}</b></td>
    <td class="n"><b>${TL(t.kesinti)}</b></td>
    <td></td>
  </tr>`;

  // Maaş ödemeleri
  const payRows = data.payments
    .map(
      (p) => `<tr>
      <td class="c">${fmtGun(p.gun)}</td>
      <td class="s">${esc(p.donem)}</td>
      <td class="n"><b>${TL(p.tutar)}</b></td>
      <td class="s">${esc(p.not) || '<span class="mut">—</span>'}</td>
    </tr>`
    )
    .join('\n');

  const payFoot = `<tr class="foot">
    <td colspan="2"><b>TOPLAM (${data.payments.length} ödeme)</b></td>
    <td class="n"><b>${TL(t.odenen)}</b></td>
    <td></td>
  </tr>`;

  // Hesap özeti
  const hesap = [
    ['Hakediş', `${NUM(t.eq)} gün × ${TL(worker.yevmiye)}`, t.hakedis, ''],
    ['Prim', worker.primAliyor ? 'şantiye günlük primi' : 'prim almıyor', t.prim, ''],
    ['Borç', 'işveren çalışana borçlu (+)', t.borc, ''],
    ['Avans', 'işveren çalışandan alacaklı (−)', -t.avans, 'eksi'],
    ['NET', 'hakediş + prim + borç − avans', t.net, 'ara'],
    ['Ödenen', `${data.payments.length} maaş ödemesi (−)`, -t.odenen, 'eksi'],
    [
      t.kalan >= 0 ? 'KALAN (ödenecek)' : 'FAZLA ÖDENMİŞ',
      'net − ödenen',
      t.kalan,
      'sonuc',
    ],
  ]
    .map(
      ([ad, aciklama, tutar, cls]) => `<tr class="${cls}">
      <td><b>${esc(ad)}</b></td>
      <td class="s">${esc(aciklama)}</td>
      <td class="n"><b>${TL(tutar)}</b></td>
    </tr>`
    )
    .join('\n');

  return `<!doctype html><html lang="tr"><head><meta charset="utf-8">
<title>${esc(worker.ad)} — çalışan dökümü</title>
<style>
  * { box-sizing: border-box; }
  body { font: 9.5pt/1.4 -apple-system, "Helvetica Neue", Arial, sans-serif; color: #1a1a1a; margin: 0; padding: 20px 24px; }
  h1 { font-size: 17pt; margin: 0 0 2px; }
  h2 { font-size: 12pt; margin: 16px 0 6px; border-bottom: 2px solid #1a1a1a; padding-bottom: 3px; }
  .sub { color: #555; margin: 0 0 12px; }
  .kartlar { display: flex; flex-wrap: wrap; gap: 8px; margin: 4px 0 6px; }
  .kart { flex: 1; min-width: 110px; border: 1px solid #ccc; border-radius: 8px; padding: 8px 10px; background: #fafafa; }
  .kart.vurgu { background: #eef6ff; border-color: #7aa7dd; }
  .kart.vurgu.eksi { background: #fdeef0; border-color: #dd7a8a; }
  .k-deger { font-size: 14pt; font-weight: 700; }
  .k-etiket { font-size: 8pt; color: #555; text-transform: uppercase; letter-spacing: .3px; margin-top: 2px; }
  .k-alt { font-size: 8pt; color: #888; margin-top: 1px; }
  table { border-collapse: collapse; width: 100%; margin: 4px 0 8px; }
  th, td { border: 1px solid #ccc; padding: 3px 6px; text-align: left; vertical-align: middle; }
  th { background: #f0f0f0; font-weight: 600; font-size: 8.5pt; }
  td.c, th.c { text-align: center; white-space: nowrap; }
  td.n, th.n { text-align: right; white-space: nowrap; }
  td.s { font-size: 8.5pt; color: #444; }
  tr.foot td { background: #f7f7f7; }
  tr.ara td { background: #eef6ff; }
  tr.sonuc td { background: #1a1a1a; color: #fff; font-size: 11pt; }
  tr.eksi td.n { color: #b00020; }
  .mut { color: #bbb; }
  .tag { display: inline-block; padding: 1px 6px; border-radius: 4px; font-size: 8pt; font-weight: 600; }
  .tag.tam  { background: #d6f0dc; color: #0a6b2d; }
  .tag.yarim{ background: #fdeecb; color: #9a6b00; }
  .tag.yok  { background: #f6d4d8; color: #b00020; }
  .tag.izin { background: #dbe6fb; color: #1f4fa8; }
  .tag.bos  { background: #f2f2f2; color: #999; }
  .rozet { display: inline-block; font-size: 8pt; background: #eee; border: 1px solid #ccc; border-radius: 4px; padding: 1px 6px; color: #555; margin-left: 4px; }
  .foot-note { margin-top: 14px; color: #888; font-size: 7.5pt; }
  .uyari { background: #fff8e1; border: 1px solid #e6c200; border-radius: 6px; padding: 8px 10px; font-size: 8.5pt; margin: 8px 0; }
  @page { size: A4; margin: 10mm; }
</style></head><body>

<h1>${esc(worker.ad)}</h1>
<p class="sub">
  Yevmiye <b>${TL(worker.yevmiye)}</b> &middot;
  ${worker.primAliyor ? 'Prim alıyor' : 'Prim almıyor'} &middot;
  ${worker.aktif ? 'Aktif' : '<b>Ayrıldı / pasif</b>'}
  <span class="rozet">id: ${esc(worker.id.slice(0, 8))}</span><br>
  Kapsam: <b>${esc(aralikYazi)}</b>${
    ilk ? ` &middot; yoklama ${fmtGun(ilk)} → ${fmtGun(son)}` : ''
  } &middot; Rapor: ${esc(now)}
</p>

<div class="kartlar">${kartlar}</div>

<h2>Hesap özeti</h2>
<table>
  <thead><tr><th>Kalem</th><th>Açıklama</th><th class="n">Tutar</th></tr></thead>
  <tbody>${hesap}</tbody>
</table>

<h2>Yoklama (${gunler.length} kayıt — ${NUM(t.eq)} gün karşılığı)</h2>
${
  gunler.length
    ? `<table>
  <thead><tr>
    <th class="c">Tarih</th><th class="c">Gün</th><th>Durum</th><th>Şantiye</th>
    <th class="c">Gün karş.</th><th class="n">Yevmiye</th><th class="n">Prim</th><th class="n">Toplam</th>
  </tr></thead>
  <tbody>${ykRows}${ykFoot}</tbody>
</table>
<p class="foot-note">Yoklama gün bazlıdır; sistemde saat verisi tutulmaz (tam=1, yarım=0.5, gelmedi/izin=0).</p>`
    : '<p class="mut">Bu kapsamda yoklama kaydı yok.</p>'
}

<h2>Prim detayı (${TL(t.prim)})</h2>
${
  primRows
    ? `<table>
  <thead><tr><th>Şantiye</th><th class="n">Günlük prim</th><th class="c">Gün karş.</th><th class="n">Toplam</th></tr></thead>
  <tbody>${primRows}</tbody>
</table>`
    : `<p class="mut">Prim yok.${
        worker.primAliyor
          ? ' (Çalıştığı şantiyelerde günlük prim tanımlı değil.)'
          : ' (Bu personel prim almıyor.)'
      }</p>`
}

<h2>Avans / Borç (${data.hareketler.length} işlem)</h2>
${
  data.hareketler.length
    ? `<table>
  <thead><tr>
    <th class="c">Tarih</th><th>Tür</th><th class="n">Avans</th><th class="n">Borç</th>
    <th class="n">Bakiye</th><th>Not</th>
  </tr></thead>
  <tbody>${abRows}${abFoot}</tbody>
</table>
<p class="foot-note">Avans: işveren çalışandan alacaklı (maaştan düşülür). Borç: işveren çalışana borçlu (maaşa eklenir). Bakiye = kümülatif avans − borç.</p>`
    : '<p class="mut">Bu kapsamda avans/borç kaydı yok.</p>'
}

<h2>Maaş ödemeleri (${data.payments.length} ödeme — ${TL(t.odenen)})</h2>
${
  data.payments.length
    ? `<table>
  <thead><tr><th class="c">Tarih</th><th>Dönem</th><th class="n">Tutar</th><th>Not</th></tr></thead>
  <tbody>${payRows}${payFoot}</tbody>
</table>`
    : '<p class="mut">Bu kapsamda maaş ödemesi yok.</p>'
}

<p class="foot-note">Kaynak: Firestore &middot; organizations/${esc(orgId)} &middot; silinmiş kayıtlar hariç &middot; prim = şantiye günlük primi × gün karşılığı (yalnız prim alan personel, şantiyeye yazılmış çalışılan günler).</p>

</body></html>`;
}

// ---- main ---------------------------------------------------------------
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

async function run() {
  const q = normalize(QUERY);
  const orgs = await db.collection('organizations').listDocuments();
  const desktop = path.join(os.homedir(), 'Desktop');
  let bulundu = 0;

  for (const orgRef of orgs) {
    const [workerSnap, siteSnap] = await Promise.all([
      orgRef.collection('calisanlar').get(),
      orgRef.collection('santiyeler').get(),
    ]);

    const sites = {};
    const sitePrim = {};
    siteSnap.forEach((d) => {
      const s = d.data();
      sites[d.id] = s.ad || s.isim || d.id;
      sitePrim[d.id] = Number(s.gunlukPrim) || 0;
    });

    const matches = [];
    workerSnap.forEach((d) => {
      const w = d.data();
      if (w.silinmeTarihi) return;
      if (!normalize(w.adSoyad).includes(q)) return;
      matches.push({
        id: d.id,
        ad: w.adSoyad || d.id,
        aktif: w.aktifMi !== false,
        yevmiye: Number(w.gunlukUcret) || 0,
        primAliyor: w.primAliyor !== false,
      });
    });

    if (matches.length === 0) continue;
    bulundu += matches.length;

    if (matches.length > 1) {
      console.log(
        `\n⚠ "${QUERY}" için ${matches.length} kayıt eşleşti — her biri için ayrı PDF üretiliyor:`
      );
      matches.forEach((m) =>
        console.log(`   · ${m.ad} (${m.aktif ? 'aktif' : 'pasif'}) id=${m.id}`)
      );
    }

    for (const worker of matches) {
      const data = await fetchWorker(orgRef, worker);
      const calc = compute(data, sitePrim);
      const html = buildHtml(orgRef.id, sites, sitePrim, data, calc);

      const slug = normalize(worker.ad).replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
      const suffix = matches.length > 1 ? `_${worker.id.slice(0, 8)}` : '';
      const base = `calisan_${slug}${suffix}`;
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
        const fallback = path.join(desktop, `${base}.html`);
        fs.copyFileSync(htmlPath, fallback);
        console.error(`(PDF üretilemedi: ${e.message}) → HTML: ${fallback}`);
      }

      const t = calc.t;
      console.log(
        `${worker.ad} — ${worker.aktif ? 'aktif' : 'pasif'} · yevmiye ${TL(worker.yevmiye)}\n` +
          `  Yoklama: ${calc.gunler.length} kayıt · Tam ${t.tam} · Yarım ${t.yarim} · Gelmedi ${t.yok} · İzin ${t.izin} · Gün karş. ${NUM(t.eq)}\n` +
          `  Hakediş ${TL(t.hakedis)} + Prim ${TL(t.prim)} = Brüt ${TL(t.brut)}\n` +
          `  Avans ${TL(t.avans)} · Borç ${TL(t.borc)} → Net ${TL(t.net)}\n` +
          `  Ödenen ${TL(t.odenen)} → ${t.kalan >= 0 ? 'KALAN' : 'FAZLA ÖDENMİŞ'} ${TL(Math.abs(t.kalan))}`
      );
    }
  }

  if (bulundu === 0) console.error(`"${QUERY}" ile eşleşen çalışan bulunamadı.`);
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error(e);
    process.exit(1);
  });
