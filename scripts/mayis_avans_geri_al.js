// 4 Mayıs "borç → avans" çevirmesini GÜVENLE geri alır: bugün (2026-07-17)
// yanlışlıkla eklenen 5 avansı SOFT-DELETE eder. Hard delete YOK.
//
// GÜVENLİK MODELİ (kopya_calisan_temizle.js ile aynı kural):
//   • Sadece silinmeTarihi + guncellenmeTarihi + senkronSurumu+1 yazılır (soft delete).
//   • cihazId script'e özeldir → telefon "echo" sanmaz, "uzak sürüm >= yerel" görüp uygular.
//   • Hedef yalnızca: tur=advance, islemTarihi=2026-05-04, createTime günü=2026-07-17,
//     ve silinmemiş olanlar. Gerçek Temmuz avansları (islemTarihi farklı) DIŞARIDA kalır.
//   • Bulunanlar TAM {5875,10000,9500,10800,2700}=38875 TL / 5 adet değilse DURUR.
//
// KULLANIM:
//   node scripts/mayis_avans_geri_al.js            # KURU ÇALIŞMA (yazma yok)
//   node scripts/mayis_avans_geri_al.js --apply    # Gerçekten uygular
//
// GERİ ALMA (bunu da geri almak istersen): aynı dokümanlarda silinmeTarihi=null yapıp
//   senkronSurumu+1 bump edilir. Soft delete olduğu için veri kaybı yok.

const admin = require('firebase-admin');
const fs = require('fs');
const path = require('path');

const ORG = 'St4QMcJf9ccsRbac4CM6S01gjvn1';
const ACTOR = 'admin-avans-geri-al';
const APPLY = process.argv.includes('--apply');

// Beklenen hedef (çift emniyet)
const ISLEM_GUN = '2026-05-04';       // avansların işlem tarihi
const CREATE_GUN = '2026-07-17';      // bugün oluşturulmuş olmalı (TR günü)
const BEKLENEN_TUTARLAR = [5875, 10000, 9500, 10800, 2700].sort((a, b) => a - b);
const BEKLENEN_TOPLAM = 38875;
const BEKLENEN_ADET = 5;

const TR = 3 * 3600 * 1000;
const saPath = process.env.SERVICE_ACCOUNT_PATH || path.resolve(__dirname, '..', 'serviceAccount.json');
if (!fs.existsSync(saPath)) { console.error(`Service account bulunamadı: ${saPath}`); process.exit(1); }
admin.initializeApp({ credential: admin.credential.cert(require(saPath)) });
const db = admin.firestore();

const TL = (n) => `${(Number(n) || 0).toLocaleString('tr-TR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })} TL`;
const d10 = (v) => String(v || '').slice(0, 10);
const trDay = (ms) => (ms == null ? null : new Date(ms + TR).toISOString().slice(0, 10));
const trStamp = (ms) => (ms == null ? '—' : new Date(ms + TR).toISOString().slice(0, 16).replace('T', ' '));
const nowIso = () => new Date().toISOString();
const bump = (v) => (Number(v) || 0) + 1;
const die = (code, msg) => { console.error(`\n⛔ DURDU: ${msg}\n(Hiçbir şey yazılmadı.)`); process.exit(code); };

