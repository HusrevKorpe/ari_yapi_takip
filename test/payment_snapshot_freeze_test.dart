import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:ari_yapi_takip/data/local/app_database.dart';
import 'package:ari_yapi_takip/data/local/repositories/advance_debt_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/attendance_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/payment_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/payroll_repository.dart';
import 'package:ari_yapi_takip/data/sync/sync_context.dart';

/// "12 gün ama listede 13" tutarsızlığına karşı kalıcı önlemin regresyon testi:
///  1) Her ödeme, dönemin günlük dökümünü ödeme kaydıyla AYNI transaction'da
///     dondurur (getSnapshotDays boş dönmez ve gün sayısı özetle tutar).
///  2) Reddedilen bir çift ödeme, mevcut donmuş dökümü BOZMAZ.
///  3) Üretim wiring'inde (PayrollRepository enjekte) freeze verilmeden ödeme
///     yapılamaz.
///  4) Eski ödemeler asOf ile ödeme anındaki günlerden yeniden kurulur.
void main() {
  late AppDatabase db;
  late PayrollRepository payroll;
  late PaymentRepository payments;

  const ctx = SyncContext(
    userId: 'u1',
    deviceId: 'd1',
    organizationId: 'org1',
  );

  final periodStart = DateTime(2026, 6, 8);
  final periodEnd = DateTime(2026, 6, 27);
  final payAt = DateTime(2026, 6, 27, 7, 52); // ödeme sabah yapılıyor

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    const uuid = Uuid();
    payroll = PayrollRepository(
      database: db,
      attendanceRepository: AttendanceRepository(db, uuid, ctx),
      advanceDebtRepository: AdvanceDebtRepository(db, uuid, ctx),
      uuid: uuid,
      syncContext: ctx,
    );
    // Üretimdeki gibi PayrollRepository enjekte edilmiş PaymentRepository.
    payments = PaymentRepository(db, uuid, ctx, payroll);

    await db.into(db.workers).insert(
          WorkersCompanion.insert(
            id: 'w1',
            fullName: 'Osman Test',
            dailyWage: 2500,
            receivesBonus: const Value(false),
          ),
        );
  });
  tearDown(() => db.close());

  Future<Worker> worker() =>
      (db.select(db.workers)..where((w) => w.id.equals('w1'))).getSingle();

  Future<void> addDay(DateTime date, String status, {DateTime? createdAt}) {
    return db.into(db.attendanceEntries).insert(
          AttendanceEntriesCompanion.insert(
            id: 'att-${date.day}-$status',
            workerId: 'w1',
            workDate: date,
            status: status,
            createdAt:
                createdAt == null ? const Value.absent() : Value(createdAt),
          ),
        );
  }

  test('recordPayment dönemin günlük dökümünü dondurur', () async {
    await addDay(DateTime(2026, 6, 8), 'worked');
    await addDay(DateTime(2026, 6, 9), 'worked');
    await addDay(DateTime(2026, 6, 10), 'worked');

    final result = await payroll.calculate(
      worker: await worker(),
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    expect(result.workedDayEquivalent, 3);

    await payments.recordPayment(
      workerId: 'w1',
      periodStart: periodStart,
      periodEnd: periodEnd,
      amount: result.net,
      freeze: result,
    );

    final days = await payroll.getSnapshotDays(
      workerId: 'w1',
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    expect(days, isNotNull);
    expect(days!.length, 3);
    final frozenWorked = days.fold<double>(0, (s, d) => s + d.dayEquivalent);
    // Donmuş listenin gün toplamı, özetteki "çalışılan gün" ile bire bir tutmalı.
    expect(frozenWorked, result.workedDayEquivalent);
  });

  test('üretim wiring\'inde freeze verilmeden ödeme reddedilir', () async {
    await expectLater(
      payments.recordPayment(
        workerId: 'w1',
        periodStart: periodStart,
        periodEnd: periodEnd,
        amount: 100,
      ),
      throwsA(isA<StateError>()),
    );
    expect(await payments.totalPaid('w1'), 0);
  });

  test('reddedilen çift ödeme mevcut donmuş dökümü bozmaz', () async {
    await addDay(DateTime(2026, 6, 8), 'worked',
        createdAt: DateTime(2026, 6, 8));
    await addDay(DateTime(2026, 6, 9), 'worked',
        createdAt: DateTime(2026, 6, 9));
    await addDay(DateTime(2026, 6, 10), 'worked',
        createdAt: DateTime(2026, 6, 10));

    final first = await payroll.calculate(
      worker: await worker(),
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    await payments.recordPayment(
      workerId: 'w1',
      periodStart: periodStart,
      periodEnd: periodEnd,
      amount: first.net,
      freeze: first,
    );

    // Ödemeden SONRA döneme yeni bir gün eklenir (osman'ın 27.06'sı gibi).
    await addDay(DateTime(2026, 6, 27), 'worked',
        createdAt: DateTime(2026, 6, 27, 14, 22));
    final second = await payroll.calculate(
      worker: await worker(),
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    expect(second.workedDayEquivalent, 4);

    // Aynı dönem için ikinci ödeme reddedilmeli...
    await expectLater(
      payments.recordPayment(
        workerId: 'w1',
        periodStart: periodStart,
        periodEnd: periodEnd,
        amount: second.net,
        freeze: second,
      ),
      throwsA(isA<DuplicatePaymentException>()),
    );

    // ...ve mevcut donmuş döküm hâlâ 3 gün olmalı (4'e bozulmamalı).
    final days = await payroll.getSnapshotDays(
      workerId: 'w1',
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    expect(days, isNotNull);
    expect(days!.length, 3);
  });

  test('asOf, eski ödemeyi ödeme anındaki günlerden yeniden kurar', () async {
    await addDay(DateTime(2026, 6, 8), 'worked',
        createdAt: DateTime(2026, 6, 8));
    await addDay(DateTime(2026, 6, 9), 'worked',
        createdAt: DateTime(2026, 6, 9));
    await addDay(DateTime(2026, 6, 10), 'worked',
        createdAt: DateTime(2026, 6, 10));
    // Ödemeden sonra girilen gün:
    await addDay(DateTime(2026, 6, 27), 'worked',
        createdAt: DateTime(2026, 6, 27, 14, 22));

    final asPaid = await payroll.calculate(
      worker: await worker(),
      periodStart: periodStart,
      periodEnd: periodEnd,
      asOf: payAt,
    );
    expect(asPaid.workedDayEquivalent, 3);
    expect(asPaid.attendanceDays.length, 3);

    // asOf'suz (bugünkü) hesap 4 gün görür — fark ödemeden sonra girilen gün.
    final liveAll = await payroll.calculate(
      worker: await worker(),
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    expect(liveAll.workedDayEquivalent, 4);
  });
}
