import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

import 'package:ari_yapi_takip/data/local/app_database.dart';
import 'package:ari_yapi_takip/data/local/repositories/advance_debt_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/attendance_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/payment_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/payroll_repository.dart';
import 'package:ari_yapi_takip/data/local/repositories/site_repository.dart';
import 'package:ari_yapi_takip/data/sync/sync_context.dart';

/// Tarih bazlı prim: şantiye primi değişikliği yalnızca ileriye dönük
/// uygulanmalı, geçmiş (özellikle ödenmiş/kapanmış) dönemler yeniden
/// fiyatlanmamalı. Yevmiyedeki wage_change_retro_test'in prim karşılığı.
void main() {
  late AppDatabase db;
  late PayrollRepository payroll;
  late PaymentRepository payments;
  late SiteRepository sites;

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
    sites = SiteRepository(db, uuid, ctx);

    // Yevmiye 0 → hesap yalnızca primden oluşsun (primi izole ediyoruz).
    await db.into(db.workers).insert(
          WorkersCompanion.insert(
            id: 'w1',
            fullName: 'Prim Alan İşçi',
            dailyWage: 0,
            receivesBonus: const Value(true),
          ),
        );
    // Şantiye primi (değişiklik ÖNCESİ) = 200.
    await db.into(db.sites).insert(
          SitesCompanion.insert(
            id: 's1',
            name: 'İlçe Şantiyesi',
            code: 'ILCE',
            dailyBonus: const Value(200),
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
              siteId: const Value('s1'),
            ),
          );

  /// Primi gerçek yol üzerinden (SiteRepository.updateSiteBonus) değiştirir;
  /// böylece tarih bazlı prim geçmişi kaydedilir.
  Future<void> raiseBonusTo(double newBonus, DateTime effectiveFrom) =>
      sites.updateSiteBonus(
        siteId: 's1',
        dailyBonus: newBonus,
        effectiveFrom: effectiveFrom,
      );

  test('prim artışı sonrası kapanmış dönem yeniden fiyatlanmamalı', () async {
    // 1-2 Haziran, günlük 200 primle çalışıldı = 400
    await addAttendance(day1);
    await addAttendance(day2);

    // Tamamı ödendi → hesap kapandı, bakiye sıfır olmalı.
    await payments.recordPayment(
      workerId: 'w1',
      periodStart: day1,
      periodEnd: payDay,
      amount: 400,
    );

    final beforeRaise = await payroll.carryOnly(
      worker: await worker(),
      asOf: payDay,
    );
    expect(beforeRaise.net, 0, reason: 'prim artışı öncesi hesap kapalı');

    // Prim 200 → 300, 4 Haziran'dan geçerli.
    await raiseBonusTo(300, DateTime(2026, 6, 4));

    final afterRaise = await payroll.carryOnly(
      worker: await worker(),
      asOf: payDay,
    );

    // Ödenmiş ve kapanmış geçmiş dönem (1-2 Haz) prim artışından ETKİLENMEMELİ.
    expect(
      afterRaise.net,
      0,
      reason: 'prim artışı yalnızca ileriye dönük olmalı; '
          'kapanmış dönem yeniden fiyatlanmamalı',
    );
  });

  test('prim tarihinden ÖNCEKİ gün eski, SONRAKİ gün yeni primle', () async {
    // 1 Haz (eski) ve 5 Haz (yeni) çalışıldı; henüz ödeme yok.
    final jun1 = DateTime(2026, 6, 1);
    final jun5 = DateTime(2026, 6, 5);
    await addAttendance(jun1);
    await addAttendance(jun5);

    // 3 Haziran'dan itibaren 200 → 300 prim.
    await raiseBonusTo(300, DateTime(2026, 6, 3));

    final result = await payroll.calculate(
      worker: await worker(),
      periodStart: jun1,
      periodEnd: jun5,
      includeCarryOver: true,
    );

    // 1 Haz → 200, 5 Haz → 300. Toplam prim = 500.
    expect(result.net, 500, reason: '1 Haz eski, 5 Haz yeni primle');
  });

  test('günlük kırılımdaki prim de tarih bazlı olmalı', () async {
    final jun1 = DateTime(2026, 6, 1);
    final jun5 = DateTime(2026, 6, 5);
    await addAttendance(jun1);
    await addAttendance(jun5);
    await raiseBonusTo(300, DateTime(2026, 6, 3));

    final result = await payroll.calculate(
      worker: await worker(),
      periodStart: jun1,
      periodEnd: jun5,
      includeCarryOver: true,
    );

    final byDate = {
      for (final d in result.attendanceDays) d.date.day: d.siteBonus,
    };
    expect(byDate[1], 200, reason: '1 Haz kırılımı eski primle');
    expect(byDate[5], 300, reason: '5 Haz kırılımı yeni primle');
  });

  test('hiç değişmemişse davranış aynı (güncel prim)', () async {
    await addAttendance(day1);
    await addAttendance(day2);

    final result = await payroll.calculate(
      worker: await worker(),
      periodStart: day1,
      periodEnd: payDay,
      includeCarryOver: true,
    );
    // Geçmiş yok → 2 gün × 200 = 400.
    expect(result.net, 400);
  });
}
