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

    final result = payrollAsync.valueOrNull;
    final isLoading = payrollAsync.isLoading && !payrollAsync.hasValue;
    final net = result?.net ?? 0;

    // "Bekleyen ödeme" tanımı header'daki _payrollSummaryProvider ile birebir
    // aynıdır: yalnızca net > 0. Böylece özetteki çalışan sayısı/toplam tutar ile
    // listede vurgulanan kartlar her zaman tutarlı kalır. net <= 0 olan açık
    // dönemler (ör. avans yevmiyeyi aşmış) ödeme bekletmez; net < 0 ise bilgi
    // amaçlı kırmızı, net == 0 ya da dönem kapalıysa "güncel" gösterilir.
    final hasPending = net > 0;
    final negative = net < 0;
    final showOpen = hasPending || negative;
    // Açık dönemin gün sayısını doğrudan hesap sonucundan türetiyoruz; böylece
    // header ile aynı periyot kaynağını kullanır (kart yerel periodStart tahmini
    // yapmaz).
    final pendingDays = result == null
        ? 0
        : result.periodEnd.difference(result.periodStart).inDays + 1;

    final Color accent;
    final Color accentSurface;
    if (isLoading) {
      accent = AppColors.textTertiary;
      accentSurface = AppColors.surfaceMuted;
    } else if (hasPending) {
      accent = AppColors.brand;
      accentSurface = AppColors.brandSurface;
    } else if (negative) {
      accent = AppColors.danger;
      accentSurface = AppColors.dangerLight;
    } else {
      accent = AppColors.success;
      accentSurface = AppColors.successLight;
    }

    final String subtitle;
    final Color subtitleColor;
    if (isLoading) {
      subtitle = 'Hesaplanıyor…';
      subtitleColor = AppColors.textTertiary;
    } else if (showOpen) {
      subtitle =
          'Son ödeme: ${lastPaidEnd != null ? formatDate(lastPaidEnd) : "—"}';
      subtitleColor = AppColors.textSecondary;
    } else {
      subtitle = 'Güncel';
      subtitleColor = AppColors.success;
    }

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
              color: showOpen
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
                isLoading: isLoading,
                showDays: showOpen,
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
                      subtitle,
                      style: AppTextStyles.caption.copyWith(
                        color: subtitleColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              if (isLoading || showOpen)
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
    required this.isLoading,
    required this.showDays,
    required this.pendingDays,
    required this.color,
    required this.surface,
  });

  final bool isLoading;
  final bool showDays;
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
      child: _buildContent(),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      );
    }
    if (showDays) {
      return Column(
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
      );
    }
    return Icon(
      Icons.check_circle_rounded,
      size: 22,
      color: color,
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
