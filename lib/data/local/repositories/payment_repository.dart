import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/month_utils.dart';
import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';
import 'dtos.dart';
import 'payroll_repository.dart';

/// Aynı işçi + dönem için zaten aktif bir ödeme varken yeniden kaydetme
/// denenirse fırlatılır. UI bu hatayı yakalayıp kullanıcıya friendly mesaj
/// gösterir; hızlı çift tıklama ya da iki cihazdan eşzamanlı ödeme bu sayede
/// duplicate satır oluşturmadan engellenir.
class DuplicatePaymentException implements Exception {
  DuplicatePaymentException({
    required this.workerId,
    required this.periodStart,
    required this.periodEnd,
    required this.existingId,
  });

  final String workerId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String existingId;

  @override
  String toString() =>
      'Bu döneme ait ödeme zaten kayıtlı (id=$existingId).';
}

/// En son olmayan (arada kalan) bir ödemeyi iptal etme denendiğinde fırlatılır.
/// Açık dönem her zaman en son ödemenin bitişinden bir gün sonra başladığı için,
/// aradaki bir dönemi silmek o dönemi ne ödenmiş ne de yeniden hesaplanabilir
/// bırakır (maaş sessizce kaybolur). Bu yüzden yalnızca en son ödeme iptal
/// edilebilir; daha ileri bir dönemi kapatan aktif ödeme varsa iptal reddedilir.
class NotLatestPaymentException implements Exception {
  NotLatestPaymentException({
    required this.paymentId,
    required this.laterPaymentId,
  });

  final String paymentId;
  final String laterPaymentId;

  @override
  String toString() =>
      'Yalnızca en son ödeme iptal edilebilir (paymentId=$paymentId, '
      'daha yeni ödeme=$laterPaymentId).';
}

class PaymentRepository {
  /// [_payrollRepository] üretimde enjekte edilir; her ödeme, dönemin günlük
  /// dökümünü ödeme kaydıyla AYNI transaction içinde dondurmak için kullanılır.
  /// Testlerde snapshot'la ilgilenmeyen senaryolar bunu vermeyebilir (null).
  PaymentRepository(this._db, this._uuid, this._ctx, [this._payrollRepository]);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;
  final PayrollRepository? _payrollRepository;

