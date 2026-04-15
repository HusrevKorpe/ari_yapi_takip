import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../shared/attendance_status.dart';
import '../../shared/month_utils.dart';
import '../../shared/payroll_calculator.dart';
import '../sync/sync_context.dart';
import '../sync/sync_mappers.dart';
import 'app_database.dart';

// ---------------------------------------------------------------------------
// DTOs
// ---------------------------------------------------------------------------

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
    this.siteBonus = 0,
  });

  final DateTime date;
  final AttendanceStatus status;
  final double dayEquivalent;
  final double dailyAmount;
  final String? siteId;
  final double siteBonus;
}

// ---------------------------------------------------------------------------
// WorkerRepository
// ---------------------------------------------------------------------------

class WorkerRepository {
  WorkerRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<Worker>> watchActiveWorkers() {
    final query = _db.select(_db.workers)
      ..where((w) => w.isActive.equals(true) & w.deletedAt.isNull())
      ..orderBy([(w) => OrderingTerm(expression: w.fullName)]);
    return query.watch();
  }

  Future<List<Worker>> getActiveWorkers() {
    final query = _db.select(_db.workers)
      ..where((w) => w.isActive.equals(true) & w.deletedAt.isNull())
      ..orderBy([(w) => OrderingTerm(expression: w.fullName)]);
    return query.get();
  }

  Future<void> saveWorker({
    String? id,
    required String fullName,
    required double dailyWage,
    String? defaultSiteId,
    String? notes,
    String payFrequency = 'weekly',
    bool isActive = true,
  }) async {
    final workerId = id ?? _uuid.v4();
    final now = DateTime.now();

    await _db.transaction(() async {
      int nextVersion = 1;
      if (id != null) {
        final existing = await (_db.select(_db.workers)
              ..where((w) => w.id.equals(id)))
            .getSingleOrNull();
        if (existing != null) nextVersion = existing.syncVersion + 1;
      }

      await _db.into(_db.workers).insertOnConflictUpdate(
        WorkersCompanion.insert(
          id: workerId,
          fullName: fullName,
          dailyWage: dailyWage,
          defaultSiteId: Value(defaultSiteId),
          payFrequency: Value(payFrequency),
          notes: Value(notes),
          isActive: Value(isActive),
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.workers)
            ..where((w) => w.id.equals(workerId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'worker',
        entityId: workerId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'worker',
        entityId: workerId,
        message: 'Worker kaydi guncellendi',
      );
    });
  }

  Future<void> deactivateWorker({required String workerId}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.workers)
            ..where((w) => w.id.equals(workerId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.workers)..where((w) => w.id.equals(workerId)))
          .write(
        WorkersCompanion(
          isActive: const Value(false),
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.workers)
            ..where((w) => w.id.equals(workerId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'worker',
        entityId: workerId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'worker',
        entityId: workerId,
        message: 'Worker pasife alindi',
      );
    });
  }
}

// ---------------------------------------------------------------------------
// SiteRepository
// ---------------------------------------------------------------------------

class SiteRepository {
  SiteRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<Site>> watchActiveSites() {
    final query = _db.select(_db.sites)
      ..where((s) => s.isActive.equals(true) & s.deletedAt.isNull())
      ..orderBy([(s) => OrderingTerm(expression: s.name)]);
    return query.watch();
  }

