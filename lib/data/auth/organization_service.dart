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

  /// Kullanicinin organizasyonunu kontrol eder ya da ilk giriste olusturur.
  ///
  /// Coklu admin senaryosu:
  ///   - Admin 1 giriş yapar → yeni org olusturulur (orgId = uid)
  ///   - Admin 2 ve 3 icin `users/{uid}` dokumani:
  ///       `organizationId` alanina ilk adminin uid'si yazilir
  ///   - Sonraki girişlerde mevcut orgId bulunur ve kullanılır
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

    String orgId;
    if (userDoc.exists && userDoc.data()?['organizationId'] != null) {
      // Mevcut kullanici - organizasyon zaten tanimli
      orgId = userDoc.data()!['organizationId'] as String;
    } else {
      // Ilk giris - yeni organizasyon olustur
      orgId = uid;

      await _firestore.collection('organizations').doc(orgId).set({
        'id': orgId,
        'ownerUid': uid,
        'email': email,
        'createdAt': DateTime.now().toIso8601String(),
      });

      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'organizationId': orgId,
        'role': 'admin',
        'createdAt': DateTime.now().toIso8601String(),
      });
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
