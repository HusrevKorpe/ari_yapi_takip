import 'package:drift/native.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ari_yapi_takip/data/local/app_database.dart';
import 'package:ari_yapi_takip/data/sync/pull_sync_service.dart';

/// Verilen Firestore hata kodu için bir `FirebaseException` üretir.
FirebaseException fbError(String code) =>
    FirebaseException(plugin: 'cloud_firestore', code: code);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// Testin ihtiyaç duyduğu servis + callback çağrı kaydını üretir.
  ({PullSyncService service, List<Object> reported}) build() {
    final reported = <Object>[];
    final service = PullSyncService(
      database: db,
      deviceId: 'test-device',
      onPermissionDenied: reported.add,
    );
    return (service: service, reported: reported);
  }

  group('handleListenerError — kalıcı yetki reddi', () {
    test('permission-denied eşiği aşınca callback TAM olarak bir kez ateşlenir',
        () {
      final (:service, :reported) = build();
      final err = fbError('permission-denied');

      // İlk 4 hata geçici kabul edilir: reconnect (true), callback yok.
      for (var i = 0; i < 4; i++) {
        expect(
          service.handleListenerError('income', err),
          isTrue,
          reason: '${i + 1}. hatada hâlâ yeniden bağlanma beklenir',
        );
      }
      expect(reported, isEmpty);

      // 5. hata eşiği (fatal) aşar: döngü kesilir (false) + callback 1 kez.
      expect(service.handleListenerError('income', err), isFalse);
      expect(reported, hasLength(1));
      expect(reported.single, same(err));

      // Sonraki hatalar guard sayesinde tekrar bildirmez.
      service.handleListenerError('income', err);
      service.handleListenerError('income', err);
      expect(reported, hasLength(1));
    });

    test('unavailable (geçici ağ) hatası eşiği aşsa da callback ATEŞLEMEZ', () {
      final (:service, :reported) = build();
      final err = fbError('unavailable');

      // Fatal eşiğin çok üstünde tekrar etse bile ağ hatası kullanıcıya
      // ekran açtırmaz; her seferinde yeniden bağlanma sürer.
      for (var i = 0; i < 12; i++) {
        expect(service.handleListenerError('income', err), isTrue);
      }
      expect(reported, isEmpty);
    });

    test('FirebaseException olmayan genel hata callback ATEŞLEMEZ', () {
      final (:service, :reported) = build();

      for (var i = 0; i < 12; i++) {
        expect(service.handleListenerError('income', Exception('boom')), isTrue);
      }
      expect(reported, isEmpty);
    });
  });

  group('handleListenerError — sayaç davranışı', () {
    test('araya giren başarılı snapshot (resetFailures) sayacı sıfırlar', () {
      final (:service, :reported) = build();
      final err = fbError('permission-denied');

      for (var i = 0; i < 4; i++) {
        service.handleListenerError('income', err);
      }
      // Sağlıklı bir snapshot geldi: sayaç sıfırlanır.
      service.resetFailures('income');
      // Yeniden 4 hata eşiğe ulaşmaz → callback yok.
      for (var i = 0; i < 4; i++) {
        expect(service.handleListenerError('income', err), isTrue);
      }
      expect(reported, isEmpty);
    });

    test('koleksiyonlar bağımsız sayılır (biri eşiğe ulaşmaz)', () {
      final (:service, :reported) = build();
      final err = fbError('permission-denied');

      for (var i = 0; i < 4; i++) {
        service.handleListenerError('income', err);
      }
      service.handleListenerError('expense', err);

      expect(reported, isEmpty);
    });
  });
}
