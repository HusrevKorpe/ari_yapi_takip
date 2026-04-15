import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../local/app_database.dart';
import '../local/local_preferences.dart';

class OrganizationService {
  OrganizationService(this._prefs, this._db);

  final LocalPreferences _prefs;
  final AppDatabase _db;

  bool get _isFirebaseAvailable => Firebase.apps.isNotEmpty;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  /// Kullanicinin organizasyonunu bulur. Otomatik org yaratmaz.
  ///
  /// Coklu admin senaryosu:
  ///   - Her admin icin Firebase Console'dan `users/{uid}` dokumani elle
  ///     hazirlanir: `organizationId: <admin1_uid>` (admin 1 dahil).
  ///   - Admin 1 icin `organizations/{admin1_uid}` dokumani da once Console'dan
  ///     ya da bu metod tarafindan yaratilir (ilk admin kuralı auto-create'e izin
  ///     veren `allow create` kuralı ile uyumlu).
  ///   - users/{uid} bulunamazsa organizasyon-forking bug'ini engellemek icin
  ///     hata firlatir (önceki sürümde admin 2/3 sessizce kendi orgunu yaratıp
  ///     izole kaliyordu — "Firestore'da hiç veri yok" semptomu).
  Future<String> ensureOrganization({
    required String uid,
    required String? email,
  }) async {
    if (!_isFirebaseAvailable) {
      await _prefs.setUserId(uid);
      await _prefs.setOrganizationId(uid);
      return uid;
    }

    final userDoc = await _firestore.collection('users').doc(uid).get();
    String? orgIdRaw;
    if (userDoc.exists) {
      final data = userDoc.data();
      final value = data?['organizationId'];
      if (value is String) orgIdRaw = value;
    }

    if (orgIdRaw == null || orgIdRaw.isEmpty) {
      throw StateError(
        'Bu hesap icin kullanici kaydi tamamlanmamis. '
        'Firebase Console > Firestore > users/$uid dokumanina '
        '"organizationId" alani elle eklenmelidir. Admin 1 icin '
        'organizationId = $uid, Admin 2/3 icin = admin 1 uid\'i.',
      );
    }

    final orgId = orgIdRaw;

    // Admin 1 self-bootstrap: users/{uid}.organizationId == uid ise ve
    // organizations/{uid} henuz yoksa bu ilk admin kaydidir, kuralın izin
    // verdigi tek senaryo. Diger tüm kullanicilar icin org zaten yaratılmış
    // olmalı.
    if (orgId == uid) {
      final orgDoc = await _firestore
          .collection('organizations')
          .doc(orgId)
          .get();
      if (!orgDoc.exists) {
        await _firestore.collection('organizations').doc(orgId).set({
          'id': orgId,
          'ownerUid': uid,
          'email': email,
          'createdAt': DateTime.now().toIso8601String(),
        });
      }
    }

    final previousOrgId = _prefs.organizationId;
    if (previousOrgId.isNotEmpty && previousOrgId != orgId) {
      await _db.clearTenantScopedData();
      await _prefs.clearBootstrapCompleteFor(previousOrgId);
    }

    await _prefs.setUserId(uid);
    await _prefs.setOrganizationId(orgId);

    return orgId;
  }
}
