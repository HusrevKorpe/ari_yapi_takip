import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/formatters.dart';
import '../../shared/ui/empty_state_view.dart';
import '../../shared/ui/live_list_view.dart';
import '../workers/workers_page.dart';
import 'widgets/worker_payroll_card.dart';
import 'widgets/worker_payroll_sheet.dart';

class _PayrollSummary {
  const _PayrollSummary({
    required this.pendingWorkers,
    required this.totalPending,
  });

  final int pendingWorkers;
  final double totalPending;
}

final _payrollSummaryProvider =
    FutureProvider.autoDispose<_PayrollSummary>((ref) async {
  final workers = await ref.watch(workersProvider.future);
  var count = 0;
  var total = 0.0;
  for (final w in workers) {
    final result = await ref.watch(workerPayrollProvider(w).future);
    if (result != null && result.net > 0) {
      count++;
      total += result.net;
    }
  }
  return _PayrollSummary(pendingWorkers: count, totalPending: total);
});

class PayrollPage extends ConsumerWidget {
  const PayrollPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(workersProvider);
    final summaryAsync = ref.watch(_payrollSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Maaş')),
      body: Column(
        children: [
          _SummaryHeader(async: summaryAsync),
          Expanded(
            child: LiveListView<Worker>(
              async: workersAsync,
              idOf: (w) => w.id,
              emptyState: const EmptyStateView(
                icon: Icons.payments_rounded,
                title: 'Maaş hesaplanacak çalışan yok',
                message: 'Önce Çalışanlar sekmesinden çalışan ekleyin.',
              ),
              itemBuilder: (context, worker) => WorkerPayrollCard(
                worker: worker,
                onTap: () => _openWorkerSheet(context, worker),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openWorkerSheet(BuildContext context, Worker worker) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkerPayrollSheet(worker: worker),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.async});

  final AsyncValue<_PayrollSummary> async;

  @override
  Widget build(BuildContext context) {
    final summary = async.valueOrNull;
    if (summary == null) {
      return const SizedBox(height: AppSpacing.md);
    }
    final hasPending = summary.pendingWorkers > 0;
    final accent = hasPending ? AppColors.brand : AppColors.success;
    final surface =
        hasPending ? AppColors.brandSurface : AppColors.successLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: accent.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                hasPending
                    ? Icons.account_balance_wallet_rounded
                    : Icons.verified_rounded,
                color: accent,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    hasPending ? 'Bekleyen ödeme' : 'Tüm ödemeler güncel',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPending
                        ? '${summary.pendingWorkers} çalışan'
                        : 'Bekleyen yok',
                    style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                  ),
                ],
              ),
            ),
            if (hasPending)
              Text(
                formatMoney(summary.totalPending),
                style: AppTextStyles.cardTitle.copyWith(
                  color: accent,
                  fontSize: 19,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
