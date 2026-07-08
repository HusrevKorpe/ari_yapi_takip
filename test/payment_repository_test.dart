import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:ari_yapi_takip/data/local/app_database.dart';
import 'package:ari_yapi_takip/data/local/repositories/payment_repository.dart';
import 'package:ari_yapi_takip/data/sync/sync_context.dart';

void main() {
  late AppDatabase db;
  late PaymentRepository repo;

  const worker = 'worker-1';
  const ctx = SyncContext(
    userId: 'u1',
    deviceId: 'd1',
    organizationId: 'org1',
  );

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = PaymentRepository(db, const Uuid(), ctx);
  });
  tearDown(() => db.close());

  /// Verilen dönemi kapatan aktif ödemeyi bulur.
  Future<PayrollPayment> paymentEndingAt(DateTime end) async {
    final all = await db.select(db.payrollPayments).get();
    return all.firstWhere(
      (p) => p.periodEnd == end && p.deletedAt == null,
    );
  }

  group('deletePayment — yalnızca en son ödeme iptal edilebilir', () {
    final jun1 = DateTime(2026, 6, 1);
    final jun15 = DateTime(2026, 6, 15);
    final jun16 = DateTime(2026, 6, 16);
    final jul4 = DateTime(2026, 7, 4);

    Future<void> seedTwoContiguousPayments() async {
      // P1: [1 Haz, 15 Haz]
      await repo.recordPayment(
        workerId: worker,
        periodStart: jun1,
        periodEnd: jun15,
        amount: 1000,
      );
      // P2: [16 Haz, 4 Tem]
      await repo.recordPayment(
        workerId: worker,
        periodStart: jun16,
        periodEnd: jul4,
        amount: 2000,
      );
    }

    test('arada kalan (eski) ödemenin iptali reddedilir ve kayıt korunur',
        () async {
      await seedTwoContiguousPayments();
      final p1 = await paymentEndingAt(jun15);

      await expectLater(
        repo.deletePayment(paymentId: p1.id),
        throwsA(isA<NotLatestPaymentException>()),
      );

      // Hiçbir şey silinmedi: iki ödeme de aktif, dönem sonu değişmedi.
      expect(await repo.totalPaid(worker), 3000);
      expect(await repo.lastPaymentEnd(worker), jul4);
    });

    test('en son ödeme iptal edilebilir ve dönem doğru şekilde geri açılır',
        () async {
      await seedTwoContiguousPayments();
      final p2 = await paymentEndingAt(jul4);

      await repo.deletePayment(paymentId: p2.id);

      // P2 gitti; açık dönem yeniden P1'in bitişinden sonra başlamalı.
      expect(await repo.totalPaid(worker), 1000);
      expect(await repo.lastPaymentEnd(worker), jun15);

      // P2 iptal edildikten sonra P1 artık en son ödeme → iptal edilebilir.
      final p1 = await paymentEndingAt(jun15);
      await repo.deletePayment(paymentId: p1.id);
      expect(await repo.totalPaid(worker), 0);
      expect(await repo.lastPaymentEnd(worker), isNull);
    });

    test('tek ödeme her zaman iptal edilebilir', () async {
      await repo.recordPayment(
        workerId: worker,
        periodStart: jun1,
        periodEnd: jun15,
        amount: 1000,
      );
      final p1 = await paymentEndingAt(jun15);

      await repo.deletePayment(paymentId: p1.id);
      expect(await repo.lastPaymentEnd(worker), isNull);
    });

    test('başka işçinin daha ileri dönemi iptali engellemez', () async {
      // Bu işçinin tek ödemesi var; başka işçide daha geç biten ödeme olsa da
      // guard yalnızca aynı workerId için ileri dönem arar.
      await repo.recordPayment(
        workerId: worker,
        periodStart: jun1,
        periodEnd: jun15,
        amount: 1000,
      );
      await repo.recordPayment(
        workerId: 'worker-2',
        periodStart: jun16,
        periodEnd: jul4,
        amount: 5000,
      );
      final p1 = await paymentEndingAt(jun15);

      await repo.deletePayment(paymentId: p1.id);
      expect(await repo.lastPaymentEnd(worker), isNull);
    });
  });

  group('deletePayment — idempotentlik', () {
    final jun1 = DateTime(2026, 6, 1);
    final jun15 = DateTime(2026, 6, 15);

    test('zaten iptal edilmiş ödemeyi tekrar silmek hata vermez', () async {
      await repo.recordPayment(
        workerId: worker,
        periodStart: jun1,
        periodEnd: jun15,
        amount: 1000,
      );
      final p1 = await paymentEndingAt(jun15);

      await repo.deletePayment(paymentId: p1.id);
      // İkinci çağrı sessizce geçmeli (early-return).
      await repo.deletePayment(paymentId: p1.id);
      expect(await repo.totalPaid(worker), 0);
    });

    test('var olmayan id sessizce geçilir', () async {
      await repo.deletePayment(paymentId: 'yok-boyle-bir-id');
      expect(await repo.totalPaid(worker), 0);
    });
  });

  group('recordPayment — fazla ödeme otomatik avans', () {
    final jun1 = DateTime(2026, 6, 1);
    final jun15 = DateTime(2026, 6, 15);

    test('excessAdvance verilince aynı işlemde avans kaydı ve kuyruk öğesi oluşur',
        () async {
      await repo.recordPayment(
        workerId: worker,
        periodStart: jun1,
        periodEnd: jun15,
        amount: 1000,
        excessAdvance: 250,
        excessAdvanceNote: 'Maaş ödemesi fazlası (test)',
      );

      // Ödeme yalnızca maaş kısmını içerir; fazlası ayrı avans satırıdır.
      expect(await repo.totalPaid(worker), 1000);

      final advances = await db.select(db.advanceDebts).get();
      expect(advances, hasLength(1));
      final advance = advances.single;
      expect(advance.workerId, worker);
      expect(advance.type, 'advance');
      expect(advance.amount, 250);
      expect(advance.note, 'Maaş ödemesi fazlası (test)');
      expect(advance.deletedAt, isNull);

      // Her iki kayıt da sync kuyruğuna girmiş olmalı.
      final queue = await db.select(db.syncQueueItems).get();
      expect(
        queue.where(
          (q) => q.entityType == 'advance_debt' && q.entityId == advance.id,
        ),
        hasLength(1),
      );
      expect(
        queue.where((q) => q.entityType == 'payroll_payment'),
        hasLength(1),
      );
    });

    test('excessAdvance verilmezse avans kaydı oluşmaz', () async {
      await repo.recordPayment(
        workerId: worker,
        periodStart: jun1,
        periodEnd: jun15,
        amount: 1000,
      );
      expect(await db.select(db.advanceDebts).get(), isEmpty);
    });

    test('duplicate ödeme reddedilince avans da yazılmaz (atomiklik)',
        () async {
      await repo.recordPayment(
        workerId: worker,
        periodStart: jun1,
        periodEnd: jun15,
        amount: 1000,
      );

      await expectLater(
        repo.recordPayment(
          workerId: worker,
          periodStart: jun1,
          periodEnd: jun15,
          amount: 1200,
          excessAdvance: 500,
        ),
        throwsA(isA<DuplicatePaymentException>()),
      );

      expect(await repo.totalPaid(worker), 1000);
      expect(await db.select(db.advanceDebts).get(), isEmpty);
    });
  });

  group('recordPayment — aynı dönem için tekrar kayıt engellenir', () {
    final jun1 = DateTime(2026, 6, 1);
    final jun15 = DateTime(2026, 6, 15);

    test('aynı işçi+dönem ikinci kez kaydedilince DuplicatePayment fırlar',
        () async {
      await repo.recordPayment(
        workerId: worker,
        periodStart: jun1,
        periodEnd: jun15,
        amount: 1000,
      );

      await expectLater(
        repo.recordPayment(
          workerId: worker,
          periodStart: jun1,
          periodEnd: jun15,
          amount: 1000,
        ),
        throwsA(isA<DuplicatePaymentException>()),
      );

      // Tek satır kaldı.
      expect(await repo.totalPaid(worker), 1000);
    });
  });
}
