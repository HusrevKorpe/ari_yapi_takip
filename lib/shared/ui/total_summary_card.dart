import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../formatters.dart';

class TotalSummaryCard extends StatelessWidget {
  const TotalSummaryCard({
    super.key,
    required this.label,
    required this.amount,
    required this.icon,
    required this.accent,
  });

  final String label;
  final double amount;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, size: 18, color: accent),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(label, style: AppTextStyles.metricLabel),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(formatMoney(amount), style: AppTextStyles.metric),
        ],
      ),
    );
  }
}
