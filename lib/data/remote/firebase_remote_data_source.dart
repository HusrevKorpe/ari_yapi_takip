import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../sync/sync_collections.dart';

abstract class RemoteDataSource {
  Future<void> upsert({
    required String organizationId,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
  });

  Future<void> softDelete({
    required String organizationId,
    required String entityType,
    required String entityId,
    required DateTime deletedAt,
    required String deletedBy,
    String? deviceId,
    int? syncVersion,
  });

  bool get isAvailable;
}

class FirebaseRemoteDataSource implements RemoteDataSource {
  FirebaseRemoteDataSource() : _enabled = Firebase.apps.isNotEmpty;

  final bool _enabled;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static const _collectionMap = <String, String>{
    ...kEntityCollections,
    'audit_log': 'islem_kayitlari',
  };

  DocumentReference _docRef(String orgId, String entityType, String entityId) {
    final collection = _collectionMap[entityType] ?? entityType;
    return _firestore
        .collection('organizations')
        .doc(orgId)
        .collection(collection)
        .doc(entityId);
  }

  @override
  bool get isAvailable => _enabled;

  void _ensureAvailable() {
    if (!_enabled) {
      throw FirebaseException(
        plugin: 'firebase_core',
        code: 'not-initialized',
        message: 'Firebase initialize edilmedi.',
      );
    }
  }

  @override
  Future<void> upsert({
    required String organizationId,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
  }) async {
    _ensureAvailable();

    await _docRef(organizationId, entityType, entityId).set({
      ...payload,
      '_syncedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> softDelete({
    required String organizationId,
    required String entityType,
    required String entityId,
    required DateTime deletedAt,
    required String deletedBy,
    String? deviceId,
    int? syncVersion,
  }) async {
    _ensureAvailable();

    final payload = <String, dynamic>{
      'id': entityId,
      'silinmeTarihi': deletedAt.toIso8601String(),
      'sonDegistiren': deletedBy,
      '_syncedAt': DateTime.now().toIso8601String(),
    };
    if (deviceId != null && deviceId.isNotEmpty) {
      payload['cihazId'] = deviceId;
    }
    if (syncVersion != null) {
      payload['senkronSurumu'] = syncVersion;
    }

    await _docRef(
      organizationId,
      entityType,
      entityId,
    ).set(payload, SetOptions(merge: true));
  }
}