  Future<void> createSite({
    required String name,
    required String code,
    double dailyBonus = 0,
  }) async {
    final id = _uuid.v4();
    await _db.transaction(() async {
      await _db.into(_db.sites).insert(
        SitesCompanion.insert(
          id: id,
          name: name,
          code: code,
          dailyBonus: Value(dailyBonus),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'site',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> updateSiteBonus({
    required String siteId,
    required double dailyBonus,
  }) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(siteId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.sites)..where((s) => s.id.equals(siteId))).write(
        SitesCompanion(
          dailyBonus: Value(dailyBonus),
          updatedAt: Value(DateTime.now()),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(siteId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'site',
        entityId: siteId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> deactivateSite({required String siteId}) async {
    await _db.transaction(() async {
      final existing = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(siteId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.sites)..where((s) => s.id.equals(siteId))).write(
        SitesCompanion(
          isActive: const Value(false),
          updatedAt: Value(DateTime.now()),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      final saved = await (_db.select(_db.sites)
            ..where((s) => s.id.equals(siteId)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'site',
        entityId: siteId,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }
}

// ---------------------------------------------------------------------------
// AttendanceRepository
// ---------------------------------------------------------------------------

class AttendanceRepository {
  AttendanceRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<AttendanceEntry>> watchByDate(DateTime date) {
    final normalized = normalizeDay(date);
    final query = _db.select(_db.attendanceEntries)
      ..where((a) => a.workDate.equals(normalized) & a.deletedAt.isNull())
      ..orderBy([(a) => OrderingTerm(expression: a.workerId)]);
    return query.watch();
  }

  Future<void> saveDailyAttendance({
    required DateTime date,
    required List<AttendanceInput> entries,
  }) async {
    final normalized = normalizeDay(date);
    final now = DateTime.now();

    // Mevcut kayıtların syncVersion'larını önceden çek — conflict durumunda
    // DoUpdate içinde doğru versiyonu kullanmak için.
    final existingEntries = await (_db.select(_db.attendanceEntries)
          ..where((a) => a.workDate.equals(normalized) & a.deletedAt.isNull()))
        .get();
    final existingVersions = {
      for (final e in existingEntries) e.workerId: e.syncVersion,
    };

    await _db.transaction(() async {
      for (final entry in entries) {
        if (entry.status.requiresSite &&
            (entry.siteId == null || entry.siteId!.isEmpty)) {
          throw ArgumentError(
            'Calisti ve Yarim Gun durumunda santiye secimi zorunludur.',
          );
        }

        final nextVersion = (existingVersions[entry.workerId] ?? 0) + 1;
        final id = _uuid.v4();
        await _db.into(_db.attendanceEntries).insert(
          AttendanceEntriesCompanion.insert(
            id: id,
            workerId: entry.workerId,
            workDate: normalized,
            status: entry.status.code,
            siteId: Value(entry.siteId),
            note: Value(entry.note),
            updatedAt: Value(now),
            lastModifiedBy: Value(_ctx.userId),
            deviceId: Value(_ctx.deviceId),
            syncVersion: Value(nextVersion),
          ),
          onConflict: DoUpdate(
            (_) => AttendanceEntriesCompanion(
              status: Value(entry.status.code),
              siteId: Value(entry.siteId),
              note: Value(entry.note),
              updatedAt: Value(now),
              lastModifiedBy: Value(_ctx.userId),
              deviceId: Value(_ctx.deviceId),
              syncVersion: Value(nextVersion),
            ),
            target: [
              _db.attendanceEntries.workerId,
              _db.attendanceEntries.workDate,
            ],
          ),
        );

        // Read back to get actual id (may differ on conflict) and sync
        final saved = await (_db.select(_db.attendanceEntries)
              ..where(
                (a) =>
                    a.workerId.equals(entry.workerId) &
                    a.workDate.equals(normalized) &
                    a.deletedAt.isNull(),
              ))
            .getSingle();

        await _db.upsertQueueItem(
          id: _uuid.v4(),
          entityType: 'attendance',
          entityId: saved.id,
          action: 'upsert',
          payload: saved.toSyncMap(),
          organizationId: _ctx.organizationId,
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
    final entries = await (_db.select(_db.attendanceEntries)
          ..where(
            (a) =>
                a.workerId.equals(workerId) &
                a.workDate.isBetweenValues(start, end) &
                a.deletedAt.isNull(),
          ))
        .get();

    if (entries.isEmpty) return 0;

    final siteIds = entries
        .where((e) => e.siteId != null)
        .map((e) => e.siteId!)
        .toSet()
        .toList();

    if (siteIds.isEmpty) return 0;

    final sites = await (_db.select(_db.sites)
          ..where((s) => s.id.isIn(siteIds)))
        .get();

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
            a.workDate.isBetweenValues(start, end) &
            a.deletedAt.isNull(),
      )
      ..orderBy([(a) => OrderingTerm(expression: a.workDate)]);
    return query.get();
  }

  Stream<List<AttendanceEntry>> watchAllEntriesInRange({
    required DateTime start,
    required DateTime end,
  }) {
    final query = _db.select(_db.attendanceEntries)
      ..where(
        (a) =>
            a.workDate.isBetweenValues(start, end) &
            a.deletedAt.isNull(),
      )
      ..orderBy([(a) => OrderingTerm(expression: a.workDate)]);
    return query.watch();
  }

  /// Bir çalışanın [since] tarihinden itibaren kayıtlı en erken yoklama
  /// tarihini döndürür. Geçmişe dönük girilen yoklamaların periodStart
  /// hesabına dahil edilmesini sağlar.
  Future<DateTime?> earliestDateForWorker(
    String workerId, {
    required DateTime since,
  }) async {
    final query = _db.select(_db.attendanceEntries)
      ..where(
        (a) =>
            a.workerId.equals(workerId) &
            a.workDate.isBiggerOrEqualValue(since) &
            a.deletedAt.isNull(),
      )
      ..orderBy([(a) => OrderingTerm(expression: a.workDate)])
      ..limit(1);
    final entry = await query.getSingleOrNull();
    return entry?.workDate;
  }
}

// ---------------------------------------------------------------------------
// ExpenseRepository
// ---------------------------------------------------------------------------

class ExpenseRepository {
  ExpenseRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<Expense>> watchMonth(DateTime month) {
    final start = monthStart(month);
    final end = monthEnd(month);

    final query = _db.select(_db.expenses)
      ..where(
        (e) =>
            e.expenseDate.isBetweenValues(start, end) & e.deletedAt.isNull(),
      )
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

    await _db.transaction(() async {
      await _db.into(_db.expenses).insert(
        ExpensesCompanion.insert(
          id: id,
          expenseDate: normalized,
          amount: amount,
          category: category,
          siteId: Value(siteId),
          description: Value(description),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.expenses)
            ..where((e) => e.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'expense',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> deleteExpense({required String expenseId}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.expenses)
            ..where((e) => e.id.equals(expenseId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.expenses)..where((e) => e.id.equals(expenseId)))
          .write(ExpensesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        lastModifiedBy: Value(_ctx.userId),
        deviceId: Value(_ctx.deviceId),
        syncVersion: Value(nextVersion),
      ));

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'expense',
        entityId: expenseId,
        action: 'delete',
        payload: {
          'id': expenseId,
          'deletedAt': now.toIso8601String(),
          'lastModifiedBy': _ctx.userId,
          'deviceId': _ctx.deviceId,
          'syncVersion': nextVersion,
        },
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'expense',
        entityId: expenseId,
        message: 'Gider kaydi silindi',
      );
    });
  }

  Future<double> totalForMonth(DateTime month) async {
    final start = monthStart(month);
    final end = monthEnd(month);

    final totalExp = _db.expenses.amount.sum();
    final query = _db.selectOnly(_db.expenses)
      ..addColumns([totalExp])
      ..where(_db.expenses.expenseDate.isBetweenValues(start, end) &
          _db.expenses.deletedAt.isNull());

    final row = await query.getSingle();
    return row.read(totalExp) ?? 0;
  }
}

// ---------------------------------------------------------------------------
// IncomeRepository
// ---------------------------------------------------------------------------

class IncomeRepository {
  IncomeRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Stream<List<Income>> watchMonth(DateTime month) {
    final start = monthStart(month);
    final end = monthEnd(month);

    final query = _db.select(_db.incomes)
      ..where(
        (i) =>
            i.incomeDate.isBetweenValues(start, end) & i.deletedAt.isNull(),
      )
      ..orderBy([(i) => OrderingTerm.desc(i.incomeDate)]);
    return query.watch();
  }

  Future<void> addIncome({
    required DateTime date,
    required double amount,
    required String category,
    String? siteId,
    String? description,
  }) async {
    final id = _uuid.v4();
    final normalized = normalizeDay(date);

    await _db.transaction(() async {
      await _db.into(_db.incomes).insert(
        IncomesCompanion.insert(
          id: id,
          incomeDate: normalized,
          amount: amount,
          category: category,
          siteId: Value(siteId),
          description: Value(description),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.incomes)
            ..where((i) => i.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'income',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  Future<void> deleteIncome({required String incomeId}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.incomes)
            ..where((i) => i.id.equals(incomeId)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.incomes)..where((i) => i.id.equals(incomeId)))
          .write(IncomesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        lastModifiedBy: Value(_ctx.userId),
        deviceId: Value(_ctx.deviceId),
        syncVersion: Value(nextVersion),
      ));

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'income',
        entityId: incomeId,
        action: 'delete',
        payload: {
          'id': incomeId,
          'deletedAt': now.toIso8601String(),
          'lastModifiedBy': _ctx.userId,
          'deviceId': _ctx.deviceId,
          'syncVersion': nextVersion,
        },
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'income',
        entityId: incomeId,
        message: 'Gelir kaydi silindi',
      );
    });
  }

  Future<double> totalForMonth(DateTime month) async {
    final start = monthStart(month);
    final end = monthEnd(month);

    final totalExp = _db.incomes.amount.sum();
    final query = _db.selectOnly(_db.incomes)
      ..addColumns([totalExp])
      ..where(_db.incomes.incomeDate.isBetweenValues(start, end) &
          _db.incomes.deletedAt.isNull());

    final row = await query.getSingle();
    return row.read(totalExp) ?? 0;
  }
}

// ---------------------------------------------------------------------------
// AdvanceDebtRepository
// ---------------------------------------------------------------------------

class AdvanceDebtRepository {
  AdvanceDebtRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Future<void> add({
    required String workerId,
    required DateTime date,
    required String type,
    required double amount,
    String? note,
  }) async {
    final id = _uuid.v4();
    final month = monthKey(date);

    await _db.transaction(() async {
      await _db.into(_db.advanceDebts).insert(
        AdvanceDebtsCompanion.insert(
          id: id,
          workerId: workerId,
          eventDate: normalizeDay(date),
          type: type,
          amount: amount,
          note: Value(note),
          settledMonth: month,
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: const Value(1),
        ),
      );

      final saved = await (_db.select(_db.advanceDebts)
            ..where((a) => a.id.equals(id)))
          .getSingle();

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'advance_debt',
        entityId: id,
        action: 'upsert',
        payload: saved.toSyncMap(),
        organizationId: _ctx.organizationId,
      );
    });
  }

  /// Returns net deductions: advances (deducted) minus debts (owed to worker).
  Future<double> totalDeductions({
    required String workerId,
    required DateTime start,
    required DateTime end,
  }) async {
    final entries = await (_db.select(_db.advanceDebts)
          ..where(
            (a) =>
                a.workerId.equals(workerId) &
                a.eventDate.isBetweenValues(start, end) &
                a.deletedAt.isNull(),
          ))
        .get();

    double total = 0;
    for (final e in entries) {
      if (e.type == 'advance') {
        total += e.amount;
      } else if (e.type == 'debt') {
        total -= e.amount;
      }
    }
    return total;
  }

  Stream<List<AdvanceDebt>> watchByWorker(String workerId) {
    final query = _db.select(_db.advanceDebts)
      ..where((a) => a.workerId.equals(workerId) & a.deletedAt.isNull())
      ..orderBy([(a) => OrderingTerm.desc(a.eventDate)]);
    return query.watch();
  }

  Future<void> delete({required String id}) async {
    final now = DateTime.now();
    await _db.transaction(() async {
      final existing = await (_db.select(_db.advanceDebts)
            ..where((a) => a.id.equals(id)))
          .getSingleOrNull();
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

      await (_db.update(_db.advanceDebts)..where((a) => a.id.equals(id)))
          .write(
        AdvanceDebtsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ),
      );

      await _db.upsertQueueItem(
        id: _uuid.v4(),
        entityType: 'advance_debt',
        entityId: id,
        action: 'delete',
        payload: {
          'id': id,
          'deletedAt': now.toIso8601String(),
          'lastModifiedBy': _ctx.userId,
          'deviceId': _ctx.deviceId,
          'syncVersion': nextVersion,
        },
        organizationId: _ctx.organizationId,
      );

      await _db.addAudit(
        id: _uuid.v4(),
        entityType: 'advance_debt',
        entityId: id,
        message: 'Avans/Borc kaydi silindi',
      );
    });
  }
}

// ---------------------------------------------------------------------------
// PayrollRepository
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// PaymentRepository
// ---------------------------------------------------------------------------

class PaymentRepository {
  PaymentRepository(this._db, this._uuid, this._ctx);

  final AppDatabase _db;
  final Uuid _uuid;
  final SyncContext _ctx;

  Future<void> recordPayment({
    required String workerId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required double amount,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now();

    await _db.transaction(() async {
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
    });
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
      final nextVersion = (existing?.syncVersion ?? 0) + 1;

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
        message: 'Odeme iptal edildi',
      );
    });
  }
}

// ---------------------------------------------------------------------------
// SyncQueueRepository
// ---------------------------------------------------------------------------

class SyncQueueRepository {
  SyncQueueRepository(this._db);

  final AppDatabase _db;

  /// 15 başarısız denemeden sonra kalıcı hataya alınır. Deneme aralıkları
  /// exponential olarak büyür — böylece geçici Firestore/network sorunlarında
  /// saatler boyunca otomatik retry devam eder.
  static const int maxRetries = 15;

  Stream<int> pendingCount() {
    final countExp = _db.syncQueueItems.id.count();
    final query = _db.selectOnly(_db.syncQueueItems)
      ..addColumns([countExp])
      ..where(_db.syncQueueItems.status.equals('pending'));

    return query.watchSingle().map((row) => row.read(countExp) ?? 0);
  }

  /// Kalıcı hatayla işaretlenmiş öğelerin sayısı — UI'da uyarı rozetinde
  /// gösterilir. Sıfırdan büyükse kullanıcıya "manuel inceleme gerekli"
  /// bildirimi sunulur.
  Stream<int> failedPermanentCount() {
    final countExp = _db.syncQueueItems.id.count();
    final query = _db.selectOnly(_db.syncQueueItems)
      ..addColumns([countExp])
      ..where(_db.syncQueueItems.status.equals('failed_permanent'));

    return query.watchSingle().map((row) => row.read(countExp) ?? 0);
  }

  /// Kalıcı hatayla işaretlenmiş öğeleri listeler (detay ekranında
  /// gösterilebilmesi için).
  Future<List<SyncQueueItem>> failedPermanentItems() {
    final query = _db.select(_db.syncQueueItems)
      ..where((q) => q.status.equals('failed_permanent'))
      ..orderBy([(q) => OrderingTerm.desc(q.createdAt)]);
    return query.get();
  }

  /// Retry için tekrar uygun hale gelmiş pending öğeleri döndürür
  /// (backoff süresi dolmuş veya hiç fail olmamış).
  Future<List<SyncQueueItem>> pendingItems() {
    final now = DateTime.now();
    final query = _db.select(_db.syncQueueItems)
      ..where(
        (q) =>
            q.status.equals('pending') &
            (q.nextAttemptAt.isNull() |
                q.nextAttemptAt.isSmallerOrEqualValue(now)),
      )
      ..orderBy([(q) => OrderingTerm(expression: q.createdAt)]);
    return query.get();
  }

  /// Backoff bekleyen en erken pending öğenin zamanı — SyncService bu
  /// zamanda yeniden flush tetikler.
  Future<DateTime?> nextBackoffAt() async {
    final now = DateTime.now();
    final query = _db.select(_db.syncQueueItems)
      ..where(
        (q) =>
            q.status.equals('pending') &
            q.nextAttemptAt.isNotNull() &
            q.nextAttemptAt.isBiggerThanValue(now),
      )
      ..orderBy([(q) => OrderingTerm(expression: q.nextAttemptAt)])
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row?.nextAttemptAt;
  }

  Future<void> markSynced(String id) {
    return (_db.update(_db.syncQueueItems)
          ..where((q) => q.id.equals(id)))
        .write(
      SyncQueueItemsCompanion(
        status: const Value('done'),
        processedAt: Value(DateTime.now()),
        nextAttemptAt: const Value(null),
        lastError: const Value(null),
      ),
    );
  }

  Future<void> markFailed(
    String id, {
    required int retryCount,
    String? error,
  }) {
    if (retryCount >= maxRetries) {
      return (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id)))
          .write(
        SyncQueueItemsCompanion(
          status: const Value('failed_permanent'),
          retryCount: Value(retryCount),
          lastError: Value(error),
        ),
      );
    }

    final delay = _backoffDelay(retryCount);
    final nextAt = DateTime.now().add(delay);
    return (_db.update(_db.syncQueueItems)..where((q) => q.id.equals(id)))
        .write(
      SyncQueueItemsCompanion(
        status: const Value('pending'),
        retryCount: Value(retryCount),
        nextAttemptAt: Value(nextAt),
        lastError: Value(error),
      ),
    );
  }

  /// Exponential backoff: 2s, 4s, 8s, 16s, 32s, 64s, 128s, 256s, 512s
  /// sonra 10dk tavan. Jitter eklenir ki birden fazla cihaz aynı anda
  /// thundering-herd oluşturmasın.
  Duration _backoffDelay(int retryCount) {
    final exp = retryCount.clamp(1, 10);
    final baseSeconds = 1 << exp; // 2..1024
    final capped = baseSeconds > 600 ? 600 : baseSeconds;
    final jitter = (DateTime.now().microsecondsSinceEpoch % 1000) / 1000.0;
    final withJitter = capped + (capped * 0.25 * jitter);
    return Duration(milliseconds: (withJitter * 1000).round());
  }

  /// Boş organizationId'li orphan kuyruk öğelerini verilen orgId ile tamir
  /// eder. Hem pending hem failed_permanent kapsanır — aksi halde orgId
  /// bulunamadığı için failed_permanent'a düşmüş orphan'lar "Tümünü Tekrar
  /// Dene" sonrası yine boş orgId ile pending'e dönüp tekrar fail olurdu.
  Future<int> backfillOrgId(String organizationId) {
    if (organizationId.isEmpty) return Future.value(0);
    return (_db.update(_db.syncQueueItems)
          ..where(
            (q) =>
                q.organizationId.equals('') &
                (q.status.equals('pending') |
                    q.status.equals('failed_permanent')),
          ))
        .write(
      SyncQueueItemsCompanion(organizationId: Value(organizationId)),
    );
  }

  /// Tamir edilemeyen öğeyi kalıcı hata olarak işaretler — veri silinmez,
  /// ileride elle incelenebilir.
  Future<void> markAbandoned(String id, {String? reason}) {
    return (_db.update(_db.syncQueueItems)
          ..where((q) => q.id.equals(id)))
        .write(
      SyncQueueItemsCompanion(
        status: const Value('failed_permanent'),
        lastError: Value(reason),
      ),
    );
  }

  /// Kullanıcı "tekrar dene" dediğinde failed_permanent öğeleri yeniden
  /// pending'e alır. retryCount sıfırlanır ki backoff baştan başlasın.
  Future<int> retryFailedPermanent() {
    return (_db.update(_db.syncQueueItems)
          ..where((q) => q.status.equals('failed_permanent')))
        .write(
      const SyncQueueItemsCompanion(
        status: Value('pending'),
        retryCount: Value(0),
        nextAttemptAt: Value(null),
        lastError: Value(null),
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

// ---------------------------------------------------------------------------
// SiteReportRepository — şantiye maliyet özeti
// ---------------------------------------------------------------------------

class SiteWorkerRow {
  const SiteWorkerRow({
    required this.workerId,
    required this.workerName,
    required this.fullDays,
    required this.halfDays,
    required this.dayEquivalent,
    required this.dailyWage,
    required this.siteBonus,
    required this.totalWage,
  });

  final String workerId;
  final String workerName;
  final int fullDays;
  final int halfDays;
  final double dayEquivalent;
  final double dailyWage;
  final double siteBonus;
  final double totalWage;
}

class SiteExpenseCategory {
  const SiteExpenseCategory({
    required this.category,
    required this.total,
  });

  final String category;
  final double total;
}

class SiteReportData {
  const SiteReportData({
    required this.site,
    required this.firstWorkDate,
    required this.lastWorkDate,
    required this.workerRows,
    required this.totalWages,
    required this.expenseCategories,
    required this.totalExpenses,
    required this.grandTotal,
  });

  final Site site;
  final DateTime? firstWorkDate;
  final DateTime? lastWorkDate;
  final List<SiteWorkerRow> workerRows;
  final double totalWages;
  final List<SiteExpenseCategory> expenseCategories;
  final double totalExpenses;
  final double grandTotal;
}

class SiteReportRepository {
  SiteReportRepository(this._db);

  final AppDatabase _db;

  Future<SiteReportData> getReport(String siteId) async {
    final site = await (_db.select(_db.sites)
          ..where((s) => s.id.equals(siteId)))
        .getSingle();

    // Şantiyeye ait tüm yoklama kayıtları (tarih sıralı)
    final entries = await (_db.select(_db.attendanceEntries)
          ..where((a) => a.siteId.equals(siteId) & a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm(expression: a.workDate)]))
        .get();

    final firstWorkDate = entries.isEmpty ? null : entries.first.workDate;
    final lastWorkDate = entries.isEmpty ? null : entries.last.workDate;

    // İşçileri çek
    final workerIds = entries.map((e) => e.workerId).toSet().toList();
    final List<Worker> workers;
    if (workerIds.isEmpty) {
      workers = [];
    } else {
      workers = await (_db.select(_db.workers)
            ..where((w) => w.id.isIn(workerIds)))
          .get();
    }
    final workerById = {for (final w in workers) w.id: w};

    // Her işçi için hesapla
    final workerRows = <SiteWorkerRow>[];
    for (final wId in workerIds) {
      final worker = workerById[wId];
      if (worker == null) continue;
      final workerEntries = entries.where((e) => e.workerId == wId);
      int fullDays = 0;
      int halfDays = 0;
      for (final e in workerEntries) {
        final status = AttendanceStatusX.fromCode(e.status);
        if (status == AttendanceStatus.worked) {
          fullDays++;
        } else if (status == AttendanceStatus.halfDay) {
          halfDays++;
        }
      }
      final dayEquivalent = fullDays + halfDays * 0.5;
      workerRows.add(SiteWorkerRow(
        workerId: wId,
        workerName: worker.fullName,
        fullDays: fullDays,
        halfDays: halfDays,
        dayEquivalent: dayEquivalent,
        dailyWage: worker.dailyWage,
        siteBonus: site.dailyBonus,
        totalWage: dayEquivalent * (worker.dailyWage + site.dailyBonus),
      ));
    }
    workerRows.sort((a, b) => a.workerName.compareTo(b.workerName));
    final totalWages =
        workerRows.fold<double>(0, (s, r) => s + r.totalWage);

    // Giderler
    final expenses = await (_db.select(_db.expenses)
          ..where((e) => e.siteId.equals(siteId) & e.deletedAt.isNull()))
        .get();
    final categoryTotals = <String, double>{};
    for (final e in expenses) {
      categoryTotals[e.category] =
          (categoryTotals[e.category] ?? 0) + e.amount;
    }
    final expenseCategories = categoryTotals.entries
        .map((e) => SiteExpenseCategory(category: e.key, total: e.value))
        .toList()
      ..sort((a, b) => b.total.compareTo(a.total));
    final totalExpenses =
        expenses.fold<double>(0, (s, e) => s + e.amount);

    return SiteReportData(
      site: site,
      firstWorkDate: firstWorkDate,
      lastWorkDate: lastWorkDate,
      workerRows: workerRows,
      totalWages: totalWages,
      expenseCategories: expenseCategories,
      totalExpenses: totalExpenses,
      grandTotal: totalWages + totalExpenses,
    );
  }
}
