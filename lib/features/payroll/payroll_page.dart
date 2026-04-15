import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/local/repositories.dart';
import '../../shared/attendance_status.dart';
import '../../shared/formatters.dart';
import '../../shared/snackbar_helper.dart';
import '../workers/workers_page.dart';

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class PayrollPage extends ConsumerWidget {
  const PayrollPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Maas')),
      body: workersAsync.when(
        data: (workers) {
          if (workers.isEmpty) {
            return const Center(
              child: Text('Maas hesaplamak icin calisan ekleyin.'),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: workers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final worker = workers[index];
              return _WorkerPayrollCard(
                worker: worker,
                onTap: () => _openWorkerSheet(context, ref, worker),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }

  void _openWorkerSheet(BuildContext context, WidgetRef ref, Worker worker) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _WorkerPayrollSheet(worker: worker),
    );
  }
}

// ---------------------------------------------------------------------------
// Worker card on the main list
// ---------------------------------------------------------------------------

class _WorkerPayrollCard extends ConsumerWidget {
  const _WorkerPayrollCard({required this.worker, required this.onTap});

  final Worker worker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPaidEnd = ref
        .watch(lastPaymentEndProvider(worker.id))
        .valueOrNull;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final periodStart = lastPaidEnd != null
        ? DateTime(lastPaidEnd.year, lastPaidEnd.month, lastPaidEnd.day + 1)
        : DateTime(
            worker.createdAt.year,
            worker.createdAt.month,
            worker.createdAt.day,
          );

    final pendingDays = today.difference(periodStart).inDays + 1;
    final hasPending = pendingDays > 0;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasPending
                ? const Color(0xFFD9C97A)
                : const Color(0xFFDCDCDD),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasPending
                    ? const Color(0xFF8A7300).withValues(alpha: 0.12)
                    : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.person_outline_rounded,
                size: 22,
                color: hasPending
                    ? const Color(0xFF8A7300)
                    : const Color(0xFF999999),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.fullName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasPending
                        ? 'Son odeme: ${lastPaidEnd != null ? formatDate(lastPaidEnd) : "Yok"}'
                        : 'Guncel',
                    style: TextStyle(
                      fontSize: 11,
                      color: hasPending
                          ? const Color(0xFF888888)
                          : const Color(0xFF1A6B5A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasPending) ...[
                  Text(
                    '$pendingDays gun',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8A7300),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'bekliyor',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF888888),
                    ),
                  ),
                ] else
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF1A6B5A),
                    size: 22,
                  ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF999999),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bottom sheet: full detail + pay + history
// ---------------------------------------------------------------------------

class _WorkerPayrollSheet extends ConsumerStatefulWidget {
  const _WorkerPayrollSheet({required this.worker});
  final Worker worker;

  @override
  ConsumerState<_WorkerPayrollSheet> createState() =>
      _WorkerPayrollSheetState();
}

class _WorkerPayrollSheetState extends ConsumerState<_WorkerPayrollSheet> {
  PayrollResult? _result;
  bool _calculating = true;

  @override
  void initState() {
    super.initState();
    _autoCalculate();
  }

