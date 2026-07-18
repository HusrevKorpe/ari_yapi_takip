// Çalışan adli dökümü — tek bir çalışanın bakiyesinin NEDEN o rakam olduğunu
// kayıt kayıt, metadata'sıyla birlikte gösterir.
//
// calisan_dokumu.js "ne" olduğunu söyler; bu script "neden" olduğunu söyler:
//   · Donmuş maaş özetleri ile bugünkü hesabı aynı dönem için karşılaştırır
//     → geçmiş yeniden fiyatlanmış mı? (yevmiye/prim değişimi hatası)
//   · Her kaydın olay tarihi ile ne zaman girildiğini gösterir
//     → ödenmiş döneme sonradan giren kayıt (carryOver kaynağı)
//   · senkronSurumu ile kaç kez yazıldığını gösterir → düzenleme izi
//   · Silinmiş kayıtları ayrıca listeler → kaybolan avans/ödeme şüphesi
//
// Kullanım:
//   node calisan_adli_dokum.js "osman bilgiç"
//
// SALT-OKUNUR. Hiçbir veri değiştirmez.

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const NAME = process.argv[2];
if (!NAME) {
  console.error('Kullanım: node calisan_adli_dokum.js <isim>');
  process.exit(1);
}

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');
if (!fs.existsSync(serviceAccountPath)) {
  console.error(`Service account JSON bulunamadı: ${serviceAccountPath}`);
  process.exit(1);
}
admin.initializeApp({ credential: admin.credential.cert(require(serviceAccountPath)) });
const db = admin.firestore();

