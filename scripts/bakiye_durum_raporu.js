// Çalışan bakiye durum raporu — "kimde ne çıkıyor, kim etkilenmiş?"
//
// Üç şeyi tek PDF'te toplar:
//   1. YEVMİYE DEĞİŞİMİ ANALİZİ
//      PayrollRepository._lifetimeNet() tüm geçmiş günleri çalışanın BUGÜNKÜ
//      yevmiyesiyle çarpar, ama ödemeler tarihseldir. Yevmiyesi değişen
//      çalışanda geçmiş yeniden fiyatlanır, bakiye şişer, yön dönebilir.
//      Tarihsel yevmiye maas_ozetleri.gunlukDetay[].dailyAmount / dayEquivalent
//      üzerinden geri çıkarılır. Dökümü olmayan dönem ÖLÇÜLEMEZ — rapor bunu
//      açıkça yazar, sessizce "temiz" demez.
//   2. TÜM ÇALIŞANLARIN BAKİYE TABLOSU
//      Uygulamanın gösterdiği net + yön. İşveren "şu yanlış" diye buradan
//      parmak basar.
//   3. DİKKAT ÇEKENLER
//      Mükerrer isimler ve "ödemesi 0 ama avansı yüksek" çalışanlar.
//
// Kullanım:
//   node bakiye_durum_raporu.js
//
// SALT-OKUNUR. Hiçbir veri değiştirmez. Service account: proje kökünde
// serviceAccount.json veya SERVICE_ACCOUNT_PATH env değişkeni.

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
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// ---- yardımcılar ---------------------------------------------------------
const TL = (n) =>
  `${(Number(n) || 0).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} ₺`;

const dayOnly = (iso) => {
  const d = new Date(iso);
  return new Date(d.getFullYear(), d.getMonth(), d.getDate());
};

