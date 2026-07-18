// "Devreden bakiye" açıklama raporu — müşteriye gösterilmek üzere sade dille,
// GERÇEK bir çalışanın verisinden devredenin ne olduğunu ve nereden geldiğini
// anlatan tek sayfalık bir PDF üretir.
//
// Devreden = (kapalı/ödenmiş dönemlerde çalışanın net hakkı) − (o dönemler için
//            ödenmiş toplam maaş).  Sıfır değilse: ya eksik/fazla ödenmiş, ya da
//            ödenmiş bir döneme sonradan kayıt gelmiş (ör. senkron kesintisi).
//
// Kullanım:
//   node devreden_anlat.js                 (varsayılan örnek: hayrettin)
//   node devreden_anlat.js "yusuf"         (ada göre çalışan seç)
//
// Salt-okunur. Service account: serviceAccount.json.

const admin = require('firebase-admin');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');

const NAME = process.argv[2] || 'hayrettin';

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error(`Service account JSON bulunamadı: ${serviceAccountPath}`);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(require(serviceAccountPath)) });
const db = admin.firestore();

// ---- yardımcılar --------------------------------------------------------
const TL = (n) =>
  `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} ₺`;
const d0 = (iso) => { const d = new Date(iso); return new Date(d.getFullYear(), d.getMonth(), d.getDate()); };
const gg = (iso) => (iso ? d0(iso).toLocaleDateString('tr-TR') : '—');
const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);
const trStamp = (ms) => (ms == null ? '—' : new Date(ms + 3 * 3600 * 1000).toISOString().slice(0, 16).replace('T', ' '));
const AY = ['Ocak','Şubat','Mart','Nisan','Mayıs','Haziran','Temmuz','Ağustos','Eylül','Ekim','Kasım','Aralık'];
const gunKisa = (iso) => { const d = d0(iso); return `${d.getDate()} ${AY[d.getMonth()]}`; };
const durumAd = (s) => (s === 'worked' ? 'Tam gün' : s === 'half_day' || s === 'halfDay' ? 'Yarım gün' : s === 'absent' ? 'Gelmedi' : s === 'leave' ? 'İzinli' : s);