const eqOf = (s) => (s === 'worked' ? 1 : s === 'half_day' || s === 'halfDay' ? 0.5 : 0);
const TL = (n) =>
  (Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const d0 = (iso) => { const d = new Date(iso); return new Date(d.getFullYear(), d.getMonth(), d.getDate()); };
const dk = (iso) => {
  if (!iso) return '—';
  const d = d0(iso);
  if (isNaN(d)) return '—';
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
};
const tsMs = (v) => {
  if (!v) return null;
  const ms = typeof v === 'object' && v._seconds != null ? v._seconds * 1000
    : (typeof v === 'number' ? v : Date.parse(v));
  return !ms || isNaN(ms) ? null : ms;
};
const ts = (v) => {
  const ms = tsMs(v);
  return ms == null ? '—' : new Date(ms).toISOString().slice(0, 16).replace('T', ' ');
};
const lag = (eventIso, createdVal) => {
  const ev = Date.parse(eventIso);
  const cr = tsMs(createdVal);
  if (!ev || isNaN(ev) || cr == null) return null;
  return Math.round((cr - d0(eventIso).getTime()) / 86400000);
};

(async () => {
  const orgs = await db.collection('organizations').listDocuments();
  for (const orgRef of orgs) {
    const w = await orgRef.collection('calisanlar').get();
    const hits = [];
    w.forEach((d) => {
      const x = d.data();
      if (String(x.adSoyad || '').toLocaleLowerCase('tr').includes(NAME.toLocaleLowerCase('tr'))) {
        hits.push({ id: d.id, x });
      }
    });
    if (!hits.length) continue;

    if (hits.length > 1) {
      console.log(`\n!! "${NAME}" icin ${hits.length} kayit bulundu — MUKERRER:`);
      hits.forEach((h) => console.log(`   ${h.id}  "${h.x.adSoyad}"  yevmiye ${TL(h.x.gunlukUcret)}  ${h.x.silinmeTarihi ? '[SILINMIS]' : ''}`));
      console.log('');
    }

    for (const { id, x } of hits) {
      if (x.silinmeTarihi) { console.log(`(${x.adSoyad} silinmis — atlaniyor)\n`); continue; }
      const wageNow = Number(x.gunlukUcret) || 0;
      const rbNow = x.primAliyor !== false;

      const [yk, ad, pay, oz, st] = await Promise.all([
        orgRef.collection('yoklama').where('calisanId', '==', id).get(),
        orgRef.collection('avans_borclar').where('calisanId', '==', id).get(),
        orgRef.collection('maas_odemeleri').where('calisanId', '==', id).get(),
        orgRef.collection('maas_ozetleri').where('calisanId', '==', id).get(),
        orgRef.collection('santiyeler').get(),
      ]);
      const sites = {};
      st.forEach((d) => { sites[d.id] = { ad: d.data().ad, prim: Number(d.data().gunlukPrim) || 0 }; });

      const all = (snap) => { const r = []; snap.forEach((d) => r.push({ _id: d.id, ...d.data() })); return r; };
      const attAll = all(yk), adAll = all(ad), payAll = all(pay), ozAll = all(oz);
      const att = attAll.filter((a) => !a.silinmeTarihi);
      const ads = adAll.filter((a) => !a.silinmeTarihi);
      const pys = payAll.filter((a) => !a.silinmeTarihi);

      const primNow = (a) => {
        if (!rbNow) return 0;
        const eq = eqOf(a.durum);
        if (eq === 0 || !a.santiyeId) return 0;
        const s = sites[a.santiyeId];
        return s && s.prim > 0 ? s.prim * eq : 0;
      };

      const eqDays = att.reduce((s, a) => s + eqOf(a.durum), 0);
      const gross = att.reduce((s, a) => s + eqOf(a.durum) * wageNow + primNow(a), 0);
      const av = ads.filter((a) => a.tur === 'advance').reduce((s, a) => s + (Number(a.tutar) || 0), 0);
      const bo = ads.filter((a) => a.tur === 'debt').reduce((s, a) => s + (Number(a.tutar) || 0), 0);
      const pd = pys.reduce((s, a) => s + (Number(a.tutar) || 0), 0);
      const net = gross + bo - av - pd;

      console.log('='.repeat(98));
      console.log(`${x.adSoyad}   (${id})`);
      console.log('='.repeat(98));
      console.log(`  bugunku yevmiye : ${TL(wageNow)}      prim aliyor: ${rbNow}`);
      console.log(`  olusturulma     : ${ts(x.olusturulmaTarihi)}`);
      console.log(`  guncellenme     : ${ts(x.guncellenmeTarihi)}`);
      console.log(`  senkronSurumu   : ${x.senkronSurumu}  <- 1 ise kayit hic duzenlenmemis (yevmiye hic degismemis)`);
      console.log('');
      console.log(`  UYGULAMANIN HESABI:`);
      console.log(`    ${eqDays} gun karsiligi x ${TL(wageNow)}  + prim  = brut ${TL(gross)}`);
      console.log(`    + borc ${TL(bo)}  - avans ${TL(av)}  - odenen ${TL(pd)}`);
      console.log(`    = NET ${TL(net)}   ${net > 0.5 ? '(ISVEREN VERECEKLI)' : net < -0.5 ? '(ISVEREN ALACAKLI)' : '(kapali)'}`);

      // ---- kesin test: donem yeniden fiyatlanmis mi? ---------------------
      console.log('\n' + '-'.repeat(98));
      console.log('1) GECMIS YENIDEN FIYATLANMIS MI?  (ayni donem: odeme aninda dondurulmus vs bugun)');
      console.log('-'.repeat(98));
      if (!ozAll.length) {
        console.log('  Maas ozeti yok — bu kontrol yapilamiyor.');
      } else {
        console.log('  DONEM'.padEnd(28), 'DONMUS BRUT'.padStart(13), 'BUGUN'.padStart(13), 'FARK'.padStart(12));
        ozAll.sort((a, b) => String(a.ay).localeCompare(String(b.ay)));
        for (const o of ozAll) {
          const [s, e] = String(o.ay).split('_');
          if (!s || !e) continue;
          const sMs = Date.parse(s), eMs = Date.parse(e) + 86399999;
          const inR = att.filter((a) => { const t = Date.parse(a.tarih); return t >= sMs && t <= eMs; });
          const today = inR.reduce((acc, a) => acc + eqOf(a.durum) * wageNow + primNow(a), 0);
          const frozen = Number(o.brut) || 0;
          const diff = today - frozen;
          const fg = Number(o.calisilanGunEsdegeri) || 0;
          console.log(
            `  ${s} → ${e}`.padEnd(28),
            TL(frozen).padStart(13),
            TL(today).padStart(13),
            ((diff > 0 ? '+' : '') + TL(diff)).padStart(12),
            Math.abs(diff) > 0.5 ? ' <<< YENIDEN FIYATLANMIS' : '',
            o.silinmeTarihi ? ' [SILINMIS OZET]' : '',
          );
          console.log(
            ' '.repeat(28),
            `odeme aninda: ${fg} gun, gun basi ${fg > 0 ? TL(frozen / fg) : '—'}`.padStart(13),
          );
        }
      }

      // ---- odemeler -------------------------------------------------------
      console.log('\n' + '-'.repeat(98));
      console.log('2) MAAS ODEMELERI');
      console.log('-'.repeat(98));
      console.log('  DONEM'.padEnd(28), 'TUTAR'.padStart(12), 'ODEME T.'.padEnd(12), 'GIRILDI'.padEnd(18), 'VER');
      payAll.sort((a, b) => Date.parse(a.donemBitisi) - Date.parse(b.donemBitisi));
      for (const p of payAll) {
        console.log(
          `  ${dk(p.donemBaslangici)} → ${dk(p.donemBitisi)}`.padEnd(28),
          TL(p.tutar).padStart(12),
          dk(p.odemeTarihi).padEnd(12),
          ts(p.olusturulmaTarihi).padEnd(18),
          String(p.senkronSurumu || '').padStart(3),
          p.silinmeTarihi ? ' [SILINMIS]' : '',
        );
      }
      console.log(`  ${'TOPLAM (silinmemis)'.padEnd(26)} ${TL(pd).padStart(12)}`);

      // ---- avans / borc ---------------------------------------------------
      console.log('\n' + '-'.repeat(98));
      console.log('3) AVANS / BORC   (GECIKME: olay gununden kac gun sonra girilmis)');
      console.log('-'.repeat(98));
      if (!adAll.length) {
        console.log('  HIC AVANS/BORC KAYDI YOK.');
      } else {
        console.log('  ISLEM T.'.padEnd(14), 'TUR'.padEnd(9), 'TUTAR'.padStart(12), 'GIRILDI'.padEnd(18), 'GECIKME'.padStart(8), 'VER', 'MAHSUP', 'NOT');
        adAll.sort((a, b) => Date.parse(a.islemTarihi) - Date.parse(b.islemTarihi));
        for (const a of adAll) {
          const L = lag(a.islemTarihi, a.olusturulmaTarihi);
          console.log(
            `  ${dk(a.islemTarihi)}`.padEnd(14),
            String(a.tur).padEnd(9),
            TL(a.tutar).padStart(12),
            ts(a.olusturulmaTarihi).padEnd(18),
            (L != null ? L + 'g' : '—').padStart(8),
            String(a.senkronSurumu || '').padStart(3),
            String(a.mahsupAy || '—').padEnd(8),
            (a.not || '').slice(0, 28),
            a.silinmeTarihi ? ' [SILINMIS]' : '',
          );
        }
        console.log(`  avans toplami (silinmemis): ${TL(av)}   borc toplami: ${TL(bo)}`);
      }

      // ---- yoklama --------------------------------------------------------
      console.log('\n' + '-'.repeat(98));
      console.log('4) YOKLAMA   (GECIKME > 1g = calisma gununden sonra girilmis)');
      console.log('-'.repeat(98));
      console.log('  TARIH'.padEnd(14), 'DURUM'.padEnd(10), 'SANTIYE'.padEnd(20), 'GIRILDI'.padEnd(18), 'GECIKME'.padStart(8), 'VER');
      attAll.sort((a, b) => Date.parse(a.tarih) - Date.parse(b.tarih));
      let retro = 0;
      for (const a of attAll) {
        const L = lag(a.tarih, a.olusturulmaTarihi);
        if (L != null && L > 1 && !a.silinmeTarihi) retro++;
        console.log(
          `  ${dk(a.tarih)}`.padEnd(14),
          String(a.durum).padEnd(10),
          String(a.santiyeId ? (sites[a.santiyeId] ? sites[a.santiyeId].ad : '?') : '—').slice(0, 19).padEnd(20),
          ts(a.olusturulmaTarihi).padEnd(18),
          (L != null ? L + 'g' : '—').padStart(8),
          String(a.senkronSurumu || '').padStart(3),
          a.silinmeTarihi ? ' [SILINMIS]' : (L != null && L > 1 ? ' <- gec girilmis' : ''),
        );
      }
      console.log(`\n  Toplam ${attAll.length} kayit, ${attAll.length - att.length} silinmis, ${retro} tanesi calisma gununden >1 gun sonra girilmis.`);

      // ---- silinmis kayit ozeti -------------------------------------------
      const delAd = adAll.filter((a) => a.silinmeTarihi);
      const delPay = payAll.filter((a) => a.silinmeTarihi);
      const delAtt = attAll.filter((a) => a.silinmeTarihi);
      console.log('\n' + '-'.repeat(98));
      console.log('5) SILINMIS KAYITLAR  (hesaba girmiyor — kasitli mi, kayip mi?)');
      console.log('-'.repeat(98));
      console.log(`  avans/borc: ${delAd.length}  (toplam ${TL(delAd.reduce((s, a) => s + (Number(a.tutar) || 0), 0))})`);
      console.log(`  odeme     : ${delPay.length}  (toplam ${TL(delPay.reduce((s, a) => s + (Number(a.tutar) || 0), 0))})`);
      console.log(`  yoklama   : ${delAtt.length}`);
      console.log('');
    }
    process.exit(0);
  }
  console.log(`"${NAME}" bulunamadi.`);
  process.exit(1);
})().catch((e) => { console.error('HATA:', e); process.exit(99); });
