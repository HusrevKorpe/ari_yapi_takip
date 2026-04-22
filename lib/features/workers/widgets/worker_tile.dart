import 'package:flutter/material.dart';

import '../../../data/local/app_database.dart';
import '../../../shared/formatters.dart';

const _cardBg = Color(0xFFF5F5F6);
const _accentTeal = Color(0xFF0A7E82);
const _accentGoldDark = Color(0xFF8A7300);

class WorkerTile extends StatelessWidget {
  const WorkerTile({
    super.key,
    required this.worker,
    required this.onTap,
    required this.onDelete,
  });

  final Worker worker;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 94,
              decoration: const BoxDecoration(
                color: _accentTeal,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE1E1E4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _initials(worker.fullName),
                        style: const TextStyle(
                          color: _accentGoldDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            worker.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'GUNLUK: ${formatMoney(worker.dailyWage)}',
                            style: const TextStyle(
                              color: Color(0xFF505050),
                              fontSize: 13,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete, color: Color(0xFFC81616)),
                      tooltip: 'Calisani Sil',
                      iconSize: 24,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _initials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}
