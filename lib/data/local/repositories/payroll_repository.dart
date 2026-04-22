import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/attendance_status.dart';
import '../../../shared/month_utils.dart';
import '../../../shared/payroll_calculator.dart';
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

  Future<PayrollResult> calculate({
    required Worker worker,
    required DateTime periodStart,
    required DateTime periodEnd,
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
    final locationBonus = await _attendanceRepository.rangeLocationBonus(
      workerId: worker.id,
      start: start,
      end: end,
    );

    final siteIds = attendanceEntries
        .where((e) => e.siteId != null)
        .map((e) => e.siteId!)
        .toSet()
        .toList();
    final Map<String, double> bonusBySiteId;
    if (siteIds.isNotEmpty) {
      final sites = await (_db.select(_db.sites)
            ..where((s) => s.id.isIn(siteIds)))
          .get();
      bonusBySiteId = {for (final s in sites) s.id: s.dailyBonus};
    } else {
      bonusBySiteId = {};
    }

    final calculation = PayrollCalculator.calculate(
      workedDayEquivalent: worked,
      dailyWage: worker.dailyWage,
      deductions: deductions,
      locationBonus: locationBonus,
    );
    final attendanceDays = parsedEntries.map((p) {
      final dayEquivalent = PayrollCalculator.workedEquivalent([p.status]);
      double dayBonus = 0;
      if (p.status.requiresSite && p.entry.siteId != null) {
        final bonus = bonusBySiteId[p.entry.siteId] ?? 0;
        if (bonus > 0) {
          dayBonus = bonus * dayEquivalent;
        }
      }

      return PayrollAttendanceDay(
        date: p.entry.workDate,
        status: p.status,
        dayEquivalent: dayEquivalent,
        dailyAmount: worker.dailyWage * dayEquivalent,
        siteId: p.entry.siteId,
        siteBonus: dayBonus,
      );
    }).toList();

    return PayrollResult(
      worker: worker,
      periodStart: start,
      periodEnd: normalizeDay(periodEnd),
      attendanceDays: attendanceDays,
      workedDayEquivalent: calculation.workedDayEquivalent,
      locationBonus: calculation.locationBonus,
      gross: calculation.gross,
      deductions: calculation.deductions,
      net: calculation.net,
    );
  }

  Future<void> saveSnapshot(PayrollResult result) async {
    final periodKey = _periodKey(result.periodStart, result.periodEnd);
    final now = DateTime.now();

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

  String _periodKey(DateTime start, DateTime end) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(start)}_${fmt(end)}';
  }
}
