import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/local/repositories.dart';
import 'repository_providers.dart';

final siteReportProvider =
    FutureProvider.autoDispose.family<SiteReportData, String>((ref, siteId) {
  return ref.watch(siteReportRepositoryProvider).getReport(siteId);
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
