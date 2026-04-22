import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/formatters.dart';
import '../../shared/ui/live_list.dart';
import 'widgets/add_income_sheet.dart';
import 'widgets/delete_income_dialog.dart';
import 'widgets/income_row_card.dart';

final incomesMonthProvider = StateProvider<DateTime>((ref) => DateTime.now());

final incomesByMonthProvider = StreamProvider<List<Income>>((ref) {
  final month = ref.watch(incomesMonthProvider);
  return ref.watch(incomeRepositoryProvider).watchMonth(month);
});

const _pageBg = Colors.white;
const _surfaceBg = Color(0xFFF0F7F2);
const _accentGreen = Color(0xFF2E7D32);
const _accentGreenLight = Color(0xFF43A047);

const _accentPalette = <Color>[
  Color(0xFF2E7D32),
  Color(0xFF388E3C),
  Color(0xFF43A047),
  Color(0xFF0A7E82),
  Color(0xFF1B5E20),
];

class IncomesPage extends ConsumerWidget {
  const IncomesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(incomesMonthProvider);
    final incomes = ref.watch(incomesByMonthProvider);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text('Gelirler'),
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
                ref.read(incomesMonthProvider.notifier).state = picked;
              }
            },
            icon: const Icon(Icons.calendar_month),
          ),
        ],
      ),
      body: LiveList<Income>(
        async: incomes,
        idOf: (i) => i.id,
        resetKey: month,
        builder: (context, items, onRefresh) {
          final totalAmount = items.fold<double>(
            0,
            (sum, income) => sum + income.amount,
          );

          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
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
                        'Toplam Gelir',
                        style: TextStyle(
                          fontSize: 22,
                          letterSpacing: 0.6,
                          color: Color(0xFF1B4A1E),
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
                      'Bu ay icin gelir kaydi yok.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF3F3F3F),
                      ),
                    ),
                  ),
                ...items.asMap().entries.map(
                  (entry) => IncomeRowCard(
                    income: entry.value,
                    accent: _accentPalette[entry.key % _accentPalette.length],
                    onDelete: () => confirmDeleteIncome(
                      context,
                      ref,
                      income: entry.value,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_accentGreen, _accentGreenLight],
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
          onPressed: () => showAddIncomeSheet(context, ref),
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
            'GELIR EKLE',
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
}