async function pickWorker(orgRef) {
  const [wS, sS, yS, aS, pS] = await Promise.all([
    orgRef.collection('calisanlar').get(),
    orgRef.collection('santiyeler').get(),
    orgRef.collection('yoklama').get(),
    orgRef.collection('avans_borclar').get(),
    orgRef.collection('maas_odemeleri').get(),
  ]);
  const sites = {};
  sS.forEach((d) => (sites[d.id] = { prim: Number(d.data().gunlukPrim) || 0 }));
  let W = null;
  wS.forEach((d) => {
    const x = d.data();
    if (x.silinmeTarihi) return;
    if (String(x.adSoyad || '').toLocaleLowerCase('tr').includes(NAME.toLocaleLowerCase('tr'))) W = { id: d.id, ...x };
  });
  if (!W) return null;

  const wage = Number(W.gunlukUcret) || 0;
  const bonus = W.primAliyor !== false;
  const primOf = (a) => {
    const eq = eqOf(a.durum);
    if (!bonus || eq === 0 || !a.santiyeId) return 0;
    const s = sites[a.santiyeId];
    return s && s.prim > 0 ? s.prim * eq : 0;
  };

  const att = [], ads = [], pays = [];
  yS.forEach((d) => { const x = d.data(); if (!x.silinmeTarihi && x.calisanId === W.id) att.push({ ...x, _d: d0(x.tarih), _ct: d.createTime ? d.createTime.toMillis() : null }); });
  aS.forEach((d) => { const x = d.data(); if (!x.silinmeTarihi && x.calisanId === W.id) ads.push({ ...x, _d: d0(x.islemTarihi), _ct: d.createTime ? d.createTime.toMillis() : null }); });
  pS.forEach((d) => { const x = d.data(); if (!x.silinmeTarihi && x.calisanId === W.id) pays.push({ ...x, _ct: d.createTime ? d.createTime.toMillis() : null }); });
  pays.sort((a, b) => d0(a.donemBaslangici) - d0(b.donemBaslangici));

  const lastPay = pays.length ? pays.reduce((m, p) => (d0(p.donemBitisi) > d0(m.donemBitisi) ? p : m)) : null;
  const lastEnd = lastPay ? d0(lastPay.donemBitisi) : null;
  const lastPayCt = lastPay ? lastPay._ct : null;

  const closed = (t) => lastEnd && t <= lastEnd.getTime();
  const cGross = att.filter((a) => closed(a._d.getTime())).reduce((s, a) => s + eqOf(a.durum) * wage + primOf(a), 0);
  const cAdv = ads.filter((a) => a.tur === 'advance' && closed(a._d.getTime())).reduce((s, x) => s + (+x.tutar || 0), 0);
  const cDebt = ads.filter((a) => a.tur === 'debt' && closed(a._d.getTime())).reduce((s, x) => s + (+x.tutar || 0), 0);
  const paid = pays.reduce((s, x) => s + (+x.tutar || 0), 0);
  const closedNet = cGross + cDebt - cAdv;
  const devreden = Math.abs(closedNet - paid) < 0.005 ? 0 : closedNet - paid;

  // Son ödemeden SONRA Firebase'e ulaşmış, kapalı döneme ait kayıtlar (devredenin sebebi)
  const late = [
    ...att.filter((a) => closed(a._d.getTime())).map((a) => ({ t: 'Yoklama', d: a._d, ct: a._ct, etki: eqOf(a.durum) * wage + primOf(a), aciklama: durumAd(a.durum) })),
    ...ads.filter((a) => closed(a._d.getTime())).map((a) => ({ t: a.tur === 'advance' ? 'Avans' : 'Borç', d: a._d, ct: a._ct, etki: a.tur === 'advance' ? -(+a.tutar || 0) : +a.tutar || 0, aciklama: a.tur === 'advance' ? 'Avans' : 'İşveren borcu' })),
  ].filter((r) => r.ct && lastPayCt && r.ct > lastPayCt).sort((a, b) => a.ct - b.ct);

  return { W, wage, pays, lastPay, lastEnd, cGross, cAdv, cDebt, closedNet, paid, devreden, late };
}

