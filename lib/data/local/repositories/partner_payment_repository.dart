import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/month_utils.dart';
import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';

class PartnerPaymentRepository {
  PartnerPaymentRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<PartnerPayment>> watchAll() {
    final query = _db.select(_db.partnerPayments)
      ..where((p) => p.deletedAt.isNull())
      ..orderBy([(p) => OrderingTerm.desc(p.paymentDate)]);
    return query.watch();
  }

  Future<void> addPartnerPayment({
    required DateTime date,
    required double amount,
    required String partnerName,
    String? description,
  }) async {
    final id = _uuid.v4();
    final normalized = normalizeDay(date);

    await _db.transaction(() async {
      await _db.into(_db.partnerPayments).insert(
        PartnerPaymentsCompanion.insert(
          id: id,
          paymentDate: normalized,
          amount: amount,
          partnerName: partnerName,
          description: Value(description),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.partnerPayments)
            ..where((p) => p.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'partner_payment',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> updatePartnerPayment({
    required String paymentId,
    required DateTime date,
    required double amount,
    required String partnerName,
    String? description,
  }) async {
    final now = DateTime.now();
    final normalized = normalizeDay(date);

    await _db.transaction(() async {
      final existing = await (_db.select(_db.partnerPayments)
            ..where((p) => p.id.equals(paymentId)))
          .getSingleOrNull();
      if (existing == null) return;
      final nextVersion = existing.syncVersion + 1;

      await (_db.update(_db.partnerPayments)
            ..where((p) => p.id.equals(paymentId)))
          .write(PartnerPaymentsCompanion(
        paymentDate: Value(normalized),
        amount: Value(amount),
        partnerName: Value(partnerName),
        description: Value(description),
        updatedAt: Value(now),
        lastModifiedBy: Value(_ctx.userId),
        deviceId: Value(_ctx.deviceId),
        syncVersion: Value(nextVersion),
      ));

      final saved = await (_db.select(_db.partnerPayments)
            ..where((p) => p.id.equals(paymentId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'partner_payment',
        entityId: paymentId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'partner_payment',
        entityId: paymentId,
        message: 'Ortak odemesi guncellendi',
      );
    });
  }

  Future<void> deletePartnerPayment({required String paymentId}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.partnerPayments)
            ..where((p) => p.id.equals(paymentId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.partnerPayments)
            ..where((p) => p.id.equals(paymentId)))
          .write(PartnerPaymentsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        lastModifiedBy: Value(_ctx.userId),
        deviceId: Value(_ctx.deviceId),
        syncVersion: Value(nextVersion),
      ));

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'partner_payment',
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
        entityType: 'partner_payment',
        entityId: paymentId,
        message: 'Ortak odemesi silindi',
      );
    });
  }
}
