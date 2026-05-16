import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/ui/live_list.dart';
import '../../shared/ui/total_summary_card.dart';
import 'widgets/add_expense_sheet.dart';
import 'widgets/delete_expense_dialog.dart';
import 'widgets/expense_row_card.dart';

final allExpensesProvider = StreamProvider<List<Expense>>((ref) {
  return ref.watch(expenseRepositoryProvider).watchAll();
});

class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses = ref.watch(allExpensesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Giderler')),
      body: LiveList<Expense>(
        async: expenses,
        idOf: (e) => e.id,
        builder: (context, items, onRefresh) {
          final totalAmount = items.fold<double>(
            0,
            (sum, expense) => sum + expense.amount,
          );

          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                100,
              ),
              children: [
                TotalSummaryCard(
                  label: 'Toplam Gider',
                  amount: totalAmount,
                  icon: Icons.receipt_long_rounded,
                  accent: AppColors.danger,
                ),
                const SizedBox(height: AppSpacing.md),
                if (items.isEmpty)
                  const _EmptyState()
                else
                  ...items.map(
                    (expense) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ExpenseRowCard(
                        expense: expense,
                        accent: AppColors.danger,
                        onDelete: () => confirmDeleteExpense(
                          context,
                          ref,
                          expense: expense,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddExpenseSheet(context, ref),
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.textOnBrand,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Gider Ekle'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: const Center(
        child: Text(
          'Henüz gider kaydı yok.',
          style: AppTextStyles.body,
        ),
      ),
    );
  }
}
