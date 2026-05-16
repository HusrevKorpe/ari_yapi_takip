import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../../shared/attendance_status.dart';
import '../../../shared/month_utils.dart';
import '../../../shared/payroll_calculator.dart';
import '../../sync/sync_context.dart';
import '../../sync/sync_mappers.dart';
import '../app_database.dart';
import 'dtos.dart';

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

    final existingEntries = await (_db.select(_db.attendanceEntries)
          ..where((a) => a.workDate.equals(normalized) & a.deletedAt.isNull()))
        .get();
    final existingVersions = {
      for (final e in existingEntries) e.workerId: e.syncVersion,
    };

    await _db.transaction(() async {
      for (final entry in entries) {
        final nextVersion = (existingVersions[entry.workerId] ?? 0) + 1;
        final id = _uuid.v4();
        await _db.into(_db.attendanceEntries).insert(
          AttendanceEntriesCompanion.insert(
            id: id,
            workerId: entry.workerId,
            workDate: normalized,
            status: entry.status.code,
            siteId: Value(entry.siteId),
            secondSiteId: Value(entry.secondSiteId),
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
              secondSiteId: Value(entry.secondSiteId),
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

  Future<void> deleteEntriesForWorkers({
    required DateTime date,
    required List<String> workerIds,
  }) async {
    if (workerIds.isEmpty) return;
    final normalized = normalizeDay(date);
    final now = DateTime.now();

    await _db.transaction(() async {
      final existing = await (_db.select(_db.attendanceEntries)
            ..where(
              (a) =>
                  a.workDate.equals(normalized) &
                  a.workerId.isIn(workerIds) &
                  a.deletedAt.isNull(),
            ))
          .get();

      for (final entry in existing) {
        final nextVersion = entry.syncVersion + 1;
        await (_db.update(_db.attendanceEntries)
              ..where((a) => a.id.equals(entry.id)))
            .write(AttendanceEntriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          lastModifiedBy: Value(_ctx.userId),
          deviceId: Value(_ctx.deviceId),
          syncVersion: Value(nextVersion),
        ));

        await _db.upsertQueueItem(
          id: _uuid.v4(),
          entityType: 'attendance',
          entityId: entry.id,
          action: 'delete',
          payload: {
            'id': entry.id,
            'deletedAt': now.toIso8601String(),
            'lastModifiedBy': _ctx.userId,
            'deviceId': _ctx.deviceId,
            'syncVersion': nextVersion,
          },
          organizationId: _ctx.organizationId,
        );
      }

      if (existing.isNotEmpty) {
        await _db.addAudit(
          id: _uuid.v4(),
          entityType: 'attendance',
          entityId: normalized.toIso8601String(),
          message: '${existing.length} adet yoklama kaydi silindi',
        );
      }
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

    final siteIds = <String>{
      for (final e in entries) ...[
        if (e.siteId != null) e.siteId!,
        if (e.secondSiteId != null) e.secondSiteId!,
      ],
    }.toList();

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

  Stream<List<AttendanceEntry>> watchWorkerEntriesInRange({
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
    return query.watch();
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

  Future<double> totalWorkedDayEquivalent(String workerId) async {
    final entries = await (_db.select(_db.attendanceEntries)
          ..where(
            (a) => a.workerId.equals(workerId) & a.deletedAt.isNull(),
          ))
        .get();
    return PayrollCalculator.workedEquivalent(
      entries.map((e) => AttendanceStatusX.fromCode(e.status)),
    );
  }

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
