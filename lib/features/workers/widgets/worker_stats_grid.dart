import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/providers.dart';
import '../../../shared/formatters.dart';

class WorkerStatsGrid extends ConsumerWidget {
  const WorkerStatsGrid({super.key, required this.workerId});

  final String workerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(workerLifetimeStatsProvider(workerId));

    return statsAsync.when(
      loading: () => const _StatsSkeleton(),
      error: (e, _) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.dangerLight,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          'İstatistikler yüklenemedi: $e',
          style: AppTextStyles.caption.copyWith(color: AppColors.danger),
        ),
      ),
      data: (stats) => _StatsContent(
        workedDays: stats.workedDayEquivalent,
        advances: stats.totalAdvances,
        paid: stats.totalPaid,
      ),
    );
  }
}

class _StatsContent extends StatelessWidget {
  const _StatsContent({
    required this.workedDays,
    required this.advances,
    required this.paid,
  });

  final double workedDays;
  final double advances;
  final double paid;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.calendar_month_rounded,
                tint: AppColors.brand,
                tintBg: AppColors.brandSurface,
                label: 'Toplam Yevmiye',
                value: _formatDays(workedDays),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _StatCard(
                icon: Icons.check_circle_outline_rounded,
                tint: AppColors.success,
                tintBg: AppColors.successLight,
                label: 'Ödenmiş Maaş',
                value: formatMoney(paid),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _StatCard(
          icon: Icons.arrow_downward_rounded,
          tint: AppColors.warning,
          tintBg: AppColors.warningLight,
          label: 'Toplam Avans',
          value: formatMoney(advances),
        ),
      ],
    );
  }

  String _formatDays(double value) {
    if (value == value.truncateToDouble()) {
      return '${value.toInt()} gün';
    }
    return '${value.toStringAsFixed(1)} gün';
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.tint,
    required this.tintBg,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color tint;
  final Color tintBg;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: tintBg,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 16, color: tint),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget box() => Container(
          height: 78,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        );
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: box()),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: box()),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: box()),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: box()),
          ],
        ),
      ],
    );
  }
}
