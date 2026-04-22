import 'dart:convert';

import 'package:drift/drift.dart';

import '../app_database.dart';

class SyncQueueRepository {
  SyncQueueRepository(this._db);

  final AppDatabase _db;

  /// 15 başarısız denemeden sonra kalıcı hataya alınır. Deneme aralıkları
  /// exponential olarak büyür — böylece geçici Firestore/network sorunlarında
  /// saatler boyunca otomatik retry devam eder.
  static const int maxRetries = 15;

  Stream<int> pendingCount() {
    final countExp = _db.syncQueueItems.id.count();
    final query = _db.selectOnly(_db.syncQueueItems)
      ..addColumns([countExp])
      ..where(_db.syncQueueItems.status.equals('pending'));

    return query.watchSingle().map((row) => row.read(countExp) ?? 0);
  }

  Stream<int> failedPermanentCount() {
    final countExp = _db.syncQueueItems.id.count();
    final query = _db.selectOnly(_db.syncQueueItems)
      ..addColumns([countExp])
      ..where(_db.syncQueueItems.status.equals('failed_permanent'));

    return query.watchSingle().map((row) => row.read(countExp) ?? 0);
  }

  Future<List<SyncQueueItem>> failedPermanentItems() {
    final query = _db.select(_db.syncQueueItems)
      ..where((q) => q.status.equals('failed_permanent'))
      ..orderBy([(q) => OrderingTerm.desc(q.createdAt)]);
    return query.get();
  }

  Future<List<SyncQueueItem>> pendingItems() {
    final now = DateTime.now();
    final query = _db.select(_db.syncQueueItems)
      ..where(
        (q) =>
            q.status.equals('pending') &
            (q.nextAttemptAt.isNull() |
                q.nextAttemptAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(q) => OrderingTerm(expression: q.createdAt)]);
    return query.get();
  }

  Future<DateTime?> nextBackoffAt() async {
    final now = DateTime.now();
    final query = _db.select(_db.syncQueueItems)
      ..where(
        (q) =>
            q.status.equals('pending') &
            q.nextAttemptAt.isNotNull() &
            q.nextAttemptAt.isBiggerThanValue(now),
      )
      ..orderBy([(q) => OrderingTerm(expression: q.nextAttemptAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.nextAttemptAt;
  }

  Future<void> markSynced(String id) {
    return (_db.update(_db.syncQueueItems)
          ..where((q) => q.id.equals(id)))
        .write(
      SyncQueueItemsCompanion(
        status: const Value('done'),
        processedAt: Value(DateTime.now()),
        nextAttemptAt: const Value(null),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> markFailed(
    String id, {
    required int retryCount,
    String? error,
  }) {
    if (retryCount >= maxRetries) {
      return (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id)))
          .write(
        SyncQueueItemsCompanion(
          status: const Value('failed_permanent'),
          retryCount: Value(retryCount),
          lastError: Value(error),
        ),
      );
    }

    final delay = _backoffDelay(retryCount);
    final nextAt = DateTime.now().add(delay);
    return (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id)))
        .write(
      SyncQueueItemsCompanion(
        status: const Value('pending'),
        retryCount: Value(retryCount),
        nextAttemptAt: Value(nextAt),
        lastError: Value(error),
      ),
    );
  }

  /// Exponential backoff: 2s, 4s, 8s, 16s, 32s, 64s, 128s, 256s, 512s
  /// sonra 10dk tavan. Jitter eklenir ki birden fazla cihaz aynı anda
  /// thundering-herd oluşturmasın.
  Duration _backoffDelay(int retryCount) {
    final exp = retryCount.clamp(1, 10);
    final baseSeconds = 1 << exp;
    final capped = baseSeconds > 600 ? 600 : baseSeconds;
    final jitter = (DateTime.now().microsecondsSinceEpoch % 1000) / 1000.0;
    final withJitter = capped + (capped * 0.25 * jitter);
    return Duration(milliseconds: (withJitter * 1000).round());
  }

  /// Boş organizationId'li orphan kuyruk öğelerini verilen orgId ile tamir
  /// eder. Hem pending hem failed_permanent kapsanır — aksi halde orgId
  /// bulunamadığı için failed_permanent'a düşmüş orphan'lar "Tümünü Tekrar
  /// Dene" sonrası yine boş orgId ile pending'e dönüp tekrar fail olurdu.
  Future<int> backfillOrgId(String organizationId) {
    if (organizationId.isEmpty) return Future.value(0);
    return (_db.update(_db.syncQueueItems)
          ..where(
            (q) =>
                q.organizationId.equals('') &
                (q.status.equals('pending') |
                    q.status.equals('failed_permanent')),
          ))
        .write(
      SyncQueueItemsCompanion(organizationId: Value(organizationId)),
    );
  }

  Future<void> markAbandoned(String id, {String? reason}) {
    return (_db.update(_db.syncQueueItems)
          ..where((q) => q.id.equals(id)))
        .write(
      SyncQueueItemsCompanion(
        status: const Value('failed_permanent'),
        lastError: Value(reason),
      ),
    );
  }

  Future<int> retryFailedPermanent() {
    return (_db.update(_db.syncQueueItems)
          ..where((q) => q.status.equals('failed_permanent')))
        .write(
      const SyncQueueItemsCompanion(
        status: Value('pending'),
        retryCount: Value(0),
        nextAttemptAt: Value(null),
        lastError: Value(null),
      ),
    );
  }

  Map<String, dynamic> decodePayload(String payload) {
    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