// Yerel gün anahtarı — toISOString() UTC'ye kaydırdığı için kullanılmaz.
const dkey = (iso) => {
  const d = dayOnly(iso);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
    d.getDate(),
  ).padStart(2, '0')}`;
};

const gg = (iso) => (iso ? dayOnly(iso).toLocaleDateString('tr-TR') : '—');
const esc = (s) =>
  String(s == null ? '' : s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');

// PayrollCalculator.workedEquivalent ile aynı
const eqOf = (durum) =>
  durum === 'worked' ? 1.0 : durum === 'half_day' || durum === 'halfDay' ? 0.5 : 0;

const yonOf = (n) =>
  n > 0.5 ? 'İşveren VERECEKLİ' : n < -0.5 ? 'İşveren ALACAKLI' : 'Kapalı';

const trFold = (s) => {
  const m = { ç: 'c', ğ: 'g', ı: 'i', ö: 'o', ş: 's', ü: 'u', İ: 'i', I: 'i' };
  return String(s || '')
    .toLocaleLowerCase('tr')
    .replace(/[çğıöşüİI]/g, (c) => m[c] || c)
    .replace(/\s+/g, ' ')
    .trim();
};

// ---- analiz --------------------------------------------------------------
async function analyzeOrg(orgRef) {
  const [workerSnap, siteSnap, ykSnap, adSnap, paySnap, ozetSnap] =
    await Promise.all([
      orgRef.collection('calisanlar').get(),
      orgRef.collection('santiyeler').get(),
      orgRef.collection('yoklama').get(),
      orgRef.collection('avans_borclar').get(),
      orgRef.collection('maas_odemeleri').get(),
      orgRef.collection('maas_ozetleri').get(),
    ]);

  const sites = {};
  siteSnap.forEach((d) => {
    sites[d.id] = Number(d.data().gunlukPrim) || 0;
  });

  const byWorker = (snap, field, keepDeleted = false) => {
    const m = {};
    snap.forEach((d) => {
      const x = d.data();
      if (!keepDeleted && x.silinmeTarihi) return;
      (m[x[field]] = m[x[field]] || []).push(x);
    });
    return m;
  };

  const yk = byWorker(ykSnap, 'calisanId');
  const ad = byWorker(adSnap, 'calisanId');
  const pay = byWorker(paySnap, 'calisanId');
  const ozet = byWorker(ozetSnap, 'calisanId');

  const rows = [];

  workerSnap.forEach((d) => {
    const w = d.data();
    if (w.silinmeTarihi) return;

    const id = d.id;
    const wageNow = Number(w.gunlukUcret) || 0;
    const receivesBonus = w.primAliyor !== false;

    const att = (yk[id] || []).map((x) => ({ ...x, _k: dkey(x.tarih) }));
    const ads = ad[id] || [];
    const pays = pay[id] || [];
    const ozets = ozet[id] || [];

    // ---- donmuş dökümlerden tarihsel yevmiyeyi geri çıkar ---------------
    const histWage = {};
    const histBonus = {};
    let parseFails = 0;
    for (const o of ozets) {
      if (!o.gunlukDetay) continue; // eski sürüm özeti: döküm yok
      let days;
      try {
        days = JSON.parse(o.gunlukDetay);
      } catch (e) {
        parseFails++;
        continue;
      }
      if (!Array.isArray(days)) continue;
      for (const day of days) {
        const eq = Number(day.dayEquivalent) || 0;
        if (eq <= 0) continue;
        histWage[dkey(day.date)] = (Number(day.dailyAmount) || 0) / eq;
        histBonus[dkey(day.date)] = Number(day.siteBonus) || 0;
      }
    }

    const wageFirstSeen = {};
    for (const [k, v] of Object.entries(histWage)) {
      const r = Math.round(v * 100) / 100;
      if (!wageFirstSeen[r] || k < wageFirstSeen[r]) wageFirstSeen[r] = k;
    }
    const histWages = Object.entries(wageFirstSeen)
      .map(([wage, first]) => ({ wage: Number(wage), first }))
      .sort((a, b) => a.first.localeCompare(b.first));
    const wageChanged = histWages.some((h) => Math.abs(h.wage - wageNow) > 0.005);

    const primNow = (a) => {
      if (!receivesBonus) return 0;
      const eq = eqOf(a.durum);
      if (eq === 0 || !a.santiyeId) return 0;
      return sites[a.santiyeId] > 0 ? sites[a.santiyeId] * eq : 0;
    };

    // ---- uygulamanın bugün gösterdiği net (_lifetimeNet birebir) --------
    const grossNow = att.reduce((s, a) => s + eqOf(a.durum) * wageNow + primNow(a), 0);
    const advAll = ads
      .filter((x) => x.tur === 'advance')
      .reduce((s, x) => s + (Number(x.tutar) || 0), 0);
    const debtAll = ads
      .filter((x) => x.tur === 'debt')
      .reduce((s, x) => s + (Number(x.tutar) || 0), 0);
    const paidAll = pays.reduce((s, x) => s + (Number(x.tutar) || 0), 0);
    const netNow = grossNow + debtAll - advAll - paidAll;

    // ---- her günü o günkü yevmiyeyle fiyatla ----------------------------
    let coveredDays = 0;
    let uncoveredWorkedDays = 0;
    const grossFixed = att.reduce((s, a) => {
      const eq = eqOf(a.durum);
      if (histWage[a._k] != null) {
        coveredDays++;
        return s + eq * histWage[a._k] + (receivesBonus ? histBonus[a._k] || 0 : 0);
      }
      if (eq > 0) uncoveredWorkedDays++;
      return s + eq * wageNow + primNow(a);
    }, 0);
    const netFixed = grossFixed + debtAll - advAll - paidAll;

    const delta = netNow - netFixed;
    const signFlip =
      (netNow > 0.5 && netFixed < -0.5) || (netNow < -0.5 && netFixed > 0.5);

    // İki ayrı soru, iki ayrı eşik:
    //  probed      → değişikliği GÖREBİLİR miyiz? Tek kapsanmış gün yeter.
    //  fullyCovered→ değişmediğini GARANTİ edebilir miyiz? Tüm günler gerekir.
    // Özetler yalnızca ödenmiş dönemleri kapsadığı için açık dönemi olan
    // çalışanda fullyCovered doğal olarak false kalır.
    const probed = coveredDays > 0;
    const fullyCovered = uncoveredWorkedDays === 0 && coveredDays > 0;

    rows.push({
      ad: w.adSoyad || '(isimsiz)',
      aktif: w.aktifMi !== false,
      ver: Number(w.senkronSurumu) || 0,
      wageNow,
      histWages,
      wageChanged,
      grossNow,
      advAll,
      debtAll,
      paidAll,
      netNow,
      netFixed,
      delta,
      signFlip,
      probed,
      fullyCovered,
      coveredDays,
      uncoveredWorkedDays,
      attDays: att.length,
      parseFails,
      snapshotCount: ozets.length,
      snapshotsWithDetail: ozets.filter((o) => o.gunlukDetay).length,
    });
  });

  // ---- mükerrer isim tespiti --------------------------------------------
  const nameGroups = {};
  for (const r of rows) (nameGroups[trFold(r.ad)] = nameGroups[trFold(r.ad)] || []).push(r);
  const dupes = Object.values(nameGroups).filter((g) => g.length > 1);

  // ---- ödemesi yok ama avansı yüksek ------------------------------------
  const advanceOnly = rows.filter(
    (r) => r.paidAll < 0.5 && r.advAll > 0.5 && r.attDays > 0,
  );

  rows.sort((a, b) => b.netNow - a.netNow);
  return { rows, dupes, advanceOnly };
}

// ---- rapor ---------------------------------------------------------------
function buildHtml(orgId, R) {
  const { rows, dupes, advanceOnly } = R;
  const stamp = new Date().toLocaleString('tr-TR');

  const changed = rows.filter((r) => r.wageChanged);
  const flips = rows.filter((r) => r.signFlip);
  const probed = rows.filter((r) => r.probed);
  const fully = rows.filter((r) => r.fullyCovered);
  const unprobed = rows.filter((r) => !r.probed);
  const totalDelta = rows.reduce((s, r) => s + r.delta, 0);

  // --- 1. yevmiye analizi özeti
  const wageVerdict = changed.length
    ? `<p class="bad"><b>${changed.length} çalışanın yevmiyesi geçmişte farklıydı</b> —
       geçmiş dönemleri bugünkü yevmiyeyle yeniden fiyatlandığı için bakiyeleri
       hatalı. Toplam hayali şişme: <b>${TL(totalDelta)}</b>.
       ${flips.length ? `Bunlardan <b>${flips.length}</b> tanesinde bakiyenin yönü tersine dönmüş.` : ''}</p>`
    : `<p><b>Geçmiş yevmiyesi kısmen okunabilen ${probed.length} çalışanın hiçbirinde
       değişiklik izi yok.</b> Yani bu hatanın şu an birinin bakiyesini bozduğuna dair
       <b>veride kanıt bulunamadı</b>. Ancak bu “hata yok” demek değildir — aşağıdaki
       kapsam uyarısına bakınız.</p>`;

  const wageRows = rows
    .filter((r) => r.wageChanged || r.snapshotsWithDetail > 0)
    .map((r) => {
      const hist = r.histWages.length
        ? r.histWages.map((h) => `${TL(h.wage)} <span class="mut">(${gg(h.first)}'den)</span>`).join('<br>')
        : '<span class="mut">—</span>';
      return `<tr${r.signFlip ? ' class="flip"' : ''}>
  <td class="ad">${esc(r.ad)}${r.signFlip ? '<br><span class="flag">YÖN TERSİNE DÖNMÜŞ</span>' : ''}</td>
  <td class="num">${TL(r.wageNow)}</td>
  <td class="num sm">${hist}</td>
  <td class="num">${TL(r.netNow)}</td>
  <td class="num">${TL(r.netFixed)}</td>
  <td class="num ${Math.abs(r.delta) > 0.5 ? 'bad' : 'mut'}">${TL(r.delta)}</td>
  <td class="sm">${
    r.fullyCovered
      ? '<span class="ok">tüm günler ölçüldü</span>'
      : `<span class="warn">kısmi</span> <span class="mut">${r.coveredDays} gün ölçüldü, ${r.uncoveredWorkedDays} gün dökümsüz</span>`
  }</td>
</tr>`;
    })
    .join('\n');

  // --- 2. bakiye tablosu
  const balRows = rows
    .map((r) => {
      const cls = r.netNow > 0.5 ? 'verecek' : r.netNow < -0.5 ? 'alacak' : 'kapali';
      return `<tr>
  <td class="ad">${esc(r.ad)}${r.aktif ? '' : ' <span class="mut">(ayrıldı)</span>'}</td>
  <td class="num">${TL(r.wageNow)}</td>
  <td class="num">${r.attDays}</td>
  <td class="num">${TL(r.grossNow)}</td>
  <td class="num">${TL(r.advAll)}</td>
  <td class="num">${r.debtAll > 0.5 ? TL(r.debtAll) : '<span class="mut">—</span>'}</td>
  <td class="num">${r.paidAll > 0.5 ? TL(r.paidAll) : '<span class="mut warn">0</span>'}</td>
  <td class="num ${cls}"><b>${TL(r.netNow)}</b></td>
  <td class="sm ${cls}">${yonOf(r.netNow)}</td>
</tr>`;
    })
    .join('\n');

  // --- 3. dikkat çekenler
  const dupeHtml = dupes.length
    ? dupes
        .map(
          (g) =>
            `<li><b>${esc(g[0].ad)}</b> — ${g.length} ayrı kayıt:<br>` +
            g
              .map(
                (r) =>
                  `<span class="mut">“${esc(r.ad)}” · yevmiye ${TL(r.wageNow)} · ${r.attDays} puantaj günü · net ${TL(r.netNow)}</span>`,
              )
              .join('<br>') +
            `</li>`,
        )
        .join('\n')
    : '<li class="mut">Mükerrer isim bulunamadı.</li>';

  const advOnlyHtml = advanceOnly.length
    ? advanceOnly
        .map(
          (r) =>
            `<li><b>${esc(r.ad)}</b> — ${r.attDays} gün çalışmış, brüt ${TL(r.grossNow)}, ` +
            `avans ${TL(r.advAll)}, <b class="warn">maaş ödemesi kaydı yok (0)</b> → net ${TL(r.netNow)}</li>`,
        )
        .join('\n')
    : '<li class="mut">Yok.</li>';

  return `<meta charset="utf-8">
<title>Çalışan Bakiye Durum Raporu</title>
<style>
  @page { size: A4 landscape; margin: 12mm; }
  body { font: 10.5px/1.45 -apple-system, "Helvetica Neue", Arial, sans-serif; color: #1a1a1a; }
  h1 { font-size: 19px; margin: 0 0 2px; }
  h2 { font-size: 13px; margin: 20px 0 7px; padding-bottom: 4px;
       border-bottom: 2px solid #333; }
  .sub { color: #666; font-size: 10.5px; margin-bottom: 14px; }
  .box { border: 1px solid #ddd; border-left: 3px solid #666; background: #fafafa;
         padding: 9px 12px; margin: 0 0 12px; border-radius: 3px; }
  .box.alert { border-left-color: #c00; background: #fdf7f7; }
  .box p { margin: 0 0 5px; } .box p:last-child { margin: 0; }
  table { border-collapse: collapse; width: 100%; }
  th, td { border-bottom: 1px solid #e6e6e6; padding: 5px 6px; vertical-align: top;
           text-align: left; }
  th { background: #f4f4f4; font-size: 9px; text-transform: uppercase;
       letter-spacing: .3px; color: #555; border-bottom: 1.5px solid #ccc; }
  .num { text-align: right; white-space: nowrap; }
  .ad { font-weight: 600; }
  .sm { font-size: 9.5px; }
  .mut { color: #888; font-weight: 400; font-size: 9px; }
  .bad, .verecek { color: #c00; }
  .good, .alacak { color: #0a7d00; }
  .kapali { color: #999; }
  .warn { color: #b36b00; font-weight: 600; }
  .ok { color: #0a7d00; }
  tr.flip { background: #fff6f6; }
  .flag { color: #c00; font-size: 8.5px; font-weight: 700; }
  ul { margin: 6px 0 0; padding-left: 18px; }
  li { margin-bottom: 5px; }
  .note { margin-top: 10px; color: #666; font-size: 9px; line-height: 1.5; }
  .pb { page-break-before: always; }
</style>

<h1>Çalışan Bakiye Durum Raporu</h1>
<div class="sub">${esc(orgId)} · ${stamp} · salt-okunur analiz, hiçbir veri değiştirilmedi</div>

<h2>1. Yevmiye değişimi analizi</h2>
<div class="box ${changed.length ? 'alert' : ''}">
  <p><b>Kontrol edilen hata:</b> Uygulama bakiye hesaplarken tüm geçmiş çalışma
  günlerini çalışanın <b>bugünkü</b> yevmiyesiyle çarpıyor; oysa geçmiş ödemeler
  o günkü yevmiye üzerindendi. Bu yüzden bir çalışana <b>zam yapıldığı anda</b>
  kapanmış ve ödenmiş dönemler yeniden fiyatlanıyor, aradaki fark hayali alacak
  olarak üstüne biniyor — yeterince büyükse bakiyenin yönü tersine dönüyor.</p>
  ${wageVerdict}
</div>

<div class="box">
  <p><b>⚠ Ölçüm kapsamı — bu rapor “sorun yok” demiyor:</b> Geçmiş yevmiye
  yalnızca ödeme anında günlük dökümü dondurulmuş dönemlerden okunabiliyor.
  Uygulamanın eski sürümleri bu dökümü yazmıyordu, yeni dönemler ise henüz
  ödenmediği için dökümü yok.</p>
  <p>Rakamlarla: <b>${probed.length} / ${rows.length}</b> çalışanın geçmiş yevmiyesi
  <b>kısmen</b> okunabildi (değişiklik olsaydı görürdük). <b>${unprobed.length}</b>
  çalışanda <b>hiç okunamadı</b> — bunlarda zam yapılıp yapılmadığı bilinmiyor.
  Ve <b>${fully.length}</b> çalışanın tüm çalışma günleri kapsandı; yani hiçbir
  çalışan için “yevmiyesi kesinlikle hiç değişmedi” <b>garantisi verilemiyor</b>.</p>
</div>

<table>
  <thead><tr>
    <th>Çalışan</th><th class="num">Bugünkü<br>yevmiye</th>
    <th class="num">Geçmişte<br>uygulanan</th>
    <th class="num">Uygulamanın<br>gösterdiği</th><th class="num">Doğrusu</th>
    <th class="num">Fark</th><th>Ölçüm</th>
  </tr></thead>
  <tbody>
${wageRows || '<tr><td colspan="7" class="mut">Günlük dökümü olan hiç özet yok — bu analiz yapılamadı.</td></tr>'}
  </tbody>
</table>
<div class="note">Yalnızca ölçülebilir dökümü olan çalışanlar listelenmiştir.</div>

<h2 class="pb">2. Tüm çalışanların bakiye durumu</h2>
<div class="box">
  <p>Uygulamanın <b>şu an gösterdiği</b> rakamlar. “Verecekli” = işveren çalışana
  borçlu, “Alacaklı” = çalışan işverene borçlu. Hatalı gördüğünüz satırı
  işaretleyin — teşhis oradan devam eder.</p>
</div>
<table>
  <thead><tr>
    <th>Çalışan</th><th class="num">Yevmiye</th><th class="num">Puantaj<br>günü</th>
    <th class="num">Brüt</th><th class="num">Avans</th><th class="num">Borç</th>
    <th class="num">Ödenen<br>maaş</th><th class="num">Net</th><th>Yön</th>
  </tr></thead>
  <tbody>
${balRows}
  </tbody>
</table>

<h2>3. Dikkat çekenler</h2>
<div class="box alert">
  <p><b>Mükerrer çalışan kayıtları</b> — aynı kişi birden fazla kayıtta olabilir.
  Bu durumda puantaj, avans ve ödemeler iki kayda bölünür; işveren birine bakarken
  diğerindeki hareketleri görmez ve bakiye yanlış görünür.</p>
  <ul>${dupeHtml}</ul>
</div>
<div class="box alert">
  <p><b>Maaş ödemesi kaydı olmayan ama avansı yüksek çalışanlar</b> — bu kişilere
  ödeme “Maaş Ver” akışıyla değil, avans kaydı olarak girilmiş görünüyor. Bu
  çalışanlarda net = brüt − avans olduğu için bakiye ALACAKLI/VERECEKLİ sınırında
  salınır ve işverenin beklediğiyle uyuşmayabilir.</p>
  <ul>${advOnlyHtml}</ul>
</div>

<div class="note">
  Rapor salt-okunurdur; hiçbir veri değiştirilmemiştir. Bakiye düzeltmesi
  yapılmadan önce rakamların işverenle mutabık kalınması gerekir.
</div>
`;
}

