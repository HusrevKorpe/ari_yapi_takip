// SALT-OKUNUR: nejıbullah moradi için uygulamanın _lifetimeNet formülünü canlı
// veriyle BİREBİR yeniden üretir:
//   net = çalışılan gün × yevmiye + PRİM(canlı) − avans − ödenen
// PRİM(canlı) = her yoklamada santiyeId dolu + durum saha gerektiriyorsa
//               site.gunlukPrim × günKarşılığı  (birincil santiye; app da böyle)
// Ayrıca: santiyeId vs siteId alan doluluğunu ve donmuş snapshot primini kıyaslar.
// HİÇBİR ŞEY YAZMAZ.  node scripts/nejibullah_prim_teshis.js

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const d = (x) => String(x || '').slice(0, 10);
const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 0, maximumFractionDigits: 2 })}₺`;
const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);
const requiresSite = (s) => s === 'worked' || s === 'half_day' || s === 'halfDay';
const near = (a, b) => Math.abs(a - b) < 0.5;

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  const [wSnap, ySnap, ozSnap, avSnap, paySnap, stSnap] = await Promise.all([
    org.collection('calisanlar').get(),
    org.collection('yoklama').get(),
    org.collection('maas_ozetleri').get(),
    org.collection('avans_borclar').get(),
    org.collection('maas_odemeleri').get(),
    org.collection('santiyeler').get(),
  ]);

  // Şantiye primleri
  const sitePrim = {}, siteAd = {};
  stSnap.forEach((doc) => { const s = doc.data(); sitePrim[doc.id] = Number(s.gunlukPrim) || 0; siteAd[doc.id] = s.ad || s.isim || doc.id; });

  // nejıbullah'ı bul
  let worker = null;
  wSnap.forEach((doc) => {
    const r = doc.data();
    if (/nej[ıi]bullah|moradi/i.test(String(r.adSoyad || ''))) worker = { _id: doc.id, ...r };
  });
  if (!worker) { console.log('nejıbullah bulunamadı'); process.exit(1); }

  const wage = Number(worker.gunlukUcret) || 0;
  const primAliyor = worker.primAliyor === true;
  console.log(`ÇALIŞAN: ${worker.adSoyad}  (id ${worker._id})`);
  console.log(`  yevmiye: ${TL(wage)}   primAliyor: ${primAliyor}   aktifMi: ${worker.aktifMi}   silinmiş: ${!!worker.silinmeTarihi}\n`);

  // Yoklamalar
  const days = [];
  ySnap.forEach((doc) => {
    const r = doc.data();
    if (r.calisanId !== worker._id) return;
    if (r.silinmeTarihi) return;
    days.push({ _id: doc.id, ...r });
  });
  days.sort((a, b) => d(a.tarih).localeCompare(d(b.tarih)));

  // Alan doluluk teşhisi (hafızadaki "siteId boş" iddiasını test et)
  let santiyeliCnt = 0, siteIdliCnt = 0, ikinciCnt = 0;
  days.forEach((a) => {
    if (a.santiyeId) santiyeliCnt++;
    if (a.siteId) siteIdliCnt++;
    if (a.ikinciSantiyeId) ikinciCnt++;
  });
  console.log(`ALAN DOLULUK (${days.length} yoklama):`);
  console.log(`  santiyeId dolu: ${santiyeliCnt}   (app bunu okur → prim buradan gelir)`);
  console.log(`  siteId dolu:    ${siteIdliCnt}   (yoklama_site_dagilim.js buna baktı → 0 görüp 'boş' dedi)`);
  console.log(`  ikinciSantiyeId dolu: ${ikinciCnt}\n`);

  // Uygulamanın _lifetimeNet'i BİREBİR
  let worked = 0, liveBonus = 0;
  const primBySite = {};
  for (const a of days) {
    const eq = eqOf(a.durum);
    worked += eq;
    if (primAliyor && requiresSite(a.durum) && a.santiyeId) {
      const b = sitePrim[a.santiyeId] || 0;
      if (b > 0) {
        const add = b * (a.durum === 'half_day' || a.durum === 'halfDay' ? 0.5 : 1.0);
        liveBonus += add;
        if (!primBySite[a.santiyeId]) primBySite[a.santiyeId] = { eq: 0, tutar: 0, prim: b };
        primBySite[a.santiyeId].eq += eq;
        primBySite[a.santiyeId].tutar += add;
      }
    }
  }

  const advances = avSnap.docs
    .map((x) => x.data())
    .filter((a) => a.calisanId === worker._id && !a.silinmeTarihi && a.tur === 'advance')
    .reduce((s, a) => s + (Number(a.tutar) || 0), 0);
  const paid = paySnap.docs
    .map((x) => x.data())
    .filter((p) => p.calisanId === worker._id && !p.silinmeTarihi)
    .reduce((s, p) => s + (Number(p.tutar) || 0), 0);

  const gross = worked * wage;
  const lifetimeNet = gross + (primAliyor ? liveBonus : 0) - advances - paid;

  console.log('UYGULAMANIN GÖSTERDİĞİ (canlı _lifetimeNet):');
  console.log(`  çalışılan gün eşdeğeri : ${worked}`);
  console.log(`  kazanç (gün×yevmiye)   : ${TL(gross)}`);
  console.log(`  + PRİM (canlı)         : ${TL(liveBonus)}`);
  console.log(`  − avans                : ${TL(advances)}`);
  console.log(`  − ödenen               : ${TL(paid)}`);
  console.log(`  ───────────────────────`);
  console.log(`  = NET (app ekranı)     : ${TL(lifetimeNet)}\n`);

  console.log('CANLI PRİM DAĞILIMI (şantiye bazında):');
  Object.entries(primBySite).forEach(([sid, v]) => {
    console.log(`  ${String(siteAd[sid]).slice(0, 24).padEnd(26)} ${v.eq} gün × ${TL(v.prim)} = ${TL(v.tutar)}`);
  });
  console.log('');

  // Donmuş snapshot primi (maas_ozetleri.gunlukDetay.siteBonus) — tarih bazlı dedupe
  const primByDate = new Map();
  let snapCount = 0, dokumsuzFazla = 0;
  ozSnap.forEach((doc) => {
    const o = doc.data();
    if (o.calisanId !== worker._id) return;
    if (o.silinmeTarihi) return;
    snapCount++;
    if (o.gunlukDetay) {
      try {
        const arr = JSON.parse(o.gunlukDetay);
        for (const x of arr) {
          const sb = Number(x.siteBonus) || 0;
          if (sb > 0) primByDate.set(d(x.date), Math.max(primByDate.get(d(x.date)) || 0, sb));
        }
      } catch (_) {}
    } else {
      const b = Number(o.brut) || 0, g = Number(o.calisilanGunEsdegeri) || 0;
      if (b - g * wage > 0.5) dokumsuzFazla += b - g * wage;
    }
  });
  let frozenPrim = 0;
  primByDate.forEach((v) => (frozenPrim += v));

  console.log('KIYAS — CANLI PRİM vs DONMUŞ SNAPSHOT PRİMİ:');
  console.log(`  canlı prim (app'in kullandığı)      : ${TL(liveBonus)}`);
  console.log(`  donmuş snapshot primi (${snapCount} snap)     : ${TL(frozenPrim)}`);
  console.log(`  fark                                : ${TL(liveBonus - frozenPrim)}`);
  if (dokumsuzFazla > 0.5) console.log(`  (dökümsüz snapshot'larda brüt fazlası: ${TL(dokumsuzFazla)})`);
  console.log('');
  console.log('YORUM:');
  if (near(liveBonus, frozenPrim)) {
    console.log('  Canlı prim ile donmuş prim TUTUYOR → app doğru, düzeltme gerekmez.');
  } else if (liveBonus > frozenPrim) {
    console.log(`  Canlı prim donmuştan ${TL(liveBonus - frozenPrim)} FAZLA. Bu, ödeme anından SONRA`);
    console.log('  santiyeId girilmiş/değişmiş günler olabilir (ödenmiş döneme retro prim).');
  } else {
    console.log(`  Canlı prim donmuştan ${TL(frozenPrim - liveBonus)} EKSİK. Ödeme anında olan prim,`);
    console.log('  sonradan santiyeId silinmiş/boşalmış günlerden kaybolmuş olabilir.');
  }
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message); process.exit(1); });
