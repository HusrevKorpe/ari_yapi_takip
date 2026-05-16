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

    final accent = hasPending ? AppColors.brand : AppColors.success;

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
                  ? AppColors.brand.withValues(alpha: 0.4)
                  : AppColors.border,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  Icons.payments_rounded,
                  size: 20,
                  color: accent,
                ),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.brandSurface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$pendingDays',
                        style: AppTextStyles.bodyStrong.copyWith(
                          color: AppColors.brand,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'gün',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.brand,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppColors.success,
                  size: 20,
                ),
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
