import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/month_utils.dart';
import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';

class IncomeRepository {
  IncomeRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<Income>> watchMonth(DateTime month) {
    final start = monthStart(month);
    final end = monthEnd(month);

    final query = _db.select(_db.incomes)
      ..where(
        (i) =>
            i.incomeDate.isBetweenValues(start, end) & i.deletedAt.isNull(),
      )
      ..orderBy([(i) => OrderingTerm.desc(i.incomeDate)]);
    return query.watch();
  }

  Future<void> addIncome({
    required DateTime date,
    required double amount,
    required String category,
    String? siteId,
    String? description,
  }) async {
    final id = _uuid.v4();
    final normalized = normalizeDay(date);

    await _db.transaction(() async {
      await _db.into(_db.incomes).insert(
        IncomesCompanion.insert(
          id: id,
          incomeDate: normalized,
          amount: amount,
          category: category,
          siteId: Value(siteId),
          description: Value(description),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.incomes)
            ..where((i) => i.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'income',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> deleteIncome({required String incomeId}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.incomes)
            ..where((i) => i.id.equals(incomeId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.incomes)..where((i) => i.id.equals(incomeId)))
          .write(IncomesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        lastModifiedBy: Value(_ctx.userId),
        deviceId: Value(_ctx.deviceId),
        syncVersion: Value(nextVersion),
      ));

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'income',
        entityId: incomeId,
        action: 'delete',
        payload: {
          'id': incomeId,
          'deletedAt': now.toIso8601String(),
          'lastModifiedBy': _ctx.userId,
          'deviceId': _ctx.deviceId,
          'syncVersion': nextVersion,
        },
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'income',
        entityId: incomeId,
        message: 'Gelir kaydi silindi',
      );
    });
  }

  Future<double> totalForMonth(DateTime month) async {
    final start = monthStart(month);
    final end = monthEnd(month);

    final totalExp = _db.incomes.amount.sum();
    final query = _db.selectOnly(_db.incomes)
      ..addColumns([totalExp])
      ..where(_db.incomes.incomeDate.isBetweenValues(start, end) &
          _db.incomes.deletedAt.isNull());

    final row = await query.getSingle();
    return row.read(totalExp) ?? 0;
  }
}
