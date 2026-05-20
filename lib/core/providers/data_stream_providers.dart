import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/local/repositories.dart';
import '../../shared/month_utils.dart';
import 'repository_providers.dart';

class WorkerLifetimeStats {
  const WorkerLifetimeStats({
    required this.workedDayEquivalent,
    required this.totalAdvances,
    required this.totalDebts,
    required this.totalPaid,
  });

  final double workedDayEquivalent;
  final double totalAdvances;
  final double totalDebts;
  final double totalPaid;
}

final siteReportDateFilterProvider =
    StateProvider.autoDispose.family<Set<DateTime>?, String>(
  (ref, siteId) => null,
);

final siteReportProvider =
    FutureProvider.autoDispose.family<SiteReportData, String>((ref, siteId) {
  final dates = ref.watch(siteReportDateFilterProvider(siteId));
  return ref
      .watch(siteReportRepositoryProvider)
      .getReport(siteId, selectedDates: dates);
});

final lastPaymentEndProvider =
    FutureProvider.autoDispose.family<DateTime?, String>((ref, workerId) {
  return ref.read(paymentRepositoryProvider).lastPaymentEnd(workerId);
});

final workerPaymentsProvider =
    StreamProvider.autoDispose.family<List<PayrollPayment>, String>((
      ref,
      workerId,
    ) {
      return ref.watch(paymentRepositoryProvider).watchWorkerPayments(workerId);
    });

final workerAdvanceDebtsProvider =
    StreamProvider.autoDispose.family<List<AdvanceDebt>, String>((
      ref,
      workerId,
    ) {
      return ref.watch(advanceDebtRepositoryProvider).watchByWorker(workerId);
    });

final workerLifetimeStatsProvider =
    FutureProvider.autoDispose.family<WorkerLifetimeStats, String>((
      ref,
      workerId,
    ) async {
      final attendance = ref.watch(attendanceRepositoryProvider);
      final advanceDebt = ref.watch(advanceDebtRepositoryProvider);
      final payment = ref.watch(paymentRepositoryProvider);

      final results = await Future.wait([
        attendance.totalWorkedDayEquivalent(workerId),
        advanceDebt.lifetimeTotals(workerId),
        payment.totalPaid(workerId),
      ]);
      final worked = results[0] as double;
      final totals = results[1] as ({double advances, double debts});
      final paid = results[2] as double;

      return WorkerLifetimeStats(
        workedDayEquivalent: worked,
        totalAdvances: totals.advances,
        totalDebts: totals.debts,
        totalPaid: paid,
      );
    });

final workerMonthAttendanceProvider = StreamProvider.autoDispose
    .family<List<AttendanceEntry>, ({String workerId, DateTime month})>((
      ref,
      args,
    ) {
      final start = monthStart(args.month);
      final end = monthEnd(args.month);
      return ref
          .watch(attendanceRepositoryProvider)
          .watchWorkerEntriesInRange(workerId: args.workerId, start: start, end: end);
    });

final paymentBreakdownProvider = FutureProvider.autoDispose
    .family<List<PayrollAttendanceDay>, PayrollPayment>((ref, payment) async {
  final worker =
      await ref.watch(workerRepositoryProvider).findById(payment.workerId);
  if (worker == null) return const [];
  final result = await ref.watch(payrollRepositoryProvider).calculate(
        worker: worker,
        periodStart: payment.periodStart,
        periodEnd: payment.periodEnd,
      );
  return result.attendanceDays;
});

final workerPayrollProvider =
    FutureProvider.autoDispose.family<PayrollResult?, Worker>((ref, worker) async {
  final lastPaidEnd =
      await ref.watch(paymentRepositoryProvider).lastPaymentEnd(worker.id);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final DateTime periodStart;
  if (lastPaidEnd != null) {
    periodStart = DateTime(
      lastPaidEnd.year,
      lastPaidEnd.month,
      lastPaidEnd.day + 1,
    );
  } else {
    final createdAtDay = DateTime(
      worker.createdAt.year,
      worker.createdAt.month,
      worker.createdAt.day,
    );
    final earliest = await ref
        .watch(attendanceRepositoryProvider)
        .earliestDateForWorker(worker.id, since: DateTime(2000));
    periodStart = (earliest != null && earliest.isBefore(createdAtDay))
        ? earliest
        : createdAtDay;
  }

  if (periodStart.isAfter(today)) return null;

  return ref.watch(payrollRepositoryProvider).calculate(
        worker: worker,
        periodStart: periodStart,
        periodEnd: today,
      );
});
