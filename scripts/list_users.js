// Firebase Auth'taki kayitli kullanicilari listeler (e-posta, uid, son giris).
// Kullanim: node scripts/list_users.js
const admin = require('firebase-admin');
const path = require('path');
const fs = require('fs');

const serviceAccountPath =
  process.env.SERVICE_ACCOUNT_PATH ||
  path.resolve(__dirname, '..', 'serviceAccount.json');

if (!fs.existsSync(serviceAccountPath)) {
  console.error(`Service account JSON bulunamadi: ${serviceAccountPath}`);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(serviceAccountPath)),
});

(async () => {
  const result = await admin.auth().listUsers(1000);
  if (result.users.length === 0) {
    console.log('Hic kullanici yok.');
    return;
  }
  console.log(`Toplam ${result.users.length} kullanici:\n`);
  result.users.forEach((u, i) => {
    console.log(`${i + 1}. e-posta: ${u.email || '(yok)'}`);
    console.log(`   uid: ${u.uid}`);
    console.log(`   olusturulma: ${u.metadata.creationTime}`);
    console.log(`   son giris:   ${u.metadata.lastSignInTime || '-'}`);
    console.log('');
  });
  process.exit(0);
})().catch((e) => {
  console.error('Hata:', e.message);
  process.exit(1);
});