async function main() {
  console.log(`Mod: ${APPLY ? '*** UYGULA (--apply) ***' : 'KURU ÇALIŞMA (yazma yok)'}`);
  console.log(`Org: ${ORG}\n`);

  const orgRef = db.collection('organizations').doc(ORG);
  const [wS, aS] = await Promise.all([
    orgRef.collection('calisanlar').get(),
    orgRef.collection('avans_borclar').get(),
  ]);
  const names = {};
  wS.forEach((d) => (names[d.id] = d.data().adSoyad || '(isimsiz)'));

  // Hedefleri topla
  const hedefler = [];
  aS.forEach((doc) => {
    const x = doc.data();
    const createMs = doc.createTime ? doc.createTime.toMillis() : null;
    if (x.tur !== 'advance') return;
    if (x.silinmeTarihi) return;                 // zaten silinmişse atla
    if (d10(x.islemTarihi) !== ISLEM_GUN) return; // sadece 4 Mayıs
    if (trDay(createMs) !== CREATE_GUN) return;   // sadece bugün oluşturulan
    hedefler.push({
      id: doc.id,
      ad: names[x.calisanId] || `(bilinmeyen:${x.calisanId})`,
      tutar: Number(x.tutar) || 0,
      surum: Number(x.senkronSurumu) || 0,
      createMs,
    });
  });

  hedefler.sort((a, b) => a.ad.localeCompare(b.ad, 'tr'));

  console.log('Bulunan hedef avanslar (islemTarihi=2026-05-04, bugün oluşturulan):');
  if (!hedefler.length) die(2, 'Hiç hedef bulunamadı. Zaten silinmiş olabilir.');
  let toplam = 0;
  hedefler.forEach((h, i) => {
    toplam += h.tutar;
    console.log(`  ${String(i + 1).padStart(2)}. ${h.ad.padEnd(22)} ${TL(h.tutar).padStart(14)}   sürüm ${h.surum}→${bump(h.surum)}   oluş: ${trStamp(h.createMs)}   id:${h.id}`);
  });
  console.log(`  ─────────────────────────────────────────`);
  console.log(`  TOPLAM: ${TL(toplam)}   (${hedefler.length} avans)\n`);

  // ---- ÇİFT EMNİYET ----
  if (hedefler.length !== BEKLENEN_ADET)
    die(3, `Beklenen ${BEKLENEN_ADET} avans, bulunan ${hedefler.length}. Elle incele.`);
  const bulunanTutarlar = hedefler.map((h) => h.tutar).sort((a, b) => a - b);
  const tutarUyum = bulunanTutarlar.every((t, i) => Math.abs(t - BEKLENEN_TUTARLAR[i]) < 0.005);
  if (!tutarUyum)
    die(4, `Tutar kümesi beklenenle uyuşmuyor.\n  beklenen: ${BEKLENEN_TUTARLAR.map(TL).join(', ')}\n  bulunan : ${bulunanTutarlar.map(TL).join(', ')}`);
  if (Math.abs(toplam - BEKLENEN_TOPLAM) > 0.005)
    die(5, `Toplam ${TL(toplam)} beklenen ${TL(BEKLENEN_TOPLAM)} değil.`);
  console.log('✅ Çift emniyet geçti: 5 avans, tutarlar ve toplam beklenenle birebir aynı.');

  if (!APPLY) {
    console.log('\n[KURU ÇALIŞMA] Hiçbir şey yazılmadı.');
    console.log('Uygulamak için: node scripts/mayis_avans_geri_al.js --apply');
    return;
  }

  console.log('\n--apply verildi, soft-delete yazılıyor...');
  for (const h of hedefler) {
    await orgRef.collection('avans_borclar').doc(h.id).update({
      silinmeTarihi: nowIso(),
      guncellenmeTarihi: nowIso(),
      sonDegistiren: ACTOR,
      cihazId: ACTOR,
      senkronSurumu: bump(h.surum),
    });
    console.log(`  ✓ ${h.ad.padEnd(22)} ${TL(h.tutar).padStart(14)} silindi (sürüm ${h.surum}→${bump(h.surum)})`);
  }
  console.log(`\nBitti. ${TL(toplam)} tutarındaki 5 avans soft-delete edildi.`);
  console.log('Telefonlar senkron olunca (senkronSurumu+1 sayesinde) bu avanslar kaybolacak,');
  console.log('işçilerin bakiyesi ve işverenin alacağı çevirme öncesine dönecek.');
}

main().then(() => process.exit(0)).catch((e) => { console.error('HATA:', e); process.exit(99); });
