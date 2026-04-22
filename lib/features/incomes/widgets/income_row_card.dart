import 'package:flutter/material.dart';

import '../../../data/local/app_database.dart';
import '../../../shared/formatters.dart';

const _surfaceBg = Color(0xFFF0F7F2);

class IncomeRowCard extends StatelessWidget {
  const IncomeRowCard({
    super.key,
    required this.income,
    required this.accent,
    required this.onDelete,
  });

  final Income income;
  final Color accent;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _surfaceBg,
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
                income.category.toUpperCase(),
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
                  formatMoney(income.amount).replaceFirst('₺', ''),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF131313),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDate(income.incomeDate),
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
              tooltip: 'Geliri sil',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.delete_outline, color: Color(0xFFC62828)),
            ),
          ],
        ),
      ),
    );
  }
}
