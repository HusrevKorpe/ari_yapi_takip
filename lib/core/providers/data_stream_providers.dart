import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../data/local/repositories.dart';
import '../../shared/month_utils.dart';
import '../../shared/wage_history.dart';
import 'repository_providers.dart';

class WorkerLifetimeStats {
  const WorkerLifetimeStats({
    required this.workedDayEquivalent,
    required this.totalAdvances,
    required this.totalPaid,
    required this.netPosition,
  });

  final double workedDayEquivalent;
  final double totalAdvances;
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

      // Tarih bazlı yevmiye: geçmiş her gün kendi günündeki yevmiyeyle toplanır
      // (zam geçmişi yeniden fiyatlamasın). Geçmiş boşsa güncel yevmiye kullanılır.
      final dailyWage = worker?.dailyWage ?? 0;
      final wages = WageHistory.decode(worker?.wageHistory);

      final results = await Future.wait([
        attendance.totalWorkedDayEquivalent(workerId),
        advanceDebt.totalAdvances(workerId),
        payment.totalPaid(workerId),
        attendance.totalLocationBonus(workerId),
        attendance.lifetimeWageGross(
          workerId,
          (d) => wages.wageForDate(d, dailyWage),
        ),
      ]);
      final worked = results[0];
      final advances = results[1];
      final paid = results[2];
      final lifetimeLocationBonus = results[3];
      final wageGross = results[4];

      final receivesBonus = worker?.receivesBonus ?? false;
      final gross = wageGross + (receivesBonus ? lifetimeLocationBonus : 0);
      final netPosition = gross - advances - paid;

      return WorkerLifetimeStats(
        workedDayEquivalent: worked,
        totalAdvances: advances,
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

/// Ödeme detayında gösterilecek günlük döküm ve kaynağı.
///
/// - [isFrozen] == true: ödeme anında dondurulmuş snapshot'tan geldi; yukarıdaki
///   özetle (Çalışılan Gün / Brut) birebir uyumludur.
/// - [isFrozen] == false: v13 öncesi ödeme, o an döküm saklanmadığı için GÜNCEL
///   puantaj kayıtlarından yeniden hesaplandı ("canlı" döküm). Ödemeden sonra o
///   döneme gün girildiyse listede donmuş özetten fazla satır çıkabilir; çağıran
///   taraf bunu bir notla belirtir.
class PaymentBreakdown {
  const PaymentBreakdown({required this.days, required this.isFrozen});

  final List<PayrollAttendanceDay> days;
  final bool isFrozen;
}

/// Ödemenin günlük dökümünü döner. Önce ödeme anında dondurulmuş snapshot'a
/// bakar; yoksa (eski ödeme) kullanıcı yine de detayı görebilsin diye güncel
/// puantajdan yeniden hesaplar ve `isFrozen: false` ile işaretler.
final paymentBreakdownProvider = FutureProvider.autoDispose
    .family<PaymentBreakdown, PayrollPayment>((ref, payment) async {
  final payrollRepo = ref.watch(payrollRepositoryProvider);

  // Ödeme anında dondurulmuş döküm — attendance sonradan değişse bile ödemenin
  // gerçeğini birebir korur.
  final frozen = await payrollRepo.getSnapshotDays(
    workerId: payment.workerId,
    periodStart: payment.periodStart,
    periodEnd: payment.periodEnd,
  );
  if (frozen != null) {
    return PaymentBreakdown(days: frozen, isFrozen: true);
  }

  // v13 öncesi ödemede döküm saklanmadı: kullanıcının en eski ödemesinin bile
  // günlük detayını görebilmesi için güncel puantajdan yeniden hesapla.
  final worker =
      await ref.watch(workerRepositoryProvider).findById(payment.workerId);
  if (worker == null) {
    return const PaymentBreakdown(days: [], isFrozen: false);
  }
  // Ödeme anındaki puantajı yeniden kur: yalnızca ödeme yapıldığı ana kadar
  // girilmiş günler. Böylece liste, üstteki donmuş "çalışılan gün" sayısıyla
  // tutar; ödemeden SONRA o döneme eklenen günler (devreden bakiyeye giden)
  // listeye sızıp tutarsızlık yaratmaz.
  final result = await payrollRepo.calculate(
    worker: worker,
    periodStart: payment.periodStart,
    periodEnd: payment.periodEnd,
    asOf: payment.paidAt,
  );
  return PaymentBreakdown(days: result.attendanceDays, isFrozen: false);
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

  if (periodStart.isAfter(today)) {
    // Son ödeme bugünü de kapatmış (açık dönem yok). Yine de ödenmiş döneme
    // aynı gün içinde sonradan puantaj/avans girilmiş olabilir; devreden
    // bakiye varsa gizlemeden göster.
    final carry = await ref
        .watch(payrollRepositoryProvider)
        .carryOnly(worker: worker, asOf: today);
    return carry.net == 0 ? null : carry;
  }

  return ref.watch(payrollRepositoryProvider).calculate(
        worker: worker,
        periodStart: periodStart,
        periodEnd: today,
        includeCarryOver: true,
      );
});
