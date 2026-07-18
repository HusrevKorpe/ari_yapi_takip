// SALT-OKUNUR.  node scripts/zam_tarama.js
// TÜM kadroda "zam almış" (dolayısıyla canlı Maaş Ver'i ŞİŞKİN) çalışanları bulur.
//
// Tarihsel yevmiye kaynakları (güvenilirlik sırasıyla):
//   1) snapshot gunlukDetay[].dailyAmount / dayEquivalent  → prim'DEN BAĞIMSIZ, KESİN
//   2) döküm YOK snapshot'ta, prim ALMAYAN işçide  brüt / calisilanGunEsdegeri → çıkarım
//   3) döküm YOK snapshot'ta, prim ALAN işçide      → belirsiz (brüt prim içeriyor), atlanır
// Herhangi bir tarihsel yevmiye < güncel gunlukUcret ise → ZAM. App o günleri
// güncel yevmiyeye çekiyor; şişkinlik ≈ Σ(güncel − eski) × o yevmiyedeki gün.

const admin = require('firebase-admin');
const path = require('path');
admin.initializeApp({ credential: admin.credential.cert(require(path.resolve(__dirname, '..', 'serviceAccount.json'))) });
const db = admin.firestore();

const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 0, maximumFractionDigits: 0 })}₺`;
const r10 = (n) => Math.round(n / 10) * 10; // yevmiye yuvarlama gürültüsünü at
const near = (a, b) => Math.abs(a - b) < 50;

(async () => {
  const org = (await db.collection('organizations').listDocuments())[0];
  const [wSnap, ozSnap] = await Promise.all([
    org.collection('calisanlar').get(),
    org.collection('maas_ozetleri').get(),
  ]);
  const workers = new Map();
  wSnap.forEach((doc) => { const r = doc.data(); if (r.silinmeTarihi) return; workers.set(doc.id, { _id: doc.id, ...r }); });
  const ozByW = new Map();
  ozSnap.forEach((doc) => { const r = doc.data(); if (r.silinmeTarihi) return; if (!ozByW.has(r.calisanId)) ozByW.set(r.calisanId, []); ozByW.get(r.calisanId).push(r); });

  const flagged = [];
  for (const [wid, w] of workers) {
    const W = r10(Number(w.gunlukUcret) || 0);
    const primAliyor = w.primAliyor === true;
    const rateDays = new Map(); // yevmiye -> gün-eşdeğeri toplamı
    let belirsizSnap = 0; // prim alan + döküm yok (ölçülemez)
    let dokumVar = false, cikarimVar = false;

    for (const o of (ozByW.get(wid) || [])) {
      const worked = Number(o.calisilanGunEsdegeri) || 0;
      const brut = Number(o.brut) || 0;
      if (o.gunlukDetay) {
        try {
          const arr = JSON.parse(o.gunlukDetay);
          for (const x of arr) {
            const eq = Number(x.dayEquivalent) || 0;
            if (eq <= 0) continue;
            const rate = r10((Number(x.dailyAmount) || 0) / eq);
            if (rate <= 0) continue;
            rateDays.set(rate, (rateDays.get(rate) || 0) + eq);
            dokumVar = true;
          }
        } catch (_) {}
      } else if (worked > 0) {
        if (!primAliyor) {
          const rate = r10(brut / worked);
          if (rate > 0) { rateDays.set(rate, (rateDays.get(rate) || 0) + worked); cikarimVar = true; }
        } else {
          belirsizSnap += worked;
        }
      }
    }

    const rates = [...rateDays.keys()].sort((a, b) => a - b);
    const dusukRates = rates.filter((rt) => rt < W - 40); // güncelden düşük = zam kanıtı
    if (dusukRates.length === 0) {
      // yine de belirsiz snapshot'ı olan prim alanları ayrı not düşeceğiz
      if (belirsizSnap > 0 && rates.length === 0) flagged.push({ w, W, primAliyor, belirsiz: true, belirsizSnap, rateDays, sisme: 0, dokumVar, cikarimVar });
      continue;
    }
    let sisme = 0;
    for (const rt of dusukRates) sisme += (W - rt) * rateDays.get(rt);
    flagged.push({ w, W, primAliyor, belirsiz: false, belirsizSnap, rateDays, dusukRates, sisme, dokumVar, cikarimVar });
  }

  // ZAM alanlar (şişme > 0) önce, büyükten küçüğe
  const zamlilar = flagged.filter((f) => !f.belirsiz && f.sisme > 0).sort((a, b) => b.sisme - a.sisme);
  const belirsizler = flagged.filter((f) => f.belirsiz);

  console.log('\n══════════ ZAM ALMIŞ ÇALIŞANLAR (canlı Maaş Ver ŞİŞKİN) ══════════\n');
  console.log('AD'.padEnd(24) + 'güncel'.padStart(8) + 'eski→yeni'.padStart(16) + 'şişme≈'.padStart(11) + '  güven');
  console.log('─'.repeat(78));
  let toplamSisme = 0;
  for (const f of zamlilar) {
    const gecis = f.dusukRates.map((rt) => `${TL(rt)}(${f.rateDays.get(rt)}g)`).join('+') + `→${TL(f.W)}`;
    const guven = f.dokumVar ? (f.cikarimVar ? 'döküm+çıkarım' : 'DÖKÜM (kesin)') : 'çıkarım (dökümsüz)';
    const pasif = f.w.aktifMi === false ? ' [PASİF]' : '';
    console.log((f.w.adSoyad || '?').slice(0, 23).padEnd(24) + TL(f.W).padStart(8) + gecis.padStart(16) + TL(f.sisme).padStart(11) + '  ' + guven + pasif);
    toplamSisme += f.sisme;
  }
  if (!zamlilar.length) console.log('(yok)');
  console.log('─'.repeat(78));
  console.log(`Kesin/çıkarım zam alan: ${zamlilar.length} kişi.  Toplam tahmini şişme ≈ ${TL(toplamSisme)}`);
  console.log('(şişme = app\'in fazla gösterdiği; gerçek borç = app − şişme)');

  if (belirsizler.length) {
    console.log('\n─── BELİRSİZ (prim alan + dökümsüz snapshot → yevmiye ölçülemedi, zam olabilir) ───');
    for (const f of belirsizler) console.log(`  ${(f.w.adSoyad || '?').slice(0, 30).padEnd(31)} güncel ${TL(f.W)}  dökümsüz ${f.belirsizSnap}g`);
  }

  console.log('\nNOT: "DÖKÜM (kesin)" = tarihsel yevmiye snapshot gün-detayından okundu, kesin.');
  console.log('     "çıkarım" = döküm yok, prim almayan işçide brüt/gün\'den çıkarıldı (güvenilir ama tek kaynak).');
  console.log('     Şişme yalnızca ÖDENMİŞ/snapshot günleri kapsar; açık dönemdeki eski-yevmiye günleri ayrıca olabilir.');
  process.exit(0);
})().catch((e) => { console.log('HATA', e.message, e.stack); process.exit(1); });
