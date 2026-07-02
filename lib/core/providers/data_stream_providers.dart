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
    required this.netPosition,
  });

  final double workedDayEquivalent;
  final double totalAdvances;
  final double totalDebts;
  final double totalPaid;
  final double netPosition;
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

final allPartnerPaymentsProvider =
    StreamProvider<List<PartnerPayment>>((ref) {
  return ref.watch(partnerPaymentRepositoryProvider).watchAll();
});

/// Daha önce kullanılmış ortak isimleri — en son kullanılandan başlayarak,
/// tekrarsız. "Akıllı seçim" chip'lerini besler. Ödeme listesinden türetilir
/// (ayrı bir DB stream'i açmaz; liste zaten sekmede sıcak).
final knownPartnerNamesProvider = Provider<List<String>>((ref) {
  final payments = ref.watch(allPartnerPaymentsProvider).valueOrNull ??
      const <PartnerPayment>[];
  final seen = <String>{};
  final names = <String>[];
  for (final p in payments) {
    final name = p.partnerName.trim();
    if (name.isNotEmpty && seen.add(name)) names.add(name);
  }
  return names;
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
      final workerRepo = ref.watch(workerRepositoryProvider);

      final worker = await workerRepo.findById(workerId);

      final results = await Future.wait([
        attendance.totalWorkedDayEquivalent(workerId),
        advanceDebt.lifetimeTotals(workerId),
        payment.totalPaid(workerId),
        attendance.totalLocationBonus(workerId),
      ]);
      final worked = results[0] as double;
      final totals = results[1] as ({double advances, double debts});
      final paid = results[2] as double;
      final lifetimeLocationBonus = results[3] as double;

      final dailyWage = worker?.dailyWage ?? 0;
      final receivesBonus = worker?.receivesBonus ?? false;
      final gross =
          worked * dailyWage + (receivesBonus ? lifetimeLocationBonus : 0);
      final netPosition = gross + totals.debts - totals.advances - paid;

      return WorkerLifetimeStats(
        workedDayEquivalent: worked,
        totalAdvances: totals.advances,
        totalDebts: totals.debts,
        totalPaid: paid,
        netPosition: netPosition,
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
  final payrollRepo = ref.watch(payrollRepositoryProvider);

  // Önce ödeme anında dondurulmuş snapshot'tan oku — bu sayede attendance
  // sonradan değişse bile tarihsel ödeme detayı sabit kalır.
  final frozen = await payrollRepo.getSnapshotDays(
    workerId: payment.workerId,
    periodStart: payment.periodStart,
    periodEnd: payment.periodEnd,
  );
  if (frozen != null) return frozen;

  // Fallback: v13 öncesi snapshot'lar için canlı hesaplama. Worker silinmişse
  // boş liste — eski davranışla uyumlu.
  final worker =
      await ref.watch(workerRepositoryProvider).findById(payment.workerId);
  if (worker == null) return const [];
  final result = await payrollRepo.calculate(
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
