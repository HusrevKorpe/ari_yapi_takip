import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/attendance_status.dart';
import '../../../shared/bonus_history.dart';
import '../../../shared/month_utils.dart';
import '../../../shared/payroll_calculator.dart';
import '../../../shared/wage_history.dart';
import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';
import 'advance_debt_repository.dart';
import 'attendance_repository.dart';
import 'dtos.dart';

class PayrollRepository {
  PayrollRepository({
    required AppDatabase database,
    required AttendanceRepository attendanceRepository,
    required AdvanceDebtRepository advanceDebtRepository,
    required Uuid uuid,
    required SyncContext syncContext,
  }) : _db = database,
       _attendanceRepository = attendanceRepository,
       _advanceDebtRepository = advanceDebtRepository,
       _uuid = uuid,
       _ctx = syncContext;

  final AppDatabase _db;
  final AttendanceRepository _attendanceRepository;
  final AdvanceDebtRepository _advanceDebtRepository;
  final Uuid _uuid;
  final SyncContext _ctx;

  /// [includeCarryOver] true ise, ödenmiş dönemlere sonradan girilen
  /// puantaj/avans kayıtlarından doğan fark (devreden bakiye) hesaba
  /// katılır ve `net` tüm geçmişin gerçek pozisyonunu gösterir. Geçmiş bir
  /// ödemenin dönem dökümünü yeniden üretirken false kalmalıdır.
  /// [asOf] verilirse yalnızca o ana kadar GİRİLMİŞ (createdAt ≤ asOf) puantaj
  /// kayıtları hesaba katılır. Geçmiş bir ödemenin dönem dökümünü, ödeme
  /// anındaki haliyle yeniden kurmak için kullanılır (ödemeden sonra girilen
  /// günler listeye sızıp donmuş "çalışılan gün" sayısıyla çelişmesin diye).
  Future<PayrollResult> calculate({
    required Worker worker,
    required DateTime periodStart,
    required DateTime periodEnd,
    bool includeCarryOver = false,
    DateTime? asOf,
  }) async {
    final start = normalizeDay(periodStart);
    final end = DateTime(
      periodEnd.year,
      periodEnd.month,
      periodEnd.day,
      23,
      59,
      59,
    );
    final attendanceEntries = await _attendanceRepository.workerEntriesInRange(
      workerId: worker.id,
      start: start,
      end: end,
      createdUpTo: asOf,
    );

    final parsedEntries = attendanceEntries
        .map((e) => (entry: e, status: AttendanceStatusX.fromCode(e.status)))
        .toList();

    final worked = PayrollCalculator.workedEquivalent(
      parsedEntries.map((p) => p.status),
    );
    final deductions = await _advanceDebtRepository.totalDeductions(
      workerId: worker.id,
      start: start,
      end: end,
    );
    final rawLocationBonus = await _attendanceRepository.rangeLocationBonus(
      workerId: worker.id,
      start: start,
      end: end,
    );
    // Prim almayan personel için tüm prim hesaplamaları sıfırlanır;
    // geçmiş aylar dahil tutar 0 gelir.
    final locationBonus = worker.receivesBonus ? rawLocationBonus : 0.0;

    final siteIds = <String>{
      for (final e in attendanceEntries) ...[
        if (e.siteId != null) e.siteId!,
        if (e.secondSiteId != null) e.secondSiteId!,
      ],
    }.toList();
    // Tarih bazlı prim: her günü, o gün geçerli olan primle fiyatlayabilmek
    // için şantiyeleri (prim geçmişiyle) tutuyoruz. Geçmiş boşsa güncel prim
    // kullanılır — prim değişikliği yalnızca ileriye dönük etki eder.
    final Map<String, Site> siteById;
    if (worker.receivesBonus && siteIds.isNotEmpty) {
      final sites = await (_db.select(_db.sites)
            ..where((s) => s.id.isIn(siteIds)))
          .get();
      siteById = {for (final s in sites) s.id: s};
    } else {
      siteById = {};
    }

    // Tarih bazlı yevmiye: her gün, o gün geçerli olan yevmiyeyle fiyatlanır.
    // Geçmiş boşsa (hiç zam yok) tüm günler güncel yevmiyeyi alır — eski
    // davranış. Zam yalnızca ileriye dönük etki eder.
    final wages = WageHistory.decode(worker.wageHistory);
    double wageForDate(DateTime d) => wages.wageForDate(d, worker.dailyWage);

    final attendanceDays = parsedEntries.map((p) {
      final dayEquivalent = PayrollCalculator.workedEquivalent([p.status]);
      double dayBonus = 0;
      if (worker.receivesBonus &&
          p.status.requiresSite &&
          p.entry.siteId != null) {
        final site = siteById[p.entry.siteId];
        if (site != null) {
          final bonus = BonusHistory.decode(site.bonusHistory)
              .bonusForDate(p.entry.workDate, site.dailyBonus);
          if (bonus > 0) {
            dayBonus = bonus * dayEquivalent;
          }
        }
      }

      return PayrollAttendanceDay(
        date: p.entry.workDate,
        status: p.status,
        dayEquivalent: dayEquivalent,
        dailyAmount: wageForDate(p.entry.workDate) * dayEquivalent,
        siteId: p.entry.siteId,
        siteBonus: dayBonus,
      );
    }).toList();

    final wageGross =
        attendanceDays.fold<double>(0, (sum, d) => sum + d.dailyAmount);
    final gross = wageGross + locationBonus;
    final net = gross - deductions;

    double carryOver = 0;
    if (includeCarryOver) {
      final lifetimeNet = await _lifetimeNet(worker);
      carryOver = lifetimeNet - net;
      // Kayan nokta artıklarını bakiye sanmayalım.
      if (carryOver.abs() < 0.005) carryOver = 0;
    }

    return PayrollResult(
      worker: worker,
      periodStart: start,
      periodEnd: normalizeDay(periodEnd),
      attendanceDays: attendanceDays,
      workedDayEquivalent: worked,
      locationBonus: locationBonus,
      gross: gross,
      deductions: deductions,
      carryOver: carryOver,
      net: net + carryOver,
    );
  }

