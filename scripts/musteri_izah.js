// SALT OKUNUR — Müşteriye gösterilecek bakiye izah raporu.
//
// Her çalışan için "bu rakam neden bu?" sorusunu kalem kalem cevaplar:
//   hakediş (çalışılan gün × yevmiye + prim) − eline geçen (avans + maaş ödemesi)
// ve 04.05.2026'daki borç→avans düzeltmesinin etkisini ayrıca gösterir.
//
// Arka plan: uygulamanın eski "Borç Ekle" butonu, kaydı "işverenin çalışana
// borcu" sayıp maaşa EKLİYORDU. Müşteri ise o butonu "işçiye borç verdim"
// (yani avans) anlamında kullanmış. Bu yüzden her borç kaydı bakiyeyi
// tutarın İKİ KATI kadar yanlış yönde göstermiş.
//
// Kullanım:
//   node musteri_izah.js           → terminale yazar
//   node musteri_izah.js --save    → Masaüstüne txt kaydeder
//
// Hiçbir yazma yapmaz.

const admin = require('firebase-admin');
const fs = require('fs');
const os = require('os');
const path = require('path');

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

const SAVE = process.argv.includes('--save');
const DUZELTME_GUNU = '2026-05-04';

const out = [];
const say = (s = '') => {
  out.push(s);
  console.log(s);
};

const TL = (n) =>
  `${(Number(n) || 0).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  })} TL`;

