import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ari_yapi_takip/data/local/app_database.dart';
import 'package:ari_yapi_takip/data/local/repositories.dart';
import 'package:ari_yapi_takip/data/remote/firebase_remote_data_source.dart';
import 'package:ari_yapi_takip/data/sync/sync_service.dart';

class _FakeConnectivity extends Fake implements Connectivity {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class _FakeRemote implements RemoteDataSource {
  bool failWrites = false;
  final upserts = <String>[];
  final deletes = <String>[];

  @override
  bool get isAvailable => true;

  @override
  Future<void> upsert({
    required String organizationId,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
  }) async {
    if (failWrites) throw Exception('permission-denied');
    upserts.add('$organizationId/$entityType/$entityId');
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
    if (failWrites) throw Exception('permission-denied');
    deletes.add('$organizationId/$entityType/$entityId');
  }
}

void main() {
  late AppDatabase db;
  late SyncQueueRepository repo;
  late _FakeRemote remote;
  late SyncService service;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SyncQueueRepository(db);
    remote = _FakeRemote();
    service = SyncService(
      queueRepository: repo,
      remoteDataSource: remote,
      connectivity: _FakeConnectivity(),
      organizationIdResolver: () => 'org-1',
    );
  });

  tearDown(() => db.close());

  Future<void> insertItem(
    String id, {
    String status = 'failed_permanent',
    String action = 'upsert',
    String organizationId = 'org-1',
    int retryCount = 15,
    String payload = '{"tutar": 10300}',
  }) {
    return db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: id,
            entityType: 'payroll_payment',
            entityId: 'e-$id',
            action: action,
            payload: Value(payload),
            status: Value(status),
            organizationId: Value(organizationId),
            retryCount: Value(retryCount),
            lastError: const Value('permission-denied (eski)'),
          ),
        );
  }

  Future<SyncQueueItem> readItem(String id) {
    return (db.select(db.syncQueueItems)..where((q) => q.id.equals(id)))
        .getSingle();
  }

  group('probeFailedPermanent', () {
    test('sunucu düzelmişse failed_permanent öğe otomatik kurtarılır',
        () async {
      await insertItem('1');

      await service.probeFailedPermanent();

      final item = await readItem('1');
      expect(item.status, 'done');
      expect(remote.upserts, ['org-1/payroll_payment/e-1']);
    });

    test('delete aksiyonlu öğe softDelete ile gönderilir', () async {
      await insertItem(
        '1',
        action: 'delete',
        payload: '{"silinmeTarihi": "2026-07-08T12:00:00.000"}',
      );

      await service.probeFailedPermanent();

      final item = await readItem('1');
      expect(item.status, 'done');
      expect(remote.deletes, ['org-1/payroll_payment/e-1']);
    });

    test('sunucu hâlâ reddediyorsa durum korunur, lastError güncellenir',
        () async {
      await insertItem('1');
      remote.failWrites = true;

      await service.probeFailedPermanent();

      final item = await readItem('1');
      expect(item.status, 'failed_permanent');
      expect(item.lastError, contains('permission-denied'));
      expect(item.lastError, isNot(contains('eski')));
      // Sonda pending'e döndürmez — banner görünmeye devam etmeli.
      expect(item.retryCount, 15);
    });

    test('sondalar failedProbeInterval içinde tekrarlanmaz', () async {
      await insertItem('1');
      remote.failWrites = true;
      await service.probeFailedPermanent();

      // Sunucu düzeldi ama aralık dolmadı → öğe henüz kurtarılmamalı.
      remote.failWrites = false;
      await service.probeFailedPermanent();

      final item = await readItem('1');
      expect(item.status, 'failed_permanent');
      expect(remote.upserts, isEmpty);
    });

    test('kuyruk boşken sonda zaman damgası bırakmaz — ilk gerçek sonda çalışır',
        () async {
      await service.probeFailedPermanent();

      await insertItem('1');
      await service.probeFailedPermanent();

      final item = await readItem('1');
      expect(item.status, 'done');
    });

    test('boş orgId\'li orphan öğe mevcut org ile tamir edilip gönderilir',
        () async {
      await insertItem('1', organizationId: '');

      await service.probeFailedPermanent();

      final item = await readItem('1');
      expect(item.status, 'done');
      expect(remote.upserts, ['org-1/payroll_payment/e-1']);
    });
  });

  group('flushPending tetiklemesi', () {
    test('pending öğe başarıyla gidince failed_permanent öğeler de denenir',
        () async {
      await insertItem('p1', status: 'pending', retryCount: 0);
      await insertItem('f1');

      await service.flushPending();

      expect((await readItem('p1')).status, 'done');
      expect((await readItem('f1')).status, 'done');
    });

    test('hiçbir pending başarılı olmazsa failed_permanent dokunulmaz',
        () async {
      await insertItem('p1', status: 'pending', retryCount: 0);
      await insertItem('f1');
      remote.failWrites = true;

      await service.flushPending();

      expect((await readItem('f1')).status, 'failed_permanent');
      // Sonda hiç koşmadığı için zaman damgası kalmadı; sunucu düzelince
      // ilk sonda hemen çalışabilir.
      remote.failWrites = false;
      await service.probeFailedPermanent();
      expect((await readItem('f1')).status, 'done');
    });
  });
}
