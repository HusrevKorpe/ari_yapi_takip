import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/formatters.dart';

class WorkerPayrollCard extends ConsumerWidget {
  const WorkerPayrollCard({
    super.key,
    required this.worker,
    required this.onTap,
  });

  final Worker worker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastPaidEnd = ref
        .watch(lastPaymentEndProvider(worker.id))
        .valueOrNull;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final periodStart = lastPaidEnd != null
        ? DateTime(lastPaidEnd.year, lastPaidEnd.month, lastPaidEnd.day + 1)
        : DateTime(
            worker.createdAt.year,
            worker.createdAt.month,
            worker.createdAt.day,
          );

    final pendingDays = today.difference(periodStart).inDays + 1;
    final hasPending = pendingDays > 0;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasPending
                ? const Color(0xFFD9C97A)
                : const Color(0xFFDCDCDD),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasPending
                    ? const Color(0xFF8A7300).withValues(alpha: 0.12)
                    : const Color(0xFFE0E0E0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.person_outline_rounded,
                size: 22,
                color: hasPending
                    ? const Color(0xFF8A7300)
                    : const Color(0xFF999999),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    worker.fullName,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    hasPending
                        ? 'Son odeme: ${lastPaidEnd != null ? formatDate(lastPaidEnd) : "Yok"}'
                        : 'Guncel',
                    style: TextStyle(
                      fontSize: 11,
                      color: hasPending
                          ? const Color(0xFF888888)
                          : const Color(0xFF1A6B5A),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hasPending) ...[
                  Text(
                    '$pendingDays gun',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF8A7300),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'bekliyor',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF888888),
                    ),
                  ),
                ] else
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF1A6B5A),
                    size: 22,
                  ),
              ],
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: Color(0xFF999999),
            ),
          ],
        ),
      ),
    );
  }
}
