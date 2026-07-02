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

  static const _accent = Color(0xFF1A6B5A);
  static const _accentMid = Color(0xFF2B8D78);
  static const _accentSoft = Color(0xFFE8F3EE);

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
        label = '${formatDate(first)} — ${formatDate(last)}';
      }
    } else {
      label = sameDay
          ? formatDayMonth(first)
          : '${formatDate(first)} — ${formatDate(last)}';
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SizeTransition(
            sizeFactor: anim,
            axis: Axis.horizontal,
            axisAlignment: -1,
            child: child,
          ),
        ),
        child: hasFilter
            ? _ActiveChip(
                key: const ValueKey('active'),
                label: label,
                count: filter.length,
                onTap: () => showSiteReportDateFilterSheet(
                  context,
                  siteId: siteId,
                  initialMonth: first,
                ),
                onClear: () => ref
                    .read(siteReportDateFilterProvider(siteId).notifier)
                    .state = null,
              )
            : _IdleChip(
                key: const ValueKey('idle'),
                label: label,
                onTap: () => showSiteReportDateFilterSheet(
                  context,
                  siteId: siteId,
                  initialMonth: DateTime.now(),
                ),
              ),
      ),
    );
  }
}

class _IdleChip extends StatelessWidget {
  const _IdleChip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: DateRangeChip._accentSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      DateRangeChip._accent,
                      DateRangeChip._accentMid,
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  size: 14,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: DateRangeChip._accent,
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(
                Icons.tune_rounded,
                size: 15,
                color: DateRangeChip._accent,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveChip extends StatelessWidget {
  const _ActiveChip({
    super.key,
    required this.label,
    required this.count,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [DateRangeChip._accent, DateRangeChip._accentMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: DateRangeChip._accent.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.event_available_rounded,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$count gün',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(width: 2),
                Material(
                  color: Colors.transparent,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: onClear,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
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
