import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';

class PaymentRepository {
  PaymentRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Future<void> recordPayment({
    required String workerId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double amount,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await _db.transaction(() async {
      await _db.into(_db.payrollPayments).insert(
        PayrollPaymentsCompanion.insert(
          id: id,
          workerId: workerId,
          periodStart: periodStart,
          periodEnd: periodEnd,
          amount: amount,
          paidAt: now,
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.payrollPayments)
            ..where((p) => p.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'payroll_payment',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<DateTime?> lastPaymentEnd(String workerId) async {
    final query = _db.select(_db.payrollPayments)
      ..where((p) => p.workerId.equals(workerId) & p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.desc(p.periodEnd)])
      ..limit(1);
    final results = await query.get();
    return results.isEmpty ? null : results.first.periodEnd;
  }

  Stream<List<PayrollPayment>> watchWorkerPayments(String workerId) {
    final query = _db.select(_db.payrollPayments)
      ..where((p) => p.workerId.equals(workerId) & p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.desc(p.paidAt)]);
    return query.watch();
  }

  Future<void> deletePayment({required String paymentId}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.payrollPayments)
            ..where((p) => p.id.equals(paymentId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.payrollPayments)
            ..where((p) => p.id.equals(paymentId)))
          .write(PayrollPaymentsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        lastModifiedBy: Value(_ctx.userId),
        deviceId: Value(_ctx.deviceId),
        syncVersion: Value(nextVersion),
      ));

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'payroll_payment',
        entityId: paymentId,
        action: 'delete',
        payload: {
          'id': paymentId,
          'deletedAt': now.toIso8601String(),
          'lastModifiedBy': _ctx.userId,
          'deviceId': _ctx.deviceId,
          'syncVersion': nextVersion,
        },
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'payroll_payment',
        entityId: paymentId,
        message: 'Odeme iptal edildi',
      );
    });
  }
}
