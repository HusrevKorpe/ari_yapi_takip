import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../shared/attendance_status.dart';
import '../../shared/month_utils.dart';
import '../../shared/payroll_calculator.dart';
import 'app_database.dart';

class AttendanceInput {
  const AttendanceInput({
    required this.workerId,
    required this.status,
    this.siteId,
    this.note,
  });

  final String workerId;
  final AttendanceStatus status;
  final String? siteId;
  final String? note;
}

class PayrollResult {
  const PayrollResult({
    required this.worker,
    required this.periodStart,
    required this.periodEnd,
    required this.attendanceDays,
    required this.workedDayEquivalent,
    required this.locationBonus,
    required this.gross,
    required this.deductions,
    required this.net,
  });

  final Worker worker;
  final DateTime periodStart;
  final DateTime periodEnd;
  final List<PayrollAttendanceDay> attendanceDays;
  final double workedDayEquivalent;
  final double locationBonus;
  final double gross;
  final double deductions;
  final double net;
}

class PayrollAttendanceDay {
  const PayrollAttendanceDay({
    required this.date,
    required this.status,
    required this.dayEquivalent,
    required this.dailyAmount,
    this.siteId,
  });

  final DateTime date;
  final AttendanceStatus status;
  final double dayEquivalent;
  final double dailyAmount;
  final String? siteId;
}

class WorkerRepository {
  WorkerRepository(this._db, this._uuid);

  final AppDatabase _db;
  final Uuid _uuid;

  Stream<List<Worker>> watchActiveWorkers() {
    final query = _db.select(_db.workers)
      ..where((w) => w.isActive.equals(true))
      ..orderBy([(w) => OrderingTerm(expression: w.fullName)]);
    return query.watch();
  }

  Future<List<Worker>> getActiveWorkers() {
    final query = _db.select(_db.workers)
      ..where((w) => w.isActive.equals(true))
      ..orderBy([(w) => OrderingTerm(expression: w.fullName)]);
    return query.get();
  }

  Future<void> saveWorker({
    String? id,
    required String fullName,
    required double dailyWage,
    String? defaultSiteId,
    String? notes,
    bool isActive = true,
  }) async {
    final workerId = id ?? _uuid.v4();
    await _db
        .into(_db.workers)
        .insertOnConflictUpdate(
          WorkersCompanion.insert(
            id: workerId,
            fullName: fullName,
            dailyWage: dailyWage,
            defaultSiteId: Value(defaultSiteId),
            notes: Value(notes),
            isActive: Value(isActive),
            updatedAt: Value(DateTime.now()),
          ),
        );

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'worker',
      entityId: workerId,
      action: 'upsert',
      payload: {
        'id': workerId,
        'fullName': fullName,
        'dailyWage': dailyWage,
        'defaultSiteId': defaultSiteId,
        'notes': notes,
        'isActive': isActive,
      },
    );

    await _db.addAudit(
      id: _uuid.v4(),
      entityType: 'worker',
      entityId: workerId,
      message: 'Worker kaydi guncellendi',
    );
  }

  Future<void> deactivateWorker({required String workerId}) async {
    final now = DateTime.now();

    await (_db.update(_db.workers)..where((w) => w.id.equals(workerId))).write(
      WorkersCompanion(isActive: const Value(false), updatedAt: Value(now)),
    );

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'worker',
      entityId: workerId,
      action: 'upsert',
      payload: {
        'id': workerId,
        'isActive': false,
        'updatedAt': now.toIso8601String(),
      },
    );

    await _db.addAudit(
      id: _uuid.v4(),
      entityType: 'worker',
      entityId: workerId,
      message: 'Worker pasife alindi',
    );
  }
}

class SiteRepository {
  SiteRepository(this._db, this._uuid);

  final AppDatabase _db;
  final Uuid _uuid;

  Stream<List<Site>> watchActiveSites() {
    final query = _db.select(_db.sites)
      ..where((s) => s.isActive.equals(true))
      ..orderBy([(s) => OrderingTerm(expression: s.name)]);
    return query.watch();
  }

