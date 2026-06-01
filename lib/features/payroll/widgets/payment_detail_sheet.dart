import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/repositories.dart';
import '../../../shared/formatters.dart';
import 'cancel_payment_dialog.dart';
import 'day_detail_expander.dart';
import 'payroll_shared.dart';

Future<void> showPaymentDetailSheet(
  BuildContext context,
  PayrollPayment payment,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _PaymentDetailSheet(payment: payment),
  );
}

class _PaymentDetailSheet extends ConsumerWidget {
  const _PaymentDetailSheet({required this.payment});

  final PayrollPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(_paymentSnapshotProvider(payment));
    final daysAsync = ref.watch(paymentBreakdownProvider(payment));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
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
            child: snapshotAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Hata: $e'),
              ),
              data: (snapshot) => _DetailBody(
                payment: payment,
                snapshot: snapshot,
                days: daysAsync.asData?.value ?? const [],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final _paymentSnapshotProvider = FutureProvider.autoDispose
    .family<PayrollSnapshot?, PayrollPayment>((ref, payment) {
  return ref.watch(payrollRepositoryProvider).getSnapshot(
        workerId: payment.workerId,
        periodStart: payment.periodStart,
        periodEnd: payment.periodEnd,
      );
});

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.payment,
    required this.snapshot,
    required this.days,
  });

  final PayrollPayment payment;
  final PayrollSnapshot? snapshot;
  final List<PayrollAttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      children: [
        Text(
          'Ödeme Detayı',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1A1A1A),
              ),
        ),
        const SizedBox(height: 18),
        PayrollSummaryRow(
          label: 'Dönem',
          value:
              '${formatDate(payment.periodStart)} – ${formatDate(payment.periodEnd)}',
        ),
        const SizedBox(height: 12),
        PayrollSummaryRow(
          label: 'Ödeme Tarihi',
          value: formatDate(payment.paidAt),
        ),
        const SizedBox(height: 12),
        PayrollSummaryRow(
          label: 'Ödenen Tutar',
          value: formatMoney(payment.amount),
          valueColor: const Color(0xFF1A6B5A),
        ),
        if (snapshot != null) ...[
          const SizedBox(height: 16),
          const Divider(color: Color(0xFFDCDCDD)),
          const SizedBox(height: 12),
          PayrollSummaryRow(
            label: 'Çalışılan Gün',
            value: formatWorkedDays(snapshot!.workedDayEquivalent),
          ),
          const SizedBox(height: 12),
          PayrollSummaryRow(
            label: 'Brut',
            value: formatMoney(snapshot!.gross),
          ),
          const SizedBox(height: 12),
          if (snapshot!.deductions < 0)
            // Borç avansı aştığında kesinti negatiftir; net'i artıran bu tutarı
            // "Kesinti" gibi göstermeyip ayrı bir "Alacak" satırı veriyoruz.
            PayrollSummaryRow(
              label: 'Alacak (Avans+Borç)',
              value: '+${formatMoney(-snapshot!.deductions)}',
              valueColor: const Color(0xFF1A6B5A),
            )
          else
            PayrollSummaryRow(
              label: 'Kesinti',
              value: formatMoney(snapshot!.deductions),
              valueColor: const Color(0xFFB60A0A),
            ),
          const SizedBox(height: 12),
          PayrollSummaryRow(
            label: 'Net',
            value: formatMoney(snapshot!.net),
            valueColor: const Color(0xFF1A6B5A),
          ),
        ],
        if (days.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDCDCDD)),
            ),
            child: DayDetailExpander(days: days),
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
            onPressed: () => cancelPaymentFlow(context, payment),
            icon: const Icon(Icons.undo_rounded, size: 18),
            label: const Text(
              'Ödemeyi İptal Et',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
