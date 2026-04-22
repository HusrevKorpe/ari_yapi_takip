import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/month_utils.dart';
import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';

class AdvanceDebtRepository {
  AdvanceDebtRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Future<void> add({
    required String workerId,
    required DateTime date,
    required String type,
    required double amount,
    String? note,
  }) async {
    final id = _uuid.v4();
    final month = monthKey(date);

    await _db.transaction(() async {
      await _db.into(_db.advanceDebts).insert(
        AdvanceDebtsCompanion.insert(
          id: id,
          workerId: workerId,
          eventDate: normalizeDay(date),
          type: type,
          amount: amount,
          note: Value(note),
          settledMonth: month,
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.advanceDebts)
            ..where((a) => a.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'advance_debt',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<double> totalDeductions({
    required String workerId,
    required DateTime start,
    required DateTime end,
  }) async {
    final entries = await (_db.select(_db.advanceDebts)
          ..where(
            (a) =>
                a.workerId.equals(workerId) &
                a.eventDate.isBetweenValues(start, end) &
                a.deletedAt.isNull(),
          ))
        .get();

    double total = 0;
    for (final e in entries) {
      if (e.type == 'advance') {
        total += e.amount;
      } else if (e.type == 'debt') {
        total -= e.amount;
      }
    }
    return total;
  }

  Stream<List<AdvanceDebt>> watchByWorker(String workerId) {
    final query = _db.select(_db.advanceDebts)
      ..where((a) => a.workerId.equals(workerId) & a.deletedAt.isNull())
      ..orderBy([(a) => OrderingTerm.desc(a.eventDate)]);
    return query.watch();
  }

  Future<void> delete({required String id}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.advanceDebts)
            ..where((a) => a.id.equals(id)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.advanceDebts)..where((a) => a.id.equals(id)))
          .write(
        AdvanceDebtsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'advance_debt',
        entityId: id,
        action: 'delete',
        payload: {
          'id': id,
          'deletedAt': now.toIso8601String(),
          'lastModifiedBy': _ctx.userId,
          'deviceId': _ctx.deviceId,
          'syncVersion': nextVersion,
        },
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'advance_debt',
        entityId: id,
        message: 'Avans/Borc kaydi silindi',
      );
    });
  }
}