function printConsole(orgId, R) {
  const { rows, dupes, advanceOnly } = R;
  const changed = rows.filter((r) => r.wageChanged);
  const probed = rows.filter((r) => r.probed);
  const fully = rows.filter((r) => r.fullyCovered);
  console.log(`\n${'='.repeat(72)}\nORG: ${orgId}\n${'='.repeat(72)}`);
  console.log(`\n1) Yevmiye degisimi: ${changed.length} calisanda tespit edildi.`);
  console.log(`   Gecmis yevmiyesi kismen okunabilen : ${probed.length}/${rows.length}`);
  console.log(`   Hic okunamayan (bilinmiyor)        : ${rows.length - probed.length}`);
  console.log(`   Tum gunleri kapsanan (garanti)     : ${fully.length}`);
  console.log(`\n2) Bakiye: ${rows.filter((r) => r.netNow > 0.5).length} verecekli, ` +
    `${rows.filter((r) => r.netNow < -0.5).length} alacakli, ` +
    `${rows.filter((r) => Math.abs(r.netNow) <= 0.5).length} kapali.`);
  console.log(`\n3) Mukerrer isim grubu: ${dupes.length}`);
  for (const g of dupes) console.log(`   - ${g[0].ad}: ${g.length} kayit`);
  console.log(`\n   Odemesi 0 ama avansi olan: ${advanceOnly.length}`);
  for (const r of advanceOnly) console.log(`   - ${r.ad}: avans ${TL(r.advAll)}, net ${TL(r.netNow)}`);
}

async function run() {
  const orgs = await db.collection('organizations').listDocuments();
  if (!orgs.length) {
    console.log('Organizasyon bulunamadı.');
    return;
  }
  const desktop = path.join(os.homedir(), 'Desktop');

  for (const orgRef of orgs) {
    const R = await analyzeOrg(orgRef);
    printConsole(orgRef.id, R);

    const html = buildHtml(orgRef.id, R);
    const base = 'bakiye_durum_raporu';
    const htmlPath = path.join(os.tmpdir(), `${base}.html`);
    const pdfPath = path.join(desktop, `${base}.pdf`);
    fs.writeFileSync(htmlPath, html, 'utf8');
    try {
      execSync(
        `"${CHROME}" --headless --disable-gpu --no-pdf-header-footer ` +
          `--print-to-pdf="${pdfPath}" "file://${htmlPath}" 2>/dev/null`,
      );
      console.log(`\n→ PDF: ${pdfPath}`);
    } catch (e) {
      const fb = path.join(desktop, `${base}.html`);
      fs.copyFileSync(htmlPath, fb);
      console.error(`(PDF üretilemedi: ${e.message}) → HTML: ${fb}`);
    }
  }
  console.log('\nSalt-okunur; hiçbir veri değiştirilmedi.\n');
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
