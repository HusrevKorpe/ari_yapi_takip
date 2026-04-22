import 'package:flutter/material.dart';

import '../../../../data/local/repositories.dart';
import '../../../../shared/formatters.dart';

class ExpenseCategoryList extends StatelessWidget {
  const ExpenseCategoryList({super.key, required this.categories});

  final List<SiteExpenseCategory> categories;

  @override
  Widget build(BuildContext context) {
    final total = categories.fold<double>(0, (s, c) => s + c.total);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE8E3)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < categories.length; i++)
            _ExpenseRow(
              category: categories[i],
              isLast: i == categories.length - 1,
              total: total,
            ),
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  const _ExpenseRow({
    required this.category,
    required this.isLast,
    required this.total,
  });

  final SiteExpenseCategory category;
  final bool isLast;
  final double total;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? category.total / total : 0.0;
    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFF0EBE6), width: 1),
              ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  category.category,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
              ),
              Text(
                formatMoney(category.total),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFC04000),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: const Color(0xFFF0EBE6),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFC04000)),
            ),
          ),
        ],
      ),
    );
  }
}