  /// Açık dönem yokken (son ödeme bugünü de kapatıyorken) kalan bakiyeyi
  /// gösteren sonuç: dönem hesabı boş, net = tüm geçmişin pozisyonu.
  /// Ödeme sabah yapılıp o günün puantajı sonradan girildiğinde bakiye
  /// ertesi günü beklemeden burada görünür.
  Future<PayrollResult> carryOnly({
    required Worker worker,
    required DateTime asOf,
  }) async {
    final day = normalizeDay(asOf);
    var lifetimeNet = await _lifetimeNet(worker);
    if (lifetimeNet.abs() < 0.005) lifetimeNet = 0;
    return PayrollResult(
      worker: worker,
      periodStart: day,
      periodEnd: day,
      attendanceDays: const [],
      workedDayEquivalent: 0,
      locationBonus: 0,
      gross: 0,
      deductions: 0,
      carryOver: lifetimeNet,
      net: lifetimeNet,
    );
  }

  /// Tüm geçmişin net pozisyonu — workerLifetimeStatsProvider ile aynı
  /// formül: (tarih bazlı yevmiye toplamı) + prim − avans − ödenen.
  Future<double> _lifetimeNet(Worker worker) async {
    // Tarih bazlı yevmiye: geçmişteki her gün kendi günündeki yevmiyeyle
    // toplanır ki zam ödenmiş/kapanmış dönemleri yeniden fiyatlamasın.
    final wages = WageHistory.decode(worker.wageHistory);
    final wageGross = await _attendanceRepository.lifetimeWageGross(
      worker.id,
      (d) => wages.wageForDate(d, worker.dailyWage),
    );
    final bonus = worker.receivesBonus
        ? await _attendanceRepository.totalLocationBonus(worker.id)
        : 0.0;
    final advances = await _advanceDebtRepository.totalAdvances(worker.id);
    final payments = await (_db.select(_db.payrollPayments)
          ..where(
            (p) => p.workerId.equals(worker.id) & p.deletedAt.isNull(),
          ))
        .get();
    final paid = payments.fold<double>(0, (sum, p) => sum + p.amount);

    return wageGross + bonus - advances - paid;
  }

  /// Snapshot'ı tek başına (kendi transaction'ında) dondurur.
  Future<void> saveSnapshot(PayrollResult result) => writeSnapshot(result);

