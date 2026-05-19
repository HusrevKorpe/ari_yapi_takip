import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/formatters.dart';

class ExpenseRowCard extends StatelessWidget {
  const ExpenseRowCard({
    super.key,
    required this.expense,
    required this.accent,
    required this.onEdit,
    required this.onDelete,
  });

  final Expense expense;
  final Color accent;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              Icons.receipt_long_rounded,
              size: 18,
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
                  expense.category,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.cardTitle.copyWith(fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDate(expense.expenseDate),
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            formatMoney(expense.amount),
            style: AppTextStyles.bodyStrong.copyWith(
              fontSize: 16,
              color: accent,
            ),
          ),
          IconButton(
            onPressed: onEdit,
            tooltip: 'Gideri düzenle',
            icon: const Icon(Icons.edit_outlined, size: 20),
            color: AppColors.textTertiary,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            onPressed: onDelete,
            tooltip: 'Gideri sil',
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: AppColors.textTertiary,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
