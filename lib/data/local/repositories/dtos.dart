import '../../../shared/attendance_status.dart';
import '../app_database.dart';

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
