import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/repositories.dart';
import '../../../shared/formatters.dart';

class WorkerHeaderCard extends ConsumerWidget {
  const WorkerHeaderCard({super.key, required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payrollAsync = ref.watch(workerPayrollProvider(worker));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(initials: _initials(worker.fullName)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      worker.fullName,
                      style: AppTextStyles.cardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.payments_outlined,
                          size: 14,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${formatMoney(worker.dailyWage)} / gün',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (worker.receivesBonus) ...[
                          const SizedBox(width: AppSpacing.sm),
                          const _BonusChip(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _BalanceBadge(payrollAsync: payrollAsync),
        ],
      ),
    );
  }

  String _initials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandSurface, Color(0xFFFCEFB3)],
        ),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.18)),
      ),
      child: Text(
        initials,
        style: AppTextStyles.bodyStrong.copyWith(
          color: AppColors.brandDark,
          fontSize: 17,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _BonusChip extends StatelessWidget {
  const _BonusChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Prim',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.brandDark,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _BalanceBadge extends StatelessWidget {
  const _BalanceBadge({required this.payrollAsync});

  final AsyncValue<PayrollResult?> payrollAsync;

  @override
  Widget build(BuildContext context) {
    return payrollAsync.when(
      loading: () => _shell(
        bg: AppColors.surfaceMuted,
        fg: AppColors.textSecondary,
        label: 'Hesaplanıyor...',
        amount: null,
      ),
      error: (_, _) => _shell(
        bg: AppColors.dangerLight,
        fg: AppColors.danger,
        label: 'Hesaplama hatası',
        amount: null,
      ),
      data: (result) {
        if (result == null) {
          return _shell(
            bg: AppColors.successLight,
            fg: AppColors.success,
            label: 'Açık dönem yok',
            amount: null,
          );
        }
        final net = result.net;
        if (net > 0) {
          return _shell(
            bg: AppColors.successLight,
            fg: AppColors.success,
            label: 'Alacağı',
            amount: net,
          );
        }
        if (net < 0) {
          return _shell(
            bg: AppColors.dangerLight,
            fg: AppColors.danger,
            label: 'Vereceği',
            amount: -net,
          );
        }
        return _shell(
          bg: AppColors.surfaceMuted,
          fg: AppColors.textSecondary,
          label: 'Mevcut dönem',
          amount: 0,
        );
      },
    );
  }

  Widget _shell({
    required Color bg,
    required Color fg,
    required String label,
    required double? amount,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          if (amount != null)
            Text(
              formatMoney(amount),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: fg,
                letterSpacing: -0.2,
              ),
            ),
        ],
      ),
    );
  }
}
