import 'package:drift/drift.dart';

import '../../../shared/attendance_status.dart';
import '../app_database.dart';
import 'dtos.dart';

class SiteReportRepository {
  SiteReportRepository(this._db);

  final AppDatabase _db;

  Future<SiteReportData> getReport(String siteId) async {
    final site = await (_db.select(_db.sites)
          ..where((s) => s.id.equals(siteId)))
        .getSingle();

    final entries = await (_db.select(_db.attendanceEntries)
          ..where((a) => a.siteId.equals(siteId) & a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm(expression: a.workDate)]))
        .get();

    final firstWorkDate = entries.isEmpty ? null : entries.first.workDate;
    final lastWorkDate = entries.isEmpty ? null : entries.last.workDate;

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
