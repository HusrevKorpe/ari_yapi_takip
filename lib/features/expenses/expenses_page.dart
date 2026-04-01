import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/formatters.dart';
import '../../shared/snackbar_helper.dart';

final expensesMonthProvider = StateProvider<DateTime>((ref) => DateTime.now());

final expensesByMonthProvider = StreamProvider<List<Expense>>((ref) {
  final month = ref.watch(expensesMonthProvider);
  return ref.watch(expenseRepositoryProvider).watchMonth(month);
});

class ExpensesPage extends ConsumerWidget {
  const ExpensesPage({super.key});
  static const _pageBg = Colors.white;
  static const _surfaceBg = Color(0xFFF4F4F5);
  static const _accentGold = Color(0xFFD6B100);
  static const _accentGoldDark = Color(0xFF8A7300);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(expensesMonthProvider);
    final expenses = ref.watch(expensesByMonthProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        title: const Text('Giderler'),
        actions: [
          IconButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime(2100),
                initialDate: month,
              );
              if (picked != null) {
                ref.read(expensesMonthProvider.notifier).state = picked;
              }
            },
            icon: const Icon(Icons.calendar_month),
          ),
        ],
      ),
      body: expenses.when(
        data: (items) {
          final totalAmount = items.fold<double>(
            0,
            (sum, expense) => sum + expense.amount,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 130),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: _surfaceBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Toplam Gider',
                      style: TextStyle(
                        fontSize: 22,
                        letterSpacing: 0.6,
                        color: Color(0xFF4F472A),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      formatMoney(totalAmount),
                      style: const TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF141414),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (items.isEmpty)
                Container(
                  decoration: BoxDecoration(
                    color: _surfaceBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(18),
                  child: const Text(
                    'Bu ay icin gider kaydi yok.',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF3F3F3F),
                    ),
                  ),
                ),
              ...items.asMap().entries.map(
                (entry) => _ExpenseRowCard(
                  expense: entry.value,
                  accent: _accentByIndex(entry.key),
                  onDelete: () =>
                      _confirmDeleteExpense(context, ref, expense: entry.value),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_accentGoldDark, _accentGold],
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 12,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: FilledButton.icon(
          onPressed: () => _showExpenseDialog(context, ref),
          style: FilledButton.styleFrom(
            minimumSize: const Size(170, 56),
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          icon: const Icon(Icons.add, size: 28),
          label: const Text(
            'GIDER EKLE',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ),
      ),
    );
  }

  Color _accentByIndex(int index) {
    const palette = <Color>[
      Color(0xFF8A7300),
      Color(0xFF8A7300),
      Color(0xFF8A7300),
      Color(0xFF0A7E82),
      Color(0xFFC62828),
    ];
    return palette[index % palette.length];
  }

  Future<void> _showExpenseDialog(BuildContext context, WidgetRef ref) async {
    final amountController = TextEditingController();
    final categoryController = TextEditingController();
    final descriptionController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
        const surfaceColor = Color(0xFFF2F2F4);
        const accentColor = _accentGold;
        const accentDarkColor = _accentGoldDark;

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCFCFCF)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Gider Ekle',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _DialogFieldContainer(
                    child: TextField(
                      controller: categoryController,
                      decoration: const InputDecoration(
                        labelText: 'Kategori',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DialogFieldContainer(
                    child: TextField(
                      controller: amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Tutar',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _DialogFieldContainer(
                    child: TextField(
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Aciklama',
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1A1A1A),
                            side: const BorderSide(color: Color(0xFFD2D2D2)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Iptal',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [accentDarkColor, accentColor],
                            ),
                          ),
                          child: FilledButton(
                            onPressed: () async {
                              final amount =
                                  double.tryParse(
                                    amountController.text.trim(),
                                  ) ??
                                  0;
                              final category = categoryController.text.trim();
                              if (amount <= 0 || category.isEmpty) {
                                return;
                              }

                              await ref
                                  .read(expenseRepositoryProvider)
                                  .addExpense(
                                    date: DateTime.now(),
                                    amount: amount,
                                    category: category,
                                    description:
                                        descriptionController.text
                                            .trim()
                                            .isEmpty
                                        ? null
                                        : descriptionController.text.trim(),
                                  );

                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: const Color(0xFF5F5200),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: const Text(
                              'Kaydet',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDeleteExpense(
    BuildContext context,
    WidgetRef ref, {
    required Expense expense,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: _surfaceBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD0D0D4)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Gideri Sil',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '"${expense.category}" giderini silmek istiyor musunuz?',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF3D3D3D),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFD2D2D2)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Iptal',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFC62828),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Sil',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    await ref
        .read(expenseRepositoryProvider)
        .deleteExpense(expenseId: expense.id);

    if (context.mounted) {
      showSuccessSnackBar(context, 'Gider silindi.');
    }
  }
}

class _DialogFieldContainer extends StatelessWidget {
  const _DialogFieldContainer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD4D4D4)),
      ),
      child: child,
    );
  }
}

class _ExpenseRowCard extends StatelessWidget {
  const _ExpenseRowCard({
    required this.expense,
    required this.accent,
    required this.onDelete,
  });

  final Expense expense;
  final Color accent;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: ExpensesPage._surfaceBg,
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: accent, width: 6)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Text(
                expense.category.toUpperCase(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF171717),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 18),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  formatMoney(expense.amount).replaceFirst('TRY ', ''),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF131313),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDate(expense.expenseDate),
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6B6B6B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: onDelete,
              tooltip: 'Gideri sil',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
            ),
          ],
        ),
      ),
    );
  }
}
