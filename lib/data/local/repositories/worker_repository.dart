import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';

class WorkerRepository {
  WorkerRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<Worker>> watchActiveWorkers() {
    final query = _db.select(_db.workers)
      ..where((w) => w.isActive.equals(true) & w.deletedAt.isNull())
      ..orderBy([(w) => OrderingTerm(expression: w.fullName)]);
    return query.watch();
  }

  Future<List<Worker>> getActiveWorkers() {
    final query = _db.select(_db.workers)
      ..where((w) => w.isActive.equals(true) & w.deletedAt.isNull())
      ..orderBy([(w) => OrderingTerm(expression: w.fullName)]);
    return query.get();
  }

  Future<void> saveWorker({
    String? id,
    required String fullName,
    required double dailyWage,
    String? defaultSiteId,
    String? notes,
    String payFrequency = 'weekly',
    bool isActive = true,
  }) async {
    final workerId = id ?? _uuid.v4();
    final now = DateTime.now();

    await _db.transaction(() async {
      int nextVersion = 1;
      if (id != null) {
        final existing = await (_db.select(_db.workers)
              ..where((w) => w.id.equals(id)))
            .getSingleOrNull();
        if (existing != null) nextVersion = existing.syncVersion + 1;
      }

      await _db.into(_db.workers).insertOnConflictUpdate(
        WorkersCompanion.insert(
          id: workerId,
          fullName: fullName,
          dailyWage: dailyWage,
          defaultSiteId: Value(defaultSiteId),
          payFrequency: Value(payFrequency),
          notes: Value(notes),
          isActive: Value(isActive),
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.workers)
            ..where((w) => w.id.equals(workerId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'worker',
        entityId: workerId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'worker',
        entityId: workerId,
        message: 'Worker kaydi guncellendi',
      );
    });
  }

  Future<void> deactivateWorker({required String workerId}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.workers)
            ..where((w) => w.id.equals(workerId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.workers)..where((w) => w.id.equals(workerId)))
          .write(
        WorkersCompanion(
          isActive: const Value(false),
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.workers)
            ..where((w) => w.id.equals(workerId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'worker',
        entityId: workerId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'worker',
        entityId: workerId,
        message: 'Worker pasife alindi',
      );
    });
  }
}