  /// [amount] dönemin maaş olarak kapatılan kısmıdır. Kullanıcı hak edişten
  /// fazla öderse fazlalık [excessAdvance] olarak verilir ve aynı transaction
  /// içinde otomatik bir avans kaydı açılır — ödeme yazılıp avans yazılamazsa
  /// bakiye sessizce kayacağı için iki kayıt atomik olmak zorunda. Hak edişten
  /// az ödemede ek kayıt gerekmez; eksik, devreden bakiye (carryOver) olarak
  /// sonraki dönemde kendiliğinden görünür.
  Future<void> recordPayment({
    required String workerId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double amount,
    double excessAdvance = 0,
    String? excessAdvanceNote,
    PayrollResult? freeze,
  }) async {
    // Üretimde (PayrollRepository enjekte edilmiş) her ödeme, dönemin günlük
    // dökümünü aynı transaction içinde DONDURMAK zorunda: dökümsüz ödeme,
    // detayda "ödeme anındaki gün sayısı ≠ liste" tutarsızlığına yol açar.
    // Wiring varken freeze atlanırsa sessizce geçmeyip gürültülü hata veriyoruz.
    if (_payrollRepository != null && freeze == null) {
      throw StateError(
        'Ödeme dökümü dondurulmadan kaydedilemez (freeze verilmedi).',
      );
    }
    if (freeze != null && _payrollRepository == null) {
      throw StateError(
        'freeze verildi ama PayrollRepository enjekte edilmemiş.',
      );
    }

    final id = _uuid.v4();
    final now = DateTime.now();

    await _db.transaction(() async {
      // Pre-check: aynı dönem için aktif (silinmemiş) bir ödeme varsa hata
      // fırlat. Hızlı çift tıklama veya iki cihazdan eşzamanlı kayıt durumunda
      // partial unique index zaten ikinci INSERT'i reddeder; ancak burada
      // anlaşılır bir exception fırlatabilmek ve audit yazabilmek için elle
      // kontrol ediyoruz.
      final existing = await (_db.select(_db.payrollPayments)
            ..where(
              (p) =>
                  p.workerId.equals(workerId) &
                  p.periodStart.equals(periodStart) &
                  p.periodEnd.equals(periodEnd) &
                  p.deletedAt.isNull(),
            )
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        throw DuplicatePaymentException(
          workerId: workerId,
          periodStart: periodStart,
          periodEnd: periodEnd,
          existingId: existing.id,
        );
      }

      // Donmuş dökümü ödemeyle AYNI transaction'da yaz. Duplicate kontrolü
      // yukarıda döndüğü için reddedilen bir çift ödeme mevcut snapshot'ı
      // ASLA bozamaz; ödeme yazılamazsa döküm de (savepoint ile) geri alınır.
      if (freeze != null) {
        await _payrollRepository!.writeSnapshot(freeze);
      }

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

      if (excessAdvance > 0) {
        // Ödeme günü genelde kapanan dönemin içinde kaldığından bu avans
        // sonraki dönemin kesintisine girmez; lifetime pozisyon üzerinden
        // devreden bakiyeye (carryOver) yansıyarak sonraki maaştan düşer.
        final advanceId = _uuid.v4();
        await _db.into(_db.advanceDebts).insert(
          AdvanceDebtsCompanion.insert(
            id: advanceId,
            workerId: workerId,
            eventDate: normalizeDay(now),
            type: 'advance',
            amount: excessAdvance,
            note: Value(excessAdvanceNote ?? 'Maaş ödemesi fazlası'),
            settledMonth: monthKey(now),
            lastModifiedBy: Value(_ctx.userId),
            deviceId: Value(_ctx.deviceId),
            syncVersion: const Value(1),
          ),
        );

        final savedAdvance = await (_db.select(_db.advanceDebts)
              ..where((a) => a.id.equals(advanceId)))
            .getSingle();

        await _db.upsertQueueItem(
          id: _uuid.v4(),
          entityType: 'advance_debt',
          entityId: advanceId,
          action: 'upsert',
          payload: savedAdvance.toSyncMap(),
          organizationId: _ctx.organizationId,
        );
      }
    });
  }

  Future<double> totalPaid(String workerId) async {
    final payments = await (_db.select(_db.payrollPayments)
          ..where(
            (p) => p.workerId.equals(workerId) & p.deletedAt.isNull(),
          ))
        .get();
    return payments.fold<double>(0, (sum, p) => sum + p.amount);
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
      // Kayıt yok ya da zaten iptal edilmişse sessizce çık (idempotent).
      if (existing == null || existing.deletedAt != null) return;

      // Yalnızca en son (periodEnd'i en büyük) aktif ödeme iptal edilebilir.
      // Açık dönem daima en son ödemenin bitişinden sonra başladığından, arada
      // kalan bir ödemeyi silmek o dönemin maaşını erişilemez hâle getirir.
      // Bu işçi için daha ileri bir dönemi kapatan aktif ödeme varsa iptali
      // reddet; kullanıcı önce sonraki dönemleri iptal etmelidir.
      final later = await (_db.select(_db.payrollPayments)
            ..where(
              (p) =>
                  p.workerId.equals(existing.workerId) &
                  p.deletedAt.isNull() &
                  p.periodEnd.isBiggerThanValue(existing.periodEnd),
            )
            ..limit(1))
          .getSingleOrNull();
      if (later != null) {
        throw NotLatestPaymentException(
          paymentId: paymentId,
          laterPaymentId: later.id,
        );
      }

      final nextVersion = existing.syncVersion + 1;

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
        message: 'Ödeme iptal edildi',
      );
    });
  }
}
