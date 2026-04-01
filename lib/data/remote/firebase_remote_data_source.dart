import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

abstract class RemoteDataSource {
  Future<void> upsert({
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
  });
}

class FirebaseRemoteDataSource implements RemoteDataSource {
  FirebaseRemoteDataSource() : _enabled = Firebase.apps.isNotEmpty;

  final bool _enabled;

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  @override
  Future<void> upsert({
    required String entityType,
    required String entityId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    if (!_enabled) {
      throw FirebaseException(
        plugin: 'firebase_core',
        code: 'not-initialized',
        message: 'Firebase initialize edilmedi.',
      );
    }

    await _firestore.collection(entityType).doc(entityId).set({
      ...payload,
      '_syncAction': action,
      '_syncedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }
}
