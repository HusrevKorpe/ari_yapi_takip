import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:ari_yapi_takip/data/local/app_database.dart';
import 'package:ari_yapi_takip/data/local/repositories/advance_debt_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/attendance_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/payment_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/payroll_repository.dart';
import 'package:ari_yapi_takip/data/sync/sync_context.dart';

void main() {
  late AppDatabase db;
  late PayrollRepository payroll;
  late PaymentRepository payments;

  const ctx = SyncContext(
    userId: 'u1',
    deviceId: 'd1',
    organizationId: 'org1',
  );

  // Osman vakasıyla aynı kurgu: 2.500 yevmiye, 200 primli şantiye.
  final day1 = DateTime(2026, 6, 1);
  final day2 = DateTime(2026, 6, 2);
  final day3 = DateTime(2026, 6, 3);
  final payDay = DateTime(2026, 6, 4); // ödeme günü (dönem bitişi)
  final day5 = DateTime(2026, 6, 5); // yeni açık dönem

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    final uuid = const Uuid();
    payroll = PayrollRepository(
      database: db,
      attendanceRepository: AttendanceRepository(db, uuid, ctx),
      advanceDebtRepository: AdvanceDebtRepository(db, uuid, ctx),
      uuid: uuid,
      syncContext: ctx,
    );
    payments = PaymentRepository(db, uuid, ctx);

    await db.into(db.workers).insert(
          WorkersCompanion.insert(
            id: 'w1',
            fullName: 'Test İşçi',
            dailyWage: 2500,
            receivesBonus: const Value(true),
          ),
        );
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 's1',
            name: 'Primli Şantiye',
            code: 'PS',
            dailyBonus: const Value(200),
          ),
        );
  });
  tearDown(() => db.close());

  Future<Worker> worker() =>
      (db.select(db.workers)..where((w) => w.id.equals('w1'))).getSingle();

  Future<void> addAttendance(
    DateTime date,
    String status, {
    String? siteId = 's1',
  }) {
    return db.into(db.attendanceEntries).insert(
          AttendanceEntriesCompanion.insert(
            id: 'att-${date.day}-$status',
            workerId: 'w1',
            workDate: date,
            status: status,
            siteId: Value(siteId),
          ),
        );
  }

  /// 1–3 Haziran tam gün çalışılır (3 × 2.700 = 8.100), 4 Haziran sabahı
  /// tamamı ödenir; dönem bitişi ödeme günü (4 Haziran) olarak damgalanır.
  Future<void> seedPaidPeriod() async {
    await addAttendance(day1, 'worked');
    await addAttendance(day2, 'worked');
    await addAttendance(day3, 'worked');
    await payments.recordPayment(
      workerId: 'w1',
      periodStart: day1,
      periodEnd: payDay,
      amount: 8100,
    );
  }

  group('devreden bakiye (carryOver)', () {
    test(
        'ödenmiş döneme sonradan girilen puantaj yeni dönemde '
        'devreden alacak olarak görünür', () async {
      await seedPaidPeriod();
      // Ödeme yapıldıktan sonra o günün puantajı girilir (2.500 + 200 prim).
      await addAttendance(payDay, 'worked');
      // Yeni dönemde primsiz yarım gün (1.250).
      await addAttendance(day5, 'half_day', siteId: null);

      final result = await payroll.calculate(
        worker: await worker(),
        periodStart: day5,
        periodEnd: day5,
        includeCarryOver: true,
      );

      expect(result.gross, 1250); // dönem: yalnızca 5 Haziran
      expect(result.carryOver, 2700); // ödenmiş döneme giren 4 Haziran
      expect(result.net, 3950); // gerçek alacak
    });

    test('geçmiş dönem dökümü (includeCarryOver=false) etkilenmez', () async {
      await seedPaidPeriod();
      await addAttendance(payDay, 'worked');
      await addAttendance(day5, 'half_day', siteId: null);

      final result = await payroll.calculate(
        worker: await worker(),
        periodStart: day5,
        periodEnd: day5,
      );

      expect(result.carryOver, 0);
      expect(result.net, 1250);
    });

    test('tam ödenmiş ve retro kayıt yoksa devreden sıfırdır', () async {
      await seedPaidPeriod();
      await addAttendance(day5, 'half_day', siteId: null);

      final result = await payroll.calculate(
        worker: await worker(),
        periodStart: day5,
        periodEnd: day5,
        includeCarryOver: true,
      );

      expect(result.carryOver, 0);
      expect(result.net, 1250);
    });

    test('ödenmiş döneme sonradan girilen avans devredeni azaltır', () async {
      await seedPaidPeriod();
      await addAttendance(payDay, 'worked'); // +2.700 devreden
      await addAttendance(day5, 'half_day', siteId: null);
      // Ödeme sonrası, ödenmiş dönem tarihine avans işlenir.
      await db.into(db.advanceDebts).insert(
            AdvanceDebtsCompanion.insert(
              id: 'adv-1',
              workerId: 'w1',
              eventDate: day2,
              type: 'advance',
              amount: 500,
              settledMonth: '2026-06',
            ),
          );

      final result = await payroll.calculate(
        worker: await worker(),
        periodStart: day5,
        periodEnd: day5,
        includeCarryOver: true,
      );

      expect(result.carryOver, 2200); // 2.700 − 500
      expect(result.net, 3450);
    });

    test('prim almayan çalışan için devreden prim içermez', () async {
      await (db.update(db.workers)..where((w) => w.id.equals('w1'))).write(
        const WorkersCompanion(receivesBonus: Value(false)),
      );
      await seedPaidPeriod();
      await addAttendance(payDay, 'worked');
      await addAttendance(day5, 'half_day', siteId: null);

      final result = await payroll.calculate(
        worker: await worker(),
        periodStart: day5,
        periodEnd: day5,
        includeCarryOver: true,
      );

      // Yevmiyeler primsiz: geçmiş 3×2500 ödendi (8100 ödendi → 600 fazla
      // ödeme), retro gün 2500. carryOver = (4×2500 + 1250 − 8100) − 1250.
      expect(result.carryOver, 1900);
      expect(result.net, 3150);
    });
  });

  group('carryOnly — açık dönem yokken kalan bakiye', () {
    test('retro kayıt yoksa bakiye 0 (ekran "ödemeler güncel" der)', () async {
      await seedPaidPeriod();

      final result = await payroll.carryOnly(
        worker: await worker(),
        asOf: payDay,
      );

      expect(result.net, 0);
      expect(result.carryOver, 0);
      expect(result.attendanceDays, isEmpty);
    });

    test('ödeme günü sonradan girilen puantaj aynı gün görünür', () async {
      await seedPaidPeriod();
      await addAttendance(payDay, 'worked'); // ödemeden sonra girildi

      final result = await payroll.carryOnly(
        worker: await worker(),
        asOf: payDay,
      );

      expect(result.carryOver, 2700);
      expect(result.net, 2700);
      expect(result.gross, 0);
      expect(result.attendanceDays, isEmpty);
    });
  });
}