// ---- HTML ---------------------------------------------------------------
function buildHtml(orgId, R) {
  const { W, pays, lastPay, cGross, cAdv, closedNet, paid, devreden, late } = R;
  const yon = devreden > 0
    ? { renk: 'pos', kim: 'işveren çalışana', cumle: `Yani ${esc(W.adSoyad)} bu döneme kadar hak ettiğinden <b>${TL(devreden)} eksik</b> almış; bu tutar bir sonraki maaşa <b>devrediyor</b>.` }
    : devreden < 0
    ? { renk: 'neg', kim: 'çalışan işverene', cumle: `Yani ${esc(W.adSoyad)} bu döneme kadar hak ettiğinden <b>${TL(Math.abs(devreden))} fazla</b> almış; bu tutar bir sonraki hesaptan <b>düşülüyor</b>.` }
    : { renk: '', kim: '', cumle: 'Bu çalışanda devreden yok — ödenen tutar dönemin netiyle birebir tutuyor.' };

  const lateRows = late.map((r) => `<tr>
      <td>${r.t}</td>
      <td>${gunKisa(r.d.toISOString())}</td>
      <td>${esc(r.aciklama)}</td>
      <td class="n ${r.etki < 0 ? 'neg' : r.etki > 0 ? 'pos' : ''}">${r.etki > 0 ? '+' : ''}${TL(r.etki)}</td>
      <td class="dim">${trStamp(r.ct)}</td>
    </tr>`).join('');

  const now = new Date().toLocaleDateString('tr-TR');

  return `<!DOCTYPE html>
<html lang="tr"><head><meta charset="utf-8"><title>Devreden Bakiye Nedir?</title>
<style>
  * { box-sizing: border-box; }
  body { font: 11pt/1.6 -apple-system,"Helvetica Neue",Arial,sans-serif; color:#1f2430; margin:0; padding:30px 34px; }
  h1 { font-size:22pt; margin:0 0 4px; letter-spacing:-.3px; }
  .sub { color:#667; margin:0 0 20px; font-size:10pt; }
  h2 { font-size:13pt; margin:22px 0 8px; color:#1a2b4a; }
  p { margin:8px 0; }
  .lead { font-size:11.5pt; }
  .box { border-radius:12px; padding:16px 20px; margin:16px 0; }
  .box.acik { background:#eef4ff; border:1px solid #cfe0ff; }
  .box.formul { background:#1a2b4a; color:#fff; text-align:center; }
  .box.formul .f { font-size:13pt; font-weight:600; margin:2px 0; }
  .box.formul .k { color:#a9c2ef; font-size:9.5pt; }
  .box.iyi { background:#e9f8ee; border:1px solid #bfe6cd; }
  .box.iyi b { color:#0a7a35; }
  .emoji { font-size:15pt; }
  table { border-collapse:collapse; width:100%; margin:10px 0; }
  td, th { padding:7px 11px; border-bottom:1px solid #e6e9ef; text-align:left; }
  th { background:#f5f7fb; font-size:9.5pt; color:#556; text-transform:uppercase; letter-spacing:.4px; }
  td.n, th.n { text-align:right; white-space:nowrap; }
  .dim { color:#8892a6; font-size:9pt; }
  .pos { color:#0a7a35; } .neg { color:#c1121f; }
  .hesap { max-width:520px; }
  .hesap td { border:none; padding:5px 11px; }
  .hesap .cizgi td { border-top:2px solid #1a2b4a; }
  .hesap .sonuc td { font-size:13pt; font-weight:700; }
  .num { font-variant-numeric:tabular-nums; }
  .step { display:flex; gap:12px; margin:6px 0; }
  .step .no { flex:0 0 26px; height:26px; border-radius:50%; background:#1a2b4a; color:#fff; text-align:center; line-height:26px; font-weight:700; font-size:10pt; }
  .foot { margin-top:26px; color:#98a1b3; font-size:8.5pt; border-top:1px solid #eee; padding-top:10px; }
  @page { size:A4; margin:16mm; }
</style></head><body>

  <h1>Devreden Bakiye Nedir?</h1>
  <p class="sub">Maaş hesabında "devreden" satırının anlamı ve nereden geldiği &middot; ${now}</p>

  <p class="lead">Uygulama, bir çalışanın maaş bakiyesini <b>iki parça</b> halinde hesaplar:</p>
  <div class="box acik">
    <p style="margin:2px 0"><b>1) Açık dönem</b> — son maaş ödemesinden bugüne kadar biriken hesap (taze kısım).</p>
    <p style="margin:2px 0"><b>2) Devreden</b> — daha önce <b>kapanmış (maaşı ödenmiş)</b> dönemlerden <b>artakalan</b> bakiye.</p>
  </div>
  <p>Ekranda gördüğünüz maaş = <b>açık dönem + devreden</b>. Her dönemin tam karşılığını ödeyip eski kayıtlara hiç dokunulmasa devreden <b>her zaman 0</b> olurdu. 0 değilse, geçmişte ödenen tutar ile o dönemin gerçek karşılığı arasında bir fark kalmış demektir.</p>

  <div class="box formul">
    <div class="k">DEVREDEN =</div>
    <div class="f">Kapalı dönemlerde çalışanın net hakkı &nbsp;−&nbsp; O dönemler için ödenen toplam maaş</div>
  </div>

  <h2>Gerçek bir örnek: ${esc(W.adSoyad)}</h2>
  <p>Son maaş ödemesi <b>${gg(lastPay ? lastPay.odemeTarihi : null)}</b> tarihinde yapıldı ve <b>${gg(lastPay ? lastPay.donemBitisi : null)}</b> tarihine kadarki dönemi kapattı. O tarihe kadarki hesap şöyle:</p>
  <table class="hesap num">
    <tr><td>Kapalı dönemde net hak ettiği</td><td class="n">${TL(closedNet)}</td></tr>
    <tr><td>Bu dönem için eline geçen maaş toplamı</td><td class="n">− ${TL(paid)}</td></tr>
    <tr class="cizgi sonuc ${yon.renk}"><td>= DEVREDEN</td><td class="n">${TL(devreden)}</td></tr>
  </table>
  <p>${yon.cumle}</p>

  ${late.length ? `
  <h2>Peki bu fark neden oluştu?</h2>
  <p>Maaş <b>${gg(lastPay ? lastPay.odemeTarihi : null)}</b> tarihinde verilirken, o döneme ait bazı kayıtlar <b>henüz uygulamaya ulaşmamıştı</b> (senkron kesintisinde takılıydılar). Ödeme yapıldıktan <b>sonra</b> gelen bu kayıtlar dönemin hesabını değiştirdi ve fark "devreden" olarak göründü:</p>
  <table>
    <thead><tr><th>Tür</th><th>İş günü</th><th>Durum</th><th class="n">Hesaba etkisi</th><th>Firebase'e ulaşma</th></tr></thead>
    <tbody>${lateRows}</tbody>
  </table>
  <p class="dim">Not: "Firebase'e ulaşma" sütunundaki tarihler, ödeme gününden sonradır — kayıtlar o an mevcut olsaydı zaten ilk ödemeye dahil edilirlerdi.</p>
  ` : `
  <h2>Peki bu fark neden oluşur?</h2>
  <p>İki sebepten: <b>(1)</b> döneme tam neti yerine yuvarlak/eksik-fazla bir tutar ödendiğinde, <b>(2)</b> maaşı ödenmiş bir döneme sonradan puantaj/avans/borç kaydı girildiğinde.</p>
  `}

  <div class="box iyi">
    <p style="margin:2px 0"><span class="emoji">✅</span> <b>En önemlisi: para kaybolmaz, bu bir hata değildir.</b></p>
    <p style="margin:6px 0 2px">Devreden, uygulamanın <b>"bu döneme kadar şu kadar fark kaldı, bir sonraki maaşta düzeltiyorum"</b> demesidir. Sistem kendi kendini dengeler: ${devreden >= 0 ? 'eksik kalan tutar' : 'fazla ödenen tutar'} bir sonraki hesaba otomatik ${devreden >= 0 ? 'eklenir' : 'düşülür'}, böylece çalışan sonunda hak ettiğinin <b>tam olarak</b> karşılığını alır. Hiçbir gün, hiçbir avans ve hiçbir ödeme kaybolmaz.</p>
  </div>

  <p class="foot">Arı Saha Yönetim &middot; Bu belge çalışanın gerçek kayıtlarından otomatik üretilmiştir &middot; Tutarlar Firebase'deki güncel veriye dayanır.</p>
</body></html>`;
}

