import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/repositories.dart';
import '../../../shared/formatters.dart';
import '../../../shared/snackbar_helper.dart';
import 'payment_history_list.dart';
import 'payroll_breakdown_card.dart';

class WorkerPayrollSheet extends ConsumerWidget {
  const WorkerPayrollSheet({super.key, required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payrollAsync = ref.watch(workerPayrollProvider(worker));

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
            child: payrollAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Hesaplama hatasi: $e'),
              ),
              data: (result) => _SheetBody(worker: worker, result: result),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetBody extends ConsumerWidget {
  const _SheetBody({required this.worker, required this.result});

  final Worker worker;
  final PayrollResult? result;

  Future<void> _recordPayment(BuildContext context, WidgetRef ref) async {
    final current = result;
    if (current == null || current.net <= 0) return;

    try {
      await ref.read(payrollRepositoryProvider).saveSnapshot(current);
      await ref.read(paymentRepositoryProvider).recordPayment(
            workerId: current.worker.id,
            periodStart: current.periodStart,
            periodEnd: current.periodEnd,
            amount: current.net,
          );
      ref.invalidate(lastPaymentEndProvider(current.worker.id));
      ref.invalidate(workerPayrollProvider(worker));

      if (context.mounted) {
        showSuccessSnackBar(context, 'Maas odendi olarak kaydedildi');
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Kayit hatasi: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textTheme = Theme.of(context).textTheme;
    final current = result;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          worker.fullName,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Yevmiye: ${formatMoney(worker.dailyWage)}',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF888888),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        if (current != null) ...[
          PayrollBreakdownCard(result: current),
          const SizedBox(height: 16),
          PayrollPayButton(
            result: current,
            onPay: () => _recordPayment(context, ref),
          ),
        ] else
          const PayrollNoPendingBanner(),
        const SizedBox(height: 28),
        PaymentHistoryList(workerId: worker.id),
      ],
    );
  }
}
