import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers.dart';
import '../../../../data/local/repositories.dart';
import '../../../../shared/formatters.dart';
import 'date_filter_sheet.dart';

class DateRangeChip extends ConsumerWidget {
  const DateRangeChip({
    super.key,
    required this.siteId,
    required this.first,
    required this.last,
  });

  final String siteId;
  final DateTime first;
  final DateTime last;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(siteReportDateFilterProvider(siteId));
    final hasFilter = filter != null && filter.isNotEmpty;

    final sameDay = first.year == last.year &&
        first.month == last.month &&
        first.day == last.day;
    final String label;
    if (hasFilter) {
      final count = filter.length;
      if (count == 1) {
        label = formatDayMonth(first);
      } else {
        label = '$count gün • ${formatDate(first)} — ${formatDate(last)}';
      }
    } else {
      label = sameDay
          ? formatDayMonth(first)
          : '${formatDate(first)} — ${formatDate(last)}';
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: const Color(0xFFDCEEE6),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showSiteReportDateFilterSheet(
            context,
            siteId: siteId,
            initialMonth: hasFilter ? first : DateTime.now(),
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 8, hasFilter ? 4 : 12, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: Color(0xFF1A6B5A),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A6B5A),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  hasFilter
                      ? Icons.expand_more_rounded
                      : Icons.tune_rounded,
                  size: 16,
                  color: const Color(0xFF1A6B5A),
                ),
                if (hasFilter)
                  InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () => ref
                        .read(siteReportDateFilterProvider(siteId).notifier)
                        .state = null,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Color(0xFF1A6B5A),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.report});

  final SiteReportData report;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'Toplam\nYevmiye',
            amount: report.totalWages,
            color: const Color(0xFF1A6B5A),
            bgColor: const Color(0xFFDCEEE6),
            icon: Icons.people_alt_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            label: 'Toplam\nGider',
            amount: report.totalExpenses,
            color: const Color(0xFFC04000),
            bgColor: const Color(0xFFFFF0E6),
            icon: Icons.receipt_long_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            label: 'Genel\nToplam',
            amount: report.grandTotal,
            color: const Color(0xFF1A3A6B),
            bgColor: const Color(0xFFE6ECF8),
            icon: Icons.summarize_rounded,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  final String label;
  final double amount;
  final Color color;
  final Color bgColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatMoney(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF1A6B5A)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A6B5A),
            letterSpacing: 0.4,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF888888),
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

class TotalRow extends StatelessWidget {
  const TotalRow({
    super.key,
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            formatMoney(amount),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
