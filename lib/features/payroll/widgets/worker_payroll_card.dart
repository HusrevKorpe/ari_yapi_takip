import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/formatters.dart';

class WorkerPayrollCard extends ConsumerWidget {
  const WorkerPayrollCard({
    super.key,
    required this.worker,
    required this.onTap,
  });

  final Worker worker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPaidEnd = ref
        .watch(lastPaymentEndProvider(worker.id))
        .valueOrNull;
    final payrollAsync = ref.watch(workerPayrollProvider(worker));

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
    final result = payrollAsync.valueOrNull;
    final net = result?.net ?? 0;
    final isLoading = payrollAsync.isLoading && !payrollAsync.hasValue;
    final negative = net < 0;

    final accent = hasPending
        ? (negative ? AppColors.danger : AppColors.brand)
        : AppColors.success;
    final accentSurface = hasPending
        ? (negative ? AppColors.dangerLight : AppColors.brandSurface)
        : AppColors.successLight;

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: hasPending
                  ? accent.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              _LeadingBadge(
                hasPending: hasPending,
                pendingDays: pendingDays,
                color: accent,
                surface: accentSurface,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      worker.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasPending
                          ? 'Son ödeme: ${lastPaidEnd != null ? formatDate(lastPaidEnd) : "—"}'
                          : 'Güncel',
                      style: AppTextStyles.caption.copyWith(
                        color: hasPending
                            ? AppColors.textSecondary
                            : AppColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (hasPending)
                _NetAmount(net: net, color: accent, loading: isLoading),
              const SizedBox(width: AppSpacing.xs),
              const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeadingBadge extends StatelessWidget {
  const _LeadingBadge({
    required this.hasPending,
    required this.pendingDays,
    required this.color,
    required this.surface,
  });

  final bool hasPending;
  final int pendingDays;
  final Color color;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: hasPending
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$pendingDays',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'gün',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color,
                    height: 1,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            )
          : Icon(
              Icons.check_circle_rounded,
              size: 22,
              color: color,
            ),
    );
  }
}

class _NetAmount extends StatelessWidget {
  const _NetAmount({
    required this.net,
    required this.color,
    required this.loading,
  });

  final double net;
  final Color color;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        width: 64,
        height: 18,
        child: Center(
          child: SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      );
    }
    return Text(
      formatMoney(net),
      style: AppTextStyles.bodyStrong.copyWith(
        color: color,
        fontSize: 15,
      ),
    );
  }
}
