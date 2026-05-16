import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/ui/live_list.dart';
import '../../shared/ui/total_summary_card.dart';
import 'widgets/add_income_sheet.dart';
import 'widgets/delete_income_dialog.dart';
import 'widgets/income_row_card.dart';

final allIncomesProvider = StreamProvider<List<Income>>((ref) {
  return ref.watch(incomeRepositoryProvider).watchAll();
});

class IncomesPage extends ConsumerWidget {
  const IncomesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incomes = ref.watch(allIncomesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Gelirler')),
      body: LiveList<Income>(
        async: incomes,
        idOf: (i) => i.id,
        builder: (context, items, onRefresh) {
          final totalAmount = items.fold<double>(
            0,
            (sum, income) => sum + income.amount,
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
                  label: 'Toplam Gelir',
                  amount: totalAmount,
                  icon: Icons.trending_up_rounded,
                  accent: AppColors.success,
                ),
                const SizedBox(height: AppSpacing.md),
                if (items.isEmpty)
                  const _EmptyState()
                else
                  ...items.map(
                    (income) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: IncomeRowCard(
                        income: income,
                        accent: AppColors.success,
                        onDelete: () => confirmDeleteIncome(
                          context,
                          ref,
                          income: income,
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
        onPressed: () => showAddIncomeSheet(context, ref),
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.textOnBrand,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Gelir Ekle'),
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
          'Henüz gelir kaydı yok.',
          style: AppTextStyles.body,
        ),
      ),
    );
  }
}