  /// Ödeme kaydıyla aynı transaction içinden de çağrılabilen dondurma. Bir
  /// transaction içinde çağrıldığında Drift savepoint kullanır; böylece donmuş
  /// döküm ile ödeme tek atomik birim olur ([PaymentRepository.recordPayment])
  /// ve reddedilen bir çift ödeme mevcut snapshot'ı bozamaz.
  Future<void> writeSnapshot(PayrollResult result) async {
    final periodKey = _periodKey(result.periodStart, result.periodEnd);
    final now = DateTime.now();
    final daysJson = jsonEncode(
      result.attendanceDays.map(_dayToJson).toList(),
    );

    await _db.transaction(() async {
      final existing = await (_db.select(_db.payrollSnapshots)
            ..where(
              (s) =>
                  s.workerId.equals(result.worker.id) &
                  s.month.equals(periodKey),
            ))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await _db.into(_db.payrollSnapshots).insert(
        PayrollSnapshotsCompanion.insert(
          id: existing?.id ?? _uuid.v4(),
          workerId: result.worker.id,
          month: periodKey,
          workedDayEquivalent: result.workedDayEquivalent,
          gross: result.gross,
          deductions: result.deductions,
          net: result.net,
          attendanceDaysJson: Value(daysJson),
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
        onConflict: DoUpdate(
          (_) => PayrollSnapshotsCompanion(
            workedDayEquivalent: Value(result.workedDayEquivalent),
            gross: Value(result.gross),
            deductions: Value(result.deductions),
            net: Value(result.net),
            attendanceDaysJson: Value(daysJson),
            updatedAt: Value(now),
            lastModifiedBy: Value(_ctx.userId),
            deviceId: Value(_ctx.deviceId),
            syncVersion: Value(nextVersion),
          ),
          target: [_db.payrollSnapshots.workerId, _db.payrollSnapshots.month],
        ),
      );

      final snapshot = await (_db.select(_db.payrollSnapshots)
            ..where(
              (s) =>
                  s.workerId.equals(result.worker.id) &
                  s.month.equals(periodKey),
            ))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'payroll_snapshot',
        entityId: snapshot.id,
        action: 'upsert',
        payload: snapshot.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<PayrollSnapshot?> getSnapshot({
    required String workerId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final key = _periodKey(periodStart, periodEnd);
    final query = _db.select(_db.payrollSnapshots)
      ..where(
        (s) =>
            s.workerId.equals(workerId) &
            s.month.equals(key) &
            s.deletedAt.isNull(),
      );
    final results = await query.get();
    return results.isEmpty ? null : results.first;
  }

  /// Snapshot anında dondurulmuş günlük detayı döner. Snapshot yoksa veya
  /// v13 öncesi yazıldığı için days alanı boşsa null döner — çağıran taraf
  /// gerekirse `calculate()` ile canlı hesaplamaya geri düşebilir.
  Future<List<PayrollAttendanceDay>?> getSnapshotDays({
    required String workerId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final snapshot = await getSnapshot(
      workerId: workerId,
      periodStart: periodStart,
      periodEnd: periodEnd,
    );
    final raw = snapshot?.attendanceDaysJson;
    if (raw == null || raw.isEmpty) return null;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => _dayFromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Bozuk JSON: snapshot var ama parse edilemiyor — fallback olarak null
      // dönüp canlı hesaplamaya izin ver, sessiz veri kaybı yapma.
      return null;
    }
  }

  String _periodKey(DateTime start, DateTime end) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(start)}_${fmt(end)}';
  }

  static Map<String, dynamic> _dayToJson(PayrollAttendanceDay d) => {
        'date': d.date.toIso8601String(),
        'status': d.status.code,
        'dayEquivalent': d.dayEquivalent,
        'dailyAmount': d.dailyAmount,
        'siteId': d.siteId,
        'siteBonus': d.siteBonus,
      };

  static PayrollAttendanceDay _dayFromJson(Map<String, dynamic> m) =>
      PayrollAttendanceDay(
        date: DateTime.parse(m['date'] as String),
        status: AttendanceStatusX.fromCode(m['status'] as String),
        dayEquivalent: (m['dayEquivalent'] as num).toDouble(),
        dailyAmount: (m['dailyAmount'] as num).toDouble(),
        siteId: m['siteId'] as String?,
        siteBonus: (m['siteBonus'] as num?)?.toDouble() ?? 0,
      );
}
