import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:ari_yapi_takip/data/local/app_database.dart';
import 'package:ari_yapi_takip/data/local/repositories/advance_debt_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/attendance_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/payment_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/payroll_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/worker_repository.dart';
import 'package:ari_yapi_takip/data/sync/sync_context.dart';

/// Tarih bazlı yevmiye: zam yalnızca ileriye dönük uygulanmalı, geçmiş
/// (özellikle ödenmiş/kapanmış) dönemler yeniden fiyatlanmamalı.
void main() {
  late AppDatabase db;
  late PayrollRepository payroll;
  late PaymentRepository payments;
  late WorkerRepository workers;

  const ctx = SyncContext(userId: 'u1', deviceId: 'd1', organizationId: 'org1');

  final day1 = DateTime(2026, 6, 1);
  final day2 = DateTime(2026, 6, 2);
  final payDay = DateTime(2026, 6, 3);

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
    workers = WorkerRepository(db, uuid, ctx);

    await db.into(db.workers).insert(
          WorkersCompanion.insert(
            id: 'w1',
            fullName: 'Zam Alan İşçi',
            dailyWage: 2000, // zam ÖNCESİ yevmiye
            receivesBonus: const Value(false),
          ),
        );
  });
  tearDown(() => db.close());

  Future<Worker> worker() =>
      (db.select(db.workers)..where((w) => w.id.equals('w1'))).getSingle();

  Future<void> addAttendance(DateTime date) =>
      db.into(db.attendanceEntries).insert(
            AttendanceEntriesCompanion.insert(
              id: 'att-${date.month}-${date.day}',
              workerId: 'w1',
              workDate: date,
              status: 'worked',
              siteId: const Value(null),
            ),
          );

  /// Yevmiyeyi gerçek yol üzerinden (WorkerRepository.saveWorker) değiştirir;
  /// böylece tarih bazlı yevmiye geçmişi kaydedilir.
  Future<void> raiseWageTo(double newWage, DateTime effectiveFrom) async {
    final w = await worker();
    await workers.saveWorker(
      id: w.id,
      fullName: w.fullName,
      dailyWage: newWage,
      receivesBonus: w.receivesBonus,
      wageEffectiveFrom: effectiveFrom,
    );
  }

  test('zam sonrası kapanmış dönem yeniden fiyatlanmamalı', () async {
    // 1-2 Haziran, günlük 2.000'den çalışıldı = 4.000
    await addAttendance(day1);
    await addAttendance(day2);

    // Tamamı ödendi → hesap kapandı, bakiye sıfır olmalı.
    await payments.recordPayment(
      workerId: 'w1',
      periodStart: day1,
      periodEnd: payDay,
      amount: 4000,
    );

    final beforeRaise = await payroll.carryOnly(
      worker: await worker(),
      asOf: payDay,
    );
    expect(beforeRaise.net, 0, reason: 'zam öncesi hesap kapalı');

    // İşveren zam yapıyor: 2.000 → 2.500, 4 Haziran'dan geçerli.
    await raiseWageTo(2500, DateTime(2026, 6, 4));

    final afterRaise = await payroll.carryOnly(
      worker: await worker(),
      asOf: payDay,
    );

    // Ödenmiş ve kapanmış geçmiş dönem (1-2 Haz) zamdan ETKİLENMEMELİ.
    expect(
      afterRaise.net,
      0,
      reason: 'zam yalnızca ileriye dönük olmalı; '
          'kapanmış dönem yeniden fiyatlanmamalı',
    );
  });

  test('zam, çalışanın borçlu olduğu bakiyeyi alacağa çevirmemeli', () async {
    await addAttendance(day1);
    await addAttendance(day2); // 2 gün × 2.000 = 4.000

    // Çalışan 5.000 avans almış → işveren 1.000 ALACAKLI (net = -1.000)
    await db.into(db.advanceDebts).insert(
          AdvanceDebtsCompanion.insert(
            id: 'adv-1',
            workerId: 'w1',
            eventDate: day1,
            type: 'advance',
            amount: 5000,
            settledMonth: '2026-06',
          ),
        );

    final before = await payroll.carryOnly(
      worker: await worker(),
      asOf: payDay,
    );
    expect(before.net, -1000, reason: 'işveren 1.000 alacaklı');

    // Zam: 2.000 → 3.000, 4 Haziran'dan geçerli.
    await raiseWageTo(3000, DateTime(2026, 6, 4));

    final after = await payroll.carryOnly(
      worker: await worker(),
      asOf: payDay,
    );

    // Geçmiş yeniden fiyatlanırsa: 2×3000 − 5000 = +1.000 → yön TERSİNE döner.
    expect(
      after.net,
      -1000,
      reason: 'zam geçmişi değiştirmemeli; işveren hâlâ alacaklı olmalı',
    );
  });

  test('zam tarihinden ÖNCEKİ gün eski, SONRAKİ gün yeni yevmiyeyle', () async {
    // 1 Haz (eski) ve 5 Haz (yeni) çalışıldı; henüz ödeme yok.
    final jun1 = DateTime(2026, 6, 1);
    final jun5 = DateTime(2026, 6, 5);
    await addAttendance(jun1);
    await addAttendance(jun5);

    // 3 Haziran'dan itibaren 2.000 → 2.500 zam.
    await raiseWageTo(2500, DateTime(2026, 6, 3));

    final result = await payroll.calculate(
      worker: await worker(),
      periodStart: jun1,
      periodEnd: jun5,
      includeCarryOver: true,
    );

    // 1 Haz → 2.000, 5 Haz → 2.500. Toplam hak ediş = 4.500.
    expect(result.net, 4500, reason: '1 Haz eski, 5 Haz yeni yevmiyeyle');
  });

  test('hiç zam yapılmamışsa davranış değişmez (güncel yevmiye)', () async {
    await addAttendance(day1);
    await addAttendance(day2);

    final result = await payroll.calculate(
      worker: await worker(),
      periodStart: day1,
      periodEnd: payDay,
      includeCarryOver: true,
    );
    // Geçmiş yok → 2 gün × 2.000 = 4.000.
    expect(result.net, 4000);
  });
}