  Future<void> createSite({
    required String name,
    required String code,
    double dailyBonus = 0,
  }) async {
    final id = _uuid.v4();
    await _db
        .into(_db.sites)
        .insert(
          SitesCompanion.insert(
            id: id,
            name: name,
            code: code,
            dailyBonus: Value(dailyBonus),
          ),
        );

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'site',
      entityId: id,
      action: 'create',
      payload: {'id': id, 'name': name, 'code': code, 'dailyBonus': dailyBonus},
    );
  }

  Future<void> updateSiteBonus({
    required String siteId,
    required double dailyBonus,
  }) async {
    await (_db.update(_db.sites)..where((s) => s.id.equals(siteId))).write(
      SitesCompanion(dailyBonus: Value(dailyBonus)),
    );

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'site',
      entityId: siteId,
      action: 'upsert',
      payload: {'id': siteId, 'dailyBonus': dailyBonus},
    );
  }

  Future<void> deactivateSite({required String siteId}) async {
    await (_db.update(_db.sites)..where((s) => s.id.equals(siteId))).write(
      const SitesCompanion(isActive: Value(false)),
    );

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'site',
      entityId: siteId,
      action: 'upsert',
      payload: {'id': siteId, 'isActive': false},
    );
  }
}

class AttendanceRepository {
  AttendanceRepository(this._db, this._uuid);

  final AppDatabase _db;
  final Uuid _uuid;

  Stream<List<AttendanceEntry>> watchByDate(DateTime date) {
    final normalized = normalizeDay(date);
    final query = _db.select(_db.attendanceEntries)
      ..where((a) => a.workDate.equals(normalized))
      ..orderBy([(a) => OrderingTerm(expression: a.workerId)]);
    return query.watch();
  }

  Future<void> saveDailyAttendance({
    required DateTime date,
    required List<AttendanceInput> entries,
  }) async {
    final normalized = normalizeDay(date);
    await _db.transaction(() async {
      for (final entry in entries) {
        if (entry.status.requiresSite &&
            (entry.siteId == null || entry.siteId!.isEmpty)) {
          throw ArgumentError(
            'Calisti ve Yarim Gun durumunda santiye secimi zorunludur.',
          );
        }

        final id = _uuid.v4();
        await _db
            .into(_db.attendanceEntries)
            .insert(
              AttendanceEntriesCompanion.insert(
                id: id,
                workerId: entry.workerId,
                workDate: normalized,
                status: entry.status.code,
                siteId: Value(entry.siteId),
                note: Value(entry.note),
                updatedAt: Value(DateTime.now()),
              ),
              onConflict: DoUpdate(
                (_) => AttendanceEntriesCompanion(
                  status: Value(entry.status.code),
                  siteId: Value(entry.siteId),
                  note: Value(entry.note),
                  updatedAt: Value(DateTime.now()),
                ),
                target: [
                  _db.attendanceEntries.workerId,
                  _db.attendanceEntries.workDate,
                ],
              ),
            );

        await _db.upsertQueueItem(
          id: _uuid.v4(),
          entityType: 'attendance',
          entityId: '${entry.workerId}-${normalized.toIso8601String()}',
          action: 'upsert',
          payload: {
            'workerId': entry.workerId,
            'workDate': normalized.toIso8601String(),
            'status': entry.status.code,
            'siteId': entry.siteId,
            'note': entry.note,
          },
        );
      }

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'attendance',
        entityId: normalized.toIso8601String(),
        message: '${entries.length} adet yoklama kaydi alindi',
      );
    });
  }

  Future<double> rangeLocationBonus({
    required String workerId,
    required DateTime start,
    required DateTime end,
  }) async {
    final entries =
        await (_db.select(_db.attendanceEntries)..where(
              (a) =>
                  a.workerId.equals(workerId) &
                  a.workDate.isBetweenValues(start, end),
            ))
            .get();

    if (entries.isEmpty) return 0;

    final siteIds = entries
        .where((e) => e.siteId != null)
        .map((e) => e.siteId!)
        .toSet()
        .toList();

    if (siteIds.isEmpty) return 0;

    final sites = await (_db.select(
      _db.sites,
    )..where((s) => s.id.isIn(siteIds))).get();

    final bonusBySiteId = {for (final s in sites) s.id: s.dailyBonus};

    double total = 0;
    for (final entry in entries) {
      final status = AttendanceStatusX.fromCode(entry.status);
      if (!status.requiresSite || entry.siteId == null) continue;
      final bonus = bonusBySiteId[entry.siteId] ?? 0;
      if (bonus <= 0) continue;
      final equivalent = status == AttendanceStatus.halfDay ? 0.5 : 1.0;
      total += bonus * equivalent;
    }

    return total;
  }

  Future<List<AttendanceEntry>> workerEntriesInRange({
    required String workerId,
    required DateTime start,
    required DateTime end,
  }) {
    final query = _db.select(_db.attendanceEntries)
      ..where(
        (a) =>
            a.workerId.equals(workerId) &
            a.workDate.isBetweenValues(start, end),
      )
      ..orderBy([(a) => OrderingTerm(expression: a.workDate)]);
    return query.get();
  }
}