const toDate = (v) => {
  if (!v) return null;
  const d = v.toDate ? v.toDate() : new Date(v);
  return isNaN(d) ? null : d;
};
const dkey = (v) => {
  const d = toDate(v);
  if (!d) return null;
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(
    d.getDate()
  ).padStart(2, '0')}`;
};
const fmt = (v) => {
  const k = dkey(v);
  if (!k) return '-';
  const [y, m, d] = k.split('-');
  return `${d}.${m}.${y}`;
};

// Canlı veride görülen durum değerleri: worked / absent / half_day
const eqOf = (durum) => (durum === 'worked' ? 1.0 : durum === 'half_day' ? 0.5 : 0.0);

async function run() {
  for (const orgRef of await db.collection('organizations').listDocuments()) {
    const [workerSnap, siteSnap, ykSnap, adSnap, paySnap] = await Promise.all([
      orgRef.collection('calisanlar').get(),
      orgRef.collection('santiyeler').get(),
      orgRef.collection('yoklama').get(),
      orgRef.collection('avans_borclar').get(),
      orgRef.collection('maas_odemeleri').get(),
    ]);

    const sites = {};
    siteSnap.forEach((d) => (sites[d.id] = Number(d.data().gunlukPrim) || 0));

    const group = (snap, field) => {
      const m = {};
      snap.forEach((d) => {
        const x = d.data();
        if (x.silinmeTarihi) return;
        (m[x[field]] = m[x[field]] || []).push(x);
      });
      return m;
    };
    // Silinmişler dahil — düzeltme izini gösterebilmek için
    const groupAll = (snap, field) => {
      const m = {};
      snap.forEach((d) => {
        const x = d.data();
        (m[x[field]] = m[x[field]] || []).push(x);
      });
      return m;
    };

    const yk = group(ykSnap, 'calisanId');
    const ad = group(adSnap, 'calisanId');
    const adHepsi = groupAll(adSnap, 'calisanId');
    const pay = group(paySnap, 'calisanId');

    say('='.repeat(74));
    say('              ÇALIŞAN BAKİYE İZAH RAPORU');
    say(`              Rapor tarihi: ${new Date().toLocaleDateString('tr-TR')}`);
    say('='.repeat(74));
    say('');
    say('  Bakiye = Hakediş − Eline geçen');
    say('    Hakediş     : çalışılan gün karşılığı × yevmiye (+ şantiye primi)');
    say('    Eline geçen : verilen avanslar + yapılan maaş ödemeleri');
    say('');
    say('  EKSİ bakiye = çalışan hakedişinden FAZLA para almış.');
    say('  ARTI bakiye = çalışanın alacağı var.');
    say('');

    const rows = [];

    workerSnap.forEach((d) => {
      const w = d.data();
      if (w.silinmeTarihi) return;
      const id = d.id;
      const wage = Number(w.gunlukUcret) || 0;
      const primAlir = w.primAliyor !== false;

      const att = yk[id] || [];
      let gunSayisi = 0;
      let prim = 0;
      const gross = att.reduce((s, a) => {
        const eq = eqOf(a.durum);
        gunSayisi += eq;
        const p = primAlir && a.santiyeId && sites[a.santiyeId] > 0 ? sites[a.santiyeId] * eq : 0;
        prim += p;
        return s + eq * wage + p;
      }, 0);

      const ads = ad[id] || [];
      const avans = ads
        .filter((x) => x.tur === 'advance')
        .reduce((s, x) => s + (Number(x.tutar) || 0), 0);
      const borc = ads
        .filter((x) => x.tur === 'debt')
        .reduce((s, x) => s + (Number(x.tutar) || 0), 0);
      const odenen = (pay[id] || []).reduce((s, x) => s + (Number(x.tutar) || 0), 0);

      const net = gross + borc - avans - odenen;

      // 04.05 düzeltmesi: o gün silinmiş borç + bugün eklenen avans
      const hepsi = adHepsi[id] || [];
      const silinenBorc = hepsi
        .filter((x) => x.tur === 'debt' && x.silinmeTarihi && dkey(x.islemTarihi) === DUZELTME_GUNU)
        .reduce((s, x) => s + (Number(x.tutar) || 0), 0);

      rows.push({
        ad: w.adSoyad || '(isimsiz)',
        wage,
        gunSayisi,
        prim,
        gross,
        avans,
        borc,
        odenen,
        net,
        silinenBorc,
        avansKalem: ads.filter((x) => x.tur === 'advance').length,
        aktifBorclar: ads.filter((x) => x.tur === 'debt'),
      });
    });

    rows.sort((a, b) => a.net - b.net);

    for (const r of rows) {
      say('-'.repeat(74));
      say(`  ${r.ad.toUpperCase()}`);
      say('-'.repeat(74));
      say(
        `    Çalıştığı gün karşılığı : ${String(r.gunSayisi).padStart(6)} gün × ${TL(
          r.wage
        )}  =  ${TL(r.gunSayisi * r.wage)}`
      );
      if (r.prim > 0) say(`    Şantiye primi           : ${TL(r.prim).padStart(37)}`);
      say(`    HAKEDİŞİ                : ${TL(r.gross).padStart(37)}`);
      say('');
      say(`    Verilen avans (${String(r.avansKalem).padStart(2)} kalem): ${TL(r.avans).padStart(37)}`);
      say(`    Yapılan maaş ödemesi    : ${TL(r.odenen).padStart(37)}`);
      if (r.borc > 0) {
        say(`    İşverenin ona borcu     : ${TL(r.borc).padStart(37)}   (+)`);
        r.aktifBorclar.forEach((b) =>
          say(`        └ ${fmt(b.islemTarihi)}  ${TL(b.tutar)}${b.not ? '  — ' + b.not : ''}`)
        );
      }
      say(`    ELİNE GEÇEN TOPLAM      : ${TL(r.avans + r.odenen).padStart(37)}`);
      say('');
      const durum =
        r.net < -0.005
          ? `${TL(Math.abs(r.net))} FAZLA ALMIŞ  (işverene borçlu)`
          : r.net > 0.005
          ? `${TL(r.net)} ALACAĞI VAR`
          : 'HESAP KAPALI';
      say(`    >>> DURUM: ${durum}`);

      if (r.silinenBorc > 0) {
        const fark = 2 * r.silinenBorc;
        say('');
        say(`    ! 04.05.2026 DÜZELTMESİ (${TL(r.silinenBorc)})`);
        say(`      Bu tutar "Borç" olarak kaydedilmişti. Uygulama "Borç"u`);
        say(`      işverenin çalışana borcu sayıp maaşa EKLİYORDU. Oysa bu para`);
        say(`      çalışana VERİLMİŞTİ — yani avanstı, maaştan DÜŞMESİ gerekiyordu.`);
        say(`      Kayıt avansa çevrildi.`);
        say(`      Eski (hatalı) ekran : ${TL(r.net + fark)}`);
        say(`      Doğru rakam         : ${TL(r.net)}`);
        say(`      Düzeltme farkı      : ${TL(fark)}  (${TL(r.silinenBorc)} × 2 —`);
        say(`                            önce yanlış eklenmiş, şimdi doğru düşülüyor)`);
      }
      say('');
    }

    const eksi = rows.filter((r) => r.net < -0.005);
    const arti = rows.filter((r) => r.net > 0.005);
    say('='.repeat(74));
    say('  ÖZET');
    say('='.repeat(74));
    say(`    Fazla para almış çalışan : ${String(eksi.length).padStart(3)} kişi — toplam ${TL(
      Math.abs(eksi.reduce((s, r) => s + r.net, 0))
    )}`);
    say(`    Alacaklı çalışan         : ${String(arti.length).padStart(3)} kişi — toplam ${TL(
      arti.reduce((s, r) => s + r.net, 0)
    )}`);
    say(`    Hesabı kapalı            : ${String(rows.length - eksi.length - arti.length).padStart(3)} kişi`);
    say('');
    const duzeltilen = rows.filter((r) => r.silinenBorc > 0);
    if (duzeltilen.length) {
      say(`    04.05.2026 düzeltmesi yapılan: ${duzeltilen.length} kişi`);
      duzeltilen.forEach((r) =>
        say(`      · ${r.ad.padEnd(24)} ${TL(r.silinenBorc).padStart(13)} borç → avans`)
      );
    }
    say('');
  }

  if (SAVE) {
    const p = path.join(os.homedir(), 'Desktop', 'musteri_izah_raporu.txt');
    fs.writeFileSync(p, out.join('\n'), 'utf8');
    console.log(`\n→ Kaydedildi: ${p}`);
  }
  console.log('\nSalt-okunur; hiçbir veri değiştirilmedi.');
}

run()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('HATA:', e);
    process.exit(99);
  });
