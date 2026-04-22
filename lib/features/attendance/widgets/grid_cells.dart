import 'package:flutter/material.dart';

import '../../../shared/attendance_status.dart';
import 'grid_constants.dart';

class NameHeaderCell extends StatelessWidget {
  const NameHeaderCell({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kNameColWidth + kSummaryColWidth,
      height: kHeaderH,
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F2F5),
        border: Border(
          bottom: BorderSide(color: Color(0xFFDDE0E4)),
          right: BorderSide(color: Color(0xFFDDE0E4)),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: const Row(
        children: [
          Expanded(
            child: Text(
              'Calisan',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
                letterSpacing: 0.3,
              ),
            ),
          ),
          SizedBox(
            width: kSummaryColWidth,
            child: Text(
              'Gun',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class NameCell extends StatelessWidget {
  const NameCell({
    super.key,
    required this.name,
    required this.workedDays,
    required this.totalDays,
  });

  final String name;
  final int workedDays;
  final int totalDays;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: kNameColWidth + kSummaryColWidth,
      height: kCellH,
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF0F0F2)),
          right: BorderSide(color: Color(0xFFDDE0E4)),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
              ),
            ),
          ),
          SizedBox(
            width: kSummaryColWidth,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              decoration: BoxDecoration(
                color: workedDays > 0
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                '$workedDays',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: workedDays > 0
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFBBBBBB),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DayHeaderCell extends StatelessWidget {
  const DayHeaderCell({
    super.key,
    required this.day,
    required this.dayName,
    required this.isWeekend,
    required this.isToday,
  });

  final int day;
  final String dayName;
  final bool isWeekend;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final bgColor = isToday
        ? const Color(0xFF1A6B5A).withValues(alpha: 0.12)
        : isWeekend
            ? const Color(0xFFFFF3E0)
            : const Color(0xFFF0F2F5);

    final numColor = isToday
        ? const Color(0xFF1A6B5A)
        : isWeekend
            ? const Color(0xFFBF360C)
            : const Color(0xFF374151);

    final nameColor = isToday
        ? const Color(0xFF1A6B5A)
        : isWeekend
            ? const Color(0xFFE65100)
            : const Color(0xFF9CA3AF);

    return Container(
      width: kCellW,
      height: kHeaderH,
      decoration: BoxDecoration(
        color: bgColor,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFDDE0E4)),
          right: BorderSide(color: Color(0xFFEEEFF2)),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$day',
            style: TextStyle(
              fontSize: 14,
              fontWeight: isToday ? FontWeight.w900 : FontWeight.w700,
              color: numColor,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            dayName,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: nameColor,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class StatusCell extends StatelessWidget {
  const StatusCell({
    super.key,
    required this.status,
    required this.isWeekend,
    required this.isToday,
  });

  final AttendanceStatus? status;
  final bool isWeekend;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    Color? cellBg;
    if (isToday) {
      cellBg = const Color(0xFF1A6B5A).withValues(alpha: 0.04);
    } else if (isWeekend) {
      cellBg = const Color(0xFFFFFBF5);
    }

    return Container(
      width: kCellW,
      height: kCellH,
      decoration: BoxDecoration(
        color: cellBg,
        border: const Border(
          bottom: BorderSide(color: Color(0xFFF0F0F2)),
          right: BorderSide(color: Color(0xFFEEEFF2)),
        ),
      ),
      alignment: Alignment.center,
      child: _buildIndicator(),
    );
  }

  Widget _buildIndicator() {
    if (status == null) {
      return Container(
        width: 10,
        height: 2,
        decoration: BoxDecoration(
          color: const Color(0xFFDDDDDD),
          borderRadius: BorderRadius.circular(1),
        ),
      );
    }

    final (color, icon, size) = switch (status!) {
      AttendanceStatus.worked => (kGridGreen, Icons.check_rounded, 16.0),
      AttendanceStatus.halfDay => (kGridOrange, Icons.remove_rounded, 14.0),
      AttendanceStatus.absent => (kGridRed, Icons.close_rounded, 14.0),
      AttendanceStatus.leave => (kGridBlue, Icons.pause_rounded, 14.0),
    };

    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: size, color: color),
    );
  }
}
