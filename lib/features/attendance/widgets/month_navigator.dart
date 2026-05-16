import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../shared/formatters.dart';

class MonthNavigator extends StatelessWidget {
  const MonthNavigator({
    super.key,
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          _NavButton(
            icon: Icons.chevron_left_rounded,
            onTap: onPrev,
          ),
          Expanded(
            child: Center(
              child: Text(
                formatMonth(month),
                style: AppTextStyles.cardTitle,
              ),
            ),
          ),
          _NavButton(
            icon: Icons.chevron_right_rounded,
            onTap: onNext,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 24, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}
