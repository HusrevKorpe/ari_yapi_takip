import 'package:flutter/material.dart';

import '../../../data/local/repositories.dart';
import '../../../shared/attendance_status.dart';
import '../../../shared/formatters.dart';

class DayDetailExpander extends StatelessWidget {
  const DayDetailExpander({super.key, required this.days});

  final List<PayrollAttendanceDay> days;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        title: const Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 13,
              color: Color(0xFF888888),
            ),
            SizedBox(width: 6),
            Text(
              'GUNLUK DETAY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Color(0xFF888888),
              ),
            ),
          ],
        ),
        children: [for (final day in days) _DayRow(day: day)],
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final PayrollAttendanceDay day;

  @override
  Widget build(BuildContext context) {
    final isHalf = day.dayEquivalent == 0.5;
    final isOff = day.status == AttendanceStatus.absent ||
        day.status == AttendanceStatus.leave;

    Color badgeBg;
    Color badgeText;
    if (isOff) {
      badgeBg = const Color(0xFFFFE0E0);
      badgeText = const Color(0xFFB60A0A);
    } else if (isHalf) {
      badgeBg = const Color(0xFFFFF3CD);
      badgeText = const Color(0xFF856404);
    } else {
      badgeBg = const Color(0xFFEDF7F4);
      badgeText = const Color(0xFF1A6B5A);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            formatDate(day.date),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF555555),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              day.status.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: badgeText,
              ),
            ),
          ),
          const Spacer(),
          if (day.siteBonus > 0) ...[
            Text(
              '+${formatMoney(day.siteBonus)}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A6B5A),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            formatMoney(day.dailyAmount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: isOff ? const Color(0xFF999999) : const Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}