class ExpenseRepository {
  ExpenseRepository(this._db, this._uuid);

  final AppDatabase _db;
  final Uuid _uuid;

  Stream<List<Expense>> watchMonth(DateTime month) {
    final start = monthStart(month);
    final end = monthEnd(month);

    final query = _db.select(_db.expenses)
      ..where((e) => e.expenseDate.isBetweenValues(start, end))
      ..orderBy([(e) => OrderingTerm.desc(e.expenseDate)]);
    return query.watch();
  }

  Future<void> addExpense({
    required DateTime date,
    required double amount,
    required String category,
    String? siteId,
    String? description,
  }) async {
    final id = _uuid.v4();
    final normalized = normalizeDay(date);

    await _db
        .into(_db.expenses)
        .insert(
          ExpensesCompanion.insert(
            id: id,
            expenseDate: normalized,
            amount: amount,
            category: category,
            siteId: Value(siteId),
            description: Value(description),
          ),
        );

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'expense',
      entityId: id,
      action: 'create',
      payload: {
        'id': id,
        'expenseDate': normalized.toIso8601String(),
        'amount': amount,
        'category': category,
        'siteId': siteId,
        'description': description,
      },
    );
  }

  Future<void> deleteExpense({required String expenseId}) async {
    await (_db.delete(_db.expenses)..where((e) => e.id.equals(expenseId))).go();

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'expense',
      entityId: expenseId,
      action: 'delete',
      payload: {'id': expenseId},
    );

    await _db.addAudit(
      id: _uuid.v4(),
      entityType: 'expense',
      entityId: expenseId,
      message: 'Gider kaydi silindi',
    );
  }

  Future<double> totalForMonth(DateTime month) async {
    final start = monthStart(month);
    final end = monthEnd(month);

    final totalExp = _db.expenses.amount.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([totalExp])
      ..where(_db.expenses.expenseDate.isBetweenValues(start, end));

    final row = await query.getSingle();
    return row.read(totalExp) ?? 0;
  }
}

class AdvanceDebtRepository {
  AdvanceDebtRepository(this._db, this._uuid);

  final AppDatabase _db;
  final Uuid _uuid;

  Future<void> add({
    required String workerId,
    required DateTime date,
    required String type,
    required double amount,
    String? note,
  }) async {
    final id = _uuid.v4();
    final month = monthKey(date);

    await _db
        .into(_db.advanceDebts)
        .insert(
          AdvanceDebtsCompanion.insert(
            id: id,
            workerId: workerId,
            eventDate: normalizeDay(date),
            type: type,
            amount: amount,
            note: Value(note),
            settledMonth: month,
          ),
        );

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'advance_debt',
      entityId: id,
      action: 'create',
      payload: {
        'id': id,
        'workerId': workerId,
        'eventDate': date.toIso8601String(),
        'type': type,
        'amount': amount,
        'note': note,
        'settledMonth': month,
      },
    );
  }

  Future<double> totalDeductions({
    required String workerId,
    required DateTime start,
    required DateTime end,
  }) async {
    final totalExp = _db.advanceDebts.amount.sum();
    final query = _db.selectOnly(_db.advanceDebts)
      ..addColumns([totalExp])
      ..where(
        _db.advanceDebts.workerId.equals(workerId) &
            _db.advanceDebts.eventDate.isBetweenValues(start, end),
      );

    final row = await query.getSingle();
    return row.read(totalExp) ?? 0;
  }
}

class PayrollRepository {
  PayrollRepository({
    required AppDatabase database,
    required AttendanceRepository attendanceRepository,
    required AdvanceDebtRepository advanceDebtRepository,
    required Uuid uuid,
  }) : _db = database,
       _attendanceRepository = attendanceRepository,
       _advanceDebtRepository = advanceDebtRepository,
       _uuid = uuid;

  final AppDatabase _db;
  final AttendanceRepository _attendanceRepository;
  final AdvanceDebtRepository _advanceDebtRepository;
  final Uuid _uuid;

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