  Future<void> _autoCalculate() async {
    final lastPaidEnd = await ref
        .read(paymentRepositoryProvider)
        .lastPaymentEnd(widget.worker.id);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final DateTime periodStart;
    if (lastPaidEnd != null) {
      // Önceki ödeme varsa bir sonraki günden başla.
      periodStart = DateTime(
        lastPaidEnd.year,
        lastPaidEnd.month,
        lastPaidEnd.day + 1,
      );
    } else {
      // Önceki ödeme yok: createdAt ile en erken yoklama tarihinin küçüğünü
      // kullan. Böylece createdAt'tan önce girilen retroaktif yoklamalar da
      // hesaba dahil edilir.
      final createdAtDay = DateTime(
        widget.worker.createdAt.year,
        widget.worker.createdAt.month,
        widget.worker.createdAt.day,
      );
      final earliest = await ref
          .read(attendanceRepositoryProvider)
          .earliestDateForWorker(
            widget.worker.id,
            since: DateTime(2000), // tüm geçmişi tara
          );
      periodStart =
          (earliest != null && earliest.isBefore(createdAtDay))
          ? earliest
          : createdAtDay;
    }

    if (periodStart.isAfter(today)) {
      setState(() => _calculating = false);
      return;
    }

    try {
      final result = await ref
          .read(payrollRepositoryProvider)
          .calculate(
            worker: widget.worker,
            periodStart: periodStart,
            periodEnd: today,
          );
      if (mounted) {
        setState(() {
          _result = result;
          _calculating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _calculating = false);
        showErrorSnackBar(context, 'Hesaplama hatasi: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F2F4),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCCCCCC),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: _calculating
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                    children: [
                      // Header
                      Text(
                        widget.worker.fullName,
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Yevmiye: ${formatMoney(widget.worker.dailyWage)}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF888888),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 20),

                      if (_result != null) ...[
                        _buildPayrollBreakdown(_result!),
                        const SizedBox(height: 16),
                        _buildPayButton(_result!),
                      ] else
                        _buildNoPendingBanner(),

                      const SizedBox(height: 28),
                      _buildPaymentHistory(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollBreakdown(PayrollResult result) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCDCDD)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                _summaryRow(
                  'Donem',
                  '${formatDate(result.periodStart)} – ${formatDate(result.periodEnd)}',
                ),
                const SizedBox(height: 10),
                _summaryRow(
                  'Calistigi Gun',
                  _formatWorkedDays(result.workedDayEquivalent),
                ),
                const SizedBox(height: 10),
                _summaryRow(
                  'Yevmiye Toplam',
                  formatMoney(
                    result.workedDayEquivalent * result.worker.dailyWage,
                  ),
                ),
                if (result.locationBonus > 0) ...[
                  const SizedBox(height: 10),
                  _summaryRow(
                    'Bolge Primi',
                    '+${formatMoney(result.locationBonus)}',
                    valueColor: const Color(0xFF1A6B5A),
                  ),
                ],
                if (result.deductions > 0) ...[
                  const SizedBox(height: 10),
                  _summaryRow(
                    'Kesinti (Avans+Borc)',
                    '-${formatMoney(result.deductions)}',
                    valueColor: const Color(0xFFB60A0A),
                  ),
                ],
              ],
            ),
          ),
          // Net bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: result.net < 0
                  ? const Color(0xFFFFE0E0)
                  : const Color(0xFFEDF7F4),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Net Odenecek',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF4E4E4E),
                  ),
                ),
                Text(
                  formatMoney(result.net),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: result.net < 0
                        ? const Color(0xFFB60A0A)
                        : const Color(0xFF1A6B5A),
                  ),
                ),
              ],
            ),
          ),
          // Detail expand
          if (result.attendanceDays.isNotEmpty) _buildDayDetailExpander(result),
        ],
      ),
    );
  }

  Widget _buildDayDetailExpander(PayrollResult result) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: Row(
          children: [
            const Icon(
              Icons.calendar_today_rounded,
              size: 13,
              color: Color(0xFF888888),
            ),
            const SizedBox(width: 6),
            Text(
              'GUNLUK DETAY',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Color(0xFF888888),
              ),
            ),
          ],
        ),
        children: [for (final day in result.attendanceDays) _dayRow(day)],
      ),
    );
  }

  Widget _buildPayButton(PayrollResult result) {
    if (result.net <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE0E0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFF5252)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: Color(0xFFB60A0A),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.net == 0
                    ? 'Odenecek tutar yok.'
                    : 'Kesintiler brutten fazla. Net tutar negatif.',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFB60A0A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF145A4A), Color(0xFF1A6B5A)],
          ),
        ),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: _recordPayment,
          icon: const Icon(Icons.check_circle_outline, size: 20),
          label: const Text(
            'Maas Ver',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNoPendingBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF7F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB2DFDB)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: Color(0xFF1A6B5A),
          ),
          const SizedBox(width: 10),
          Text(
            'Tum odemeler guncel.',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A6B5A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentHistory() {
    final paymentsAsync = ref.watch(workerPaymentsProvider(widget.worker.id));

    return paymentsAsync.when(
      data: (payments) {
        if (payments.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.history_rounded,
                  size: 15,
                  color: Color(0xFF888888),
                ),
                const SizedBox(width: 6),
                Text(
                  'GECMIS ODEMELER',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Color(0xFF888888),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final payment in payments)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showPaymentDetail(payment),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFDCDCDD)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF1A6B5A,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            size: 18,
                            color: Color(0xFF1A6B5A),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${formatDate(payment.periodStart)} – ${formatDate(payment.periodEnd)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1A1A1A),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Odeme: ${formatDate(payment.paidAt)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF888888),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatMoney(payment.amount),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1A6B5A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }

  Future<void> _showPaymentDetail(PayrollPayment payment) async {
    final snapshot = await ref
        .read(payrollRepositoryProvider)
        .getSnapshot(
          workerId: payment.workerId,
          periodStart: payment.periodStart,
          periodEnd: payment.periodEnd,
        );

    if (!mounted) return;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          decoration: const BoxDecoration(
            color: Color(0xFFF2F2F4),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFCCCCCC),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  children: [
                    Text(
                      'Odeme Detayi',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                    const SizedBox(height: 18),
                    _summaryRow(
                      'Donem',
                      '${formatDate(payment.periodStart)} – ${formatDate(payment.periodEnd)}',
                    ),
                    const SizedBox(height: 12),
                    _summaryRow('Odeme Tarihi', formatDate(payment.paidAt)),
                    const SizedBox(height: 12),
                    _summaryRow(
                      'Odenen Tutar',
                      formatMoney(payment.amount),
                      valueColor: const Color(0xFF1A6B5A),
                    ),
                    if (snapshot != null) ...[
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFFDCDCDD)),
                      const SizedBox(height: 12),
                      _summaryRow(
                        'Calisilan Gun',
                        _formatWorkedDays(snapshot.workedDayEquivalent),
                      ),
                      const SizedBox(height: 12),
                      _summaryRow('Brut', formatMoney(snapshot.gross)),
                      const SizedBox(height: 12),
                      _summaryRow(
                        'Kesinti',
                        formatMoney(snapshot.deductions),
                        valueColor: const Color(0xFFB60A0A),
                      ),
                      const SizedBox(height: 12),
                      _summaryRow(
                        'Net',
                        formatMoney(snapshot.net),
                        valueColor: const Color(0xFF1A6B5A),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 50,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB60A0A),
                          side: const BorderSide(color: Color(0xFFFF5252)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () => _cancelPayment(payment, ctx),
                        icon: const Icon(Icons.undo_rounded, size: 18),
                        label: const Text(
                          'Odemeyi Iptal Et',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _cancelPayment(
    PayrollPayment payment,
    BuildContext sheetContext,
  ) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F4),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFD8D8DA)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26000000),
                blurRadius: 22,
                offset: Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB60A0A).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Color(0xFFB60A0A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Odemeyi Iptal Et',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Bu odeme iptal edilecek ve donem tekrar hesaplanabilir olacak. Emin misiniz?',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: Color(0xFF4E4E4E),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF1A1A1A),
                        side: const BorderSide(color: Color(0xFFD2D2D2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text(
                        'Vazgec',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0xFF8D0E0E), Color(0xFFD33A3A)],
                        ),
                      ),
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text(
                          'Iptal Et',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await ref
          .read(paymentRepositoryProvider)
          .deletePayment(paymentId: payment.id);
      ref.invalidate(lastPaymentEndProvider(payment.workerId));
      ref.invalidate(workerPaymentsProvider(payment.workerId));

      if (sheetContext.mounted) Navigator.pop(sheetContext);
      if (mounted) {
        showSuccessSnackBar(context, 'Odeme iptal edildi');
        // Re-calculate after cancellation
        setState(() {
          _result = null;
          _calculating = true;
        });
        _autoCalculate();
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Iptal hatasi: $e');
      }
    }
  }

  Future<void> _recordPayment() async {
    final result = _result;
    if (result == null || result.net <= 0) return;

    try {
      await ref.read(payrollRepositoryProvider).saveSnapshot(result);
      await ref
          .read(paymentRepositoryProvider)
          .recordPayment(
            workerId: result.worker.id,
            periodStart: result.periodStart,
            periodEnd: result.periodEnd,
            amount: result.net,
          );
      ref.invalidate(lastPaymentEndProvider(result.worker.id));

      if (mounted) {
        showSuccessSnackBar(context, 'Maas odendi olarak kaydedildi');
        setState(() {
          _result = null;
          _calculating = true;
        });
        _autoCalculate();
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Kayit hatasi: $e');
      }
    }
  }

  // ---- Shared widgets ----

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: Color(0xFF494949),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: valueColor ?? const Color(0xFF121212),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dayRow(PayrollAttendanceDay day) {
    final isHalf = day.dayEquivalent == 0.5;
    final isOff =
        day.status == AttendanceStatus.absent ||
        day.status == AttendanceStatus.leave;

    Color badgeBg;
    Color badgeText;
    if (isOff) {
      badgeBg = const Color(0xFFFFE0E0);
      badgeText = const Color(0xFFB60A0A);
    } else if (isHalf) {
      badgeBg = const Color(0xFFFFF3CD);
      badgeText = const Color(0xFF856404);
    } else {
      badgeBg = const Color(0xFFEDF7F4);
      badgeText = const Color(0xFF1A6B5A);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            formatDate(day.date),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF555555),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              day.status.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: badgeText,
              ),
            ),
          ),
          const Spacer(),
          if (day.siteBonus > 0) ...[
            Text(
              '+${formatMoney(day.siteBonus)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A6B5A),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            formatMoney(day.dailyAmount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isOff ? const Color(0xFF999999) : const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  String _formatWorkedDays(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }
}