// ---- main ---------------------------------------------------------------
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

async function run() {
  const orgs = await db.collection('organizations').listDocuments();
  const desktop = path.join(os.homedir(), 'Desktop');
  for (const orgRef of orgs) {
    const R = await pickWorker(orgRef);
    if (!R) continue;
    const html = buildHtml(orgRef.id, R);
    const trMap = { ç: 'c', ğ: 'g', ı: 'i', ö: 'o', ş: 's', ü: 'u', İ: 'i' };
    const safe = String(R.W.adSoyad)
      .toLocaleLowerCase('tr')
      .replace(/[çğıöşüİ]/g, (c) => trMap[c] || c)
      .replace(/[^a-z0-9]+/g, '_')
      .replace(/^_|_$/g, '');
    const base = `devreden_${safe}`;
    const htmlPath = path.join(os.tmpdir(), `${base}.html`);
    const pdfPath = path.join(desktop, `${base}.pdf`);
    fs.writeFileSync(htmlPath, html, 'utf8');
    try {
      execSync(`"${CHROME}" --headless --disable-gpu --no-pdf-header-footer --print-to-pdf="${pdfPath}" "file://${htmlPath}" 2>/dev/null`);
      console.log(`→ PDF yazıldı: ${pdfPath}`);
    } catch (e) {
      const fb = path.join(desktop, `${base}.html`);
      fs.copyFileSync(htmlPath, fb);
      console.error(`(PDF üretilemedi: ${e.message}) → HTML: ${fb}`);
    }
    console.log(`   ${R.W.adSoyad}: kapalı net ${TL(R.closedNet)} − ödenen ${TL(R.paid)} = devreden ${TL(R.devreden)}`);
    return;
  }
  console.log(`"${NAME}" adında çalışan bulunamadı.`);
}

run().then(() => process.exit(0)).catch((e) => { console.error('HATA:', e); process.exit(99); });
