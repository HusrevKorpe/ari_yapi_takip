import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/month_utils.dart';
import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';

class ExpenseRepository {
  ExpenseRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<Expense>> watchMonth(DateTime month) {
    final start = monthStart(month);
    final end = monthEnd(month);

    final query = _db.select(_db.expenses)
      ..where(
        (e) =>
            e.expenseDate.isBetweenValues(start, end) & e.deletedAt.isNull(),
      )
      ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]);
    return query.watch();
  }

  Future<void> addExpense({
    required DateTime date,
    required double amount,
    required String category,
    String? siteId,
    String? description,
  }) async {
    final id = _uuid.v4();
    final normalized = normalizeDay(date);

    await _db.transaction(() async {
      await _db.into(_db.expenses).insert(
        ExpensesCompanion.insert(
          id: id,
          expenseDate: normalized,
          amount: amount,
          category: category,
          siteId: Value(siteId),
          description: Value(description),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.expenses)
            ..where((e) => e.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'expense',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> deleteExpense({required String expenseId}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.expenses)
            ..where((e) => e.id.equals(expenseId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.expenses)..where((e) => e.id.equals(expenseId)))
          .write(ExpensesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        lastModifiedBy: Value(_ctx.userId),
        deviceId: Value(_ctx.deviceId),
        syncVersion: Value(nextVersion),
      ));

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'expense',
        entityId: expenseId,
        action: 'delete',
        payload: {
          'id': expenseId,
          'deletedAt': now.toIso8601String(),
          'lastModifiedBy': _ctx.userId,
          'deviceId': _ctx.deviceId,
          'syncVersion': nextVersion,
        },
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'expense',
        entityId: expenseId,
        message: 'Gider kaydi silindi',
      );
    });
  }

  Future<double> totalForMonth(DateTime month) async {
    final start = monthStart(month);
    final end = monthEnd(month);

    final totalExp = _db.expenses.amount.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([totalExp])
      ..where(_db.expenses.expenseDate.isBetweenValues(start, end) &
          _db.expenses.deletedAt.isNull());

    final row = await query.getSingle();
    return row.read(totalExp) ?? 0;
  }
}
