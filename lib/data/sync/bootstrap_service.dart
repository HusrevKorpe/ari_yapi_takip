import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../local/app_database.dart';
import '../local/local_preferences.dart';
import 'sync_context.dart';
import 'sync_mappers.dart';

class BootstrapService {
  BootstrapService(this._db, this._uuid, this._prefs);

  final AppDatabase _db;
  final Uuid _uuid;
  final LocalPreferences _prefs;

  /// Bootstrap local data to remote under the given org.
  /// Stamps all existing rows with identity and enqueues them for sync.
  Future<void> run(SyncContext ctx) async {
    if (!ctx.isValid) return;
    if (_prefs.bootstrapCompleteFor(ctx.organizationId)) return;

    // Eski sürümlerden kalan boş organizationId'li orphan öğeleri temizle.
    await _db.deleteOrphanQueueItems();

    // Önceki yarım bootstrap girişiminden kalan pending öğeleri temizle.
    // bootstrapCompleteFor false ise henüz hiç kullanıcı işlemi yapılmamıştır,
    // bu öğelerin hepsi bootstrap'tan kalmadır.
    await (_db.delete(_db.syncQueueItems)
          ..where(
            (q) =>
                q.organizationId.equals(ctx.organizationId) &
                q.status.equals('pending'),
          ))
        .go();

    // Step 1: Stamp all existing rows with identity
    await _stampTable(_db.workers, ctx);
    await _stampTable(_db.sites, ctx);
    await _stampTable(_db.attendanceEntries, ctx);
    await _stampTable(_db.expenses, ctx);
    await _stampTable(_db.advanceDebts, ctx);
    await _stampTable(_db.payrollPayments, ctx);
    await _stampTable(_db.payrollSnapshots, ctx);

    // Step 2: Enqueue all entities for sync
    await _enqueueWorkers(ctx);
    await _enqueueSites(ctx);
    await _enqueueAttendance(ctx);
    await _enqueueExpenses(ctx);
    await _enqueueAdvanceDebts(ctx);
    await _enqueuePayrollPayments(ctx);
    await _enqueuePayrollSnapshots(ctx);

    // Step 3: Mark bootstrap complete
    await _prefs.setBootstrapCompleteFor(ctx.organizationId, true);
  }

  Future<void> _stampTable<T extends Table, D>(
    TableInfo<T, D> tableInfo,
    SyncContext ctx,
  ) async {
    await _db.customUpdate(
      'UPDATE ${tableInfo.actualTableName} '
      'SET last_modified_by = ?, device_id = ?, sync_version = 1 '
      'WHERE sync_version = 0',
      variables: [Variable(ctx.userId), Variable(ctx.deviceId)],
      updates: {tableInfo},
    );
  }

  Future<void> _enqueueWorkers(SyncContext ctx) async {
    final rows = await (_db.select(
      _db.workers,
    )..where((w) => w.deletedAt.isNull())).get();
    for (final row in rows) {
      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'worker',
        entityId: row.id,
        action: 'upsert',
        payload: row.toSyncMap(),
        organizationId: ctx.organizationId,
      );
    }
  }

  Future<void> _enqueueSites(SyncContext ctx) async {
    final rows = await (_db.select(
      _db.sites,
    )..where((s) => s.deletedAt.isNull())).get();
    for (final row in rows) {
      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'site',
        entityId: row.id,
        action: 'upsert',
        payload: row.toSyncMap(),
        organizationId: ctx.organizationId,
      );
    }
  }

  Future<void> _enqueueAttendance(SyncContext ctx) async {
    final rows = await (_db.select(
      _db.attendanceEntries,
    )..where((a) => a.deletedAt.isNull())).get();
    for (final row in rows) {
      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'attendance',
        entityId: row.id,
        action: 'upsert',
        payload: row.toSyncMap(),
        organizationId: ctx.organizationId,
      );
    }
  }

  Future<void> _enqueueExpenses(SyncContext ctx) async {
    final rows = await (_db.select(
      _db.expenses,
    )..where((e) => e.deletedAt.isNull())).get();
    for (final row in rows) {
      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'expense',
        entityId: row.id,
        action: 'upsert',
        payload: row.toSyncMap(),
        organizationId: ctx.organizationId,
      );
    }
  }

  Future<void> _enqueueAdvanceDebts(SyncContext ctx) async {
    final rows = await (_db.select(
      _db.advanceDebts,
    )..where((a) => a.deletedAt.isNull())).get();
    for (final row in rows) {
      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'advance_debt',
        entityId: row.id,
        action: 'upsert',
        payload: row.toSyncMap(),
        organizationId: ctx.organizationId,
      );
    }
  }

  Future<void> _enqueuePayrollPayments(SyncContext ctx) async {
    final rows = await (_db.select(
      _db.payrollPayments,
    )..where((p) => p.deletedAt.isNull())).get();
    for (final row in rows) {
      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'payroll_payment',
        entityId: row.id,
        action: 'upsert',
        payload: row.toSyncMap(),
        organizationId: ctx.organizationId,
      );
    }
  }

  Future<void> _enqueuePayrollSnapshots(SyncContext ctx) async {
    final rows = await (_db.select(
      _db.payrollSnapshots,
    )..where((s) => s.deletedAt.isNull())).get();
    for (final row in rows) {
      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'payroll_snapshot',
        entityId: row.id,
        action: 'upsert',
        payload: row.toSyncMap(),
        organizationId: ctx.organizationId,
      );
    }
  }
}