    final calculation = PayrollCalculator.calculate(
      workedDayEquivalent: worked,
      dailyWage: worker.dailyWage,
      deductions: deductions,
      locationBonus: locationBonus,
    );
    final attendanceDays = parsedEntries
        .map((p) {
          final dayEquivalent = PayrollCalculator.workedEquivalent([p.status]);
          if (dayEquivalent <= 0) return null;

          return PayrollAttendanceDay(
            date: p.entry.workDate,
            status: p.status,
            dayEquivalent: dayEquivalent,
            dailyAmount: worker.dailyWage * dayEquivalent,
            siteId: p.entry.siteId,
          );
        })
        .whereType<PayrollAttendanceDay>()
        .toList();

    final periodKey = _periodKey(start, end);

    await _db
        .into(_db.payrollSnapshots)
        .insert(
          PayrollSnapshotsCompanion.insert(
            id: _uuid.v4(),
            workerId: worker.id,
            month: periodKey,
            workedDayEquivalent: calculation.workedDayEquivalent,
            gross: calculation.gross,
            deductions: calculation.deductions,
            net: calculation.net,
          ),
          onConflict: DoUpdate(
            (_) => PayrollSnapshotsCompanion(
              workedDayEquivalent: Value(calculation.workedDayEquivalent),
              gross: Value(calculation.gross),
              deductions: Value(calculation.deductions),
              net: Value(calculation.net),
            ),
            target: [_db.payrollSnapshots.workerId, _db.payrollSnapshots.month],
          ),
        );

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'payroll_snapshot',
      entityId: '${worker.id}-$periodKey',
      action: 'upsert',
      payload: {
        'workerId': worker.id,
        'month': periodKey,
        'workedDayEquivalent': calculation.workedDayEquivalent,
        'gross': calculation.gross,
        'deductions': calculation.deductions,
        'net': calculation.net,
      },
    );

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

  String _periodKey(DateTime start, DateTime end) {
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    return '${fmt(start)}_${fmt(end)}';
  }
}

class PaymentRepository {
  PaymentRepository(this._db, this._uuid);

  final AppDatabase _db;
  final Uuid _uuid;

  Future<void> recordPayment({
    required String workerId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double amount,
  }) async {
    final id = _uuid.v4();
    await _db
        .into(_db.payrollPayments)
        .insert(
          PayrollPaymentsCompanion.insert(
            id: id,
            workerId: workerId,
            periodStart: periodStart,
            periodEnd: periodEnd,
            amount: amount,
            paidAt: DateTime.now(),
          ),
        );

    await _db.upsertQueueItem(
      id: _uuid.v4(),
      entityType: 'payroll_payment',
      entityId: id,
      action: 'create',
      payload: {
        'id': id,
        'workerId': workerId,
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'amount': amount,
      },
    );
  }

  Future<DateTime?> lastPaymentEnd(String workerId) async {
    final query = _db.select(_db.payrollPayments)
      ..where((p) => p.workerId.equals(workerId))
      ..orderBy([(p) => OrderingTerm.desc(p.periodEnd)])
      ..limit(1);
    final results = await query.get();
    return results.isEmpty ? null : results.first.periodEnd;
  }
}

class SyncQueueRepository {
  SyncQueueRepository(this._db);

  final AppDatabase _db;

  Stream<int> pendingCount() {
    final countExp = _db.syncQueueItems.id.count();
    final query = _db.selectOnly(_db.syncQueueItems)
      ..addColumns([countExp])
      ..where(_db.syncQueueItems.status.equals('pending'));

    return query.watchSingle().map((row) => row.read(countExp) ?? 0);
  }

  Future<List<SyncQueueItem>> pendingItems() {
    final query = _db.select(_db.syncQueueItems)
      ..where((q) => q.status.equals('pending'))
      ..orderBy([(q) => OrderingTerm(expression: q.createdAt)]);
    return query.get();
  }

  Future<void> markSynced(String id) {
    return (_db.update(
      _db.syncQueueItems,
    )..where((q) => q.id.equals(id))).write(
      SyncQueueItemsCompanion(
        status: const Value('done'),
        processedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> markFailed(String id, {required int retryCount}) {
    return (_db.update(
      _db.syncQueueItems,
    )..where((q) => q.id.equals(id))).write(
      SyncQueueItemsCompanion(
        status: const Value('pending'),
        retryCount: Value(retryCount),
      ),
    );
  }

  Map<String, dynamic> decodePayload(String payload) {
    try {
      return jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }
}
