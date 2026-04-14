import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/attendance_status.dart';
import '../../shared/formatters.dart';
import '../../shared/month_utils.dart';
import 'attendance_page.dart';

// ---------------------------------------------------------------------------
// Provider: all attendance entries for a month
// ---------------------------------------------------------------------------

final _monthEntriesProvider =
    StreamProvider.family<List<AttendanceEntry>, DateTime>((ref, month) {
  return ref.watch(attendanceRepositoryProvider).watchAllEntriesInRange(
    start: monthStart(month),
    end: monthEnd(month),
  );
});

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const _nameColWidth = 110.0;
const _summaryColWidth = 44.0;
const _cellW = 38.0;
const _cellH = 40.0;
const _headerH = 52.0;

const _kGreen = Color(0xFF2E7D32);
const _kOrange = Color(0xFFE65100);
const _kRed = Color(0xFFC62828);
const _kBlue = Color(0xFF1565C0);

const _dayNames = ['Pzt', 'Sal', 'Car', 'Per', 'Cum', 'Cmt', 'Paz'];

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

class AttendanceGridPage extends ConsumerStatefulWidget {
  const AttendanceGridPage({super.key});

  @override
  ConsumerState<AttendanceGridPage> createState() => _AttendanceGridPageState();
}

class _AttendanceGridPageState extends ConsumerState<AttendanceGridPage> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _prevMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1));

  void _nextMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month + 1));

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(attendanceWorkersProvider);
    final entriesAsync = ref.watch(_monthEntriesProvider(_month));
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7F9),
      appBar: AppBar(
        title: const Text('Yoklama Cizelgesi'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          _MonthNavigator(
            month: _month,
            onPrev: _prevMonth,
            onNext: _nextMonth,
          ),
          Expanded(
            child: workersAsync.when(
              data: (workers) => entriesAsync.when(
                data: (entries) {
                  if (workers.isEmpty) {
                    return const Center(
                      child: Text(
                        'Calisan bulunamadi.',
                        style: TextStyle(
                          color: Color(0xFF999999),
                          fontSize: 14,
                        ),
                      ),
                    );
                  }
                  return _GridBody(
                    workers: workers,
                    entries: entries,
                    daysInMonth: daysInMonth,
                    month: _month,
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Hata: $e')),
              ),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
            ),
          ),
          const _Legend(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Month navigator
// ---------------------------------------------------------------------------

class _MonthNavigator extends StatelessWidget {
  const _MonthNavigator({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: const Color(0xFF1A6B5A),
            splashRadius: 20,
          ),
          Expanded(
            child: Text(
              formatMonth(month),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded, size: 28),
            color: const Color(0xFF1A6B5A),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grid body — handles the table with fixed name col + scrollable days
// ---------------------------------------------------------------------------

class _GridBody extends StatelessWidget {
  const _GridBody({
    required this.workers,
    required this.entries,
    required this.daysInMonth,
    required this.month,
  });

  final List<Worker> workers;
  final List<AttendanceEntry> entries;
  final int daysInMonth;
  final DateTime month;

  @override
  Widget build(BuildContext context) {
    // Build lookup: workerId → (day → status)
    final lookup = <String, Map<int, AttendanceStatus>>{};
    for (final e in entries) {
      final map = lookup.putIfAbsent(e.workerId, () => {});
      map[e.workDate.day] = AttendanceStatusX.fromCode(e.status);
    }

    final today = DateTime.now();
    final isCurrentMonth =
        month.year == today.year && month.month == today.month;

    final verticalScroll = ScrollController();
    final horizontalScroll = ScrollController();

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        controller: verticalScroll,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fixed left: name + summary ──
            Column(
              children: [
                _NameHeaderCell(),
                for (final w in workers)
                  _NameCell(
                    name: w.fullName,
                    workedDays: _countStatus(lookup[w.id], daysInMonth),
                    totalDays: daysInMonth,
                  ),
              ],
            ),
            // ── Scrollable day columns ──
            Expanded(
              child: SingleChildScrollView(
                controller: horizontalScroll,
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Day headers
                    Row(
                      children: List.generate(daysInMonth, (i) {
                        final day = i + 1;
                        final date = DateTime(month.year, month.month, day);
                        final isWeekend = date.weekday >= 6;
                        final isToday = isCurrentMonth && day == today.day;

                        return _DayHeaderCell(
                          day: day,
                          dayName: _dayNames[date.weekday - 1],
                          isWeekend: isWeekend,
                          isToday: isToday,
                        );
                      }),
                    ),
                    // Worker rows
                    for (final w in workers)
                      Row(
                        children: List.generate(daysInMonth, (i) {
                          final day = i + 1;
                          final date = DateTime(month.year, month.month, day);
                          final isWeekend = date.weekday >= 6;
                          final isToday = isCurrentMonth && day == today.day;
                          final status = lookup[w.id]?[day];

                          return _StatusCell(
                            status: status,
                            isWeekend: isWeekend,
                            isToday: isToday,
                          );
                        }),
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

  int _countStatus(Map<int, AttendanceStatus>? dayMap, int days) {
    if (dayMap == null) return 0;
    var count = 0;
    for (var d = 1; d <= days; d++) {
      final s = dayMap[d];
      if (s == AttendanceStatus.worked) {
        count++;
      } else if (s == AttendanceStatus.halfDay) {
        count++; // count half days too for simplicity
      }
    }
    return count;
  }
}

// ---------------------------------------------------------------------------
// Fixed name column cells
// ---------------------------------------------------------------------------

class _NameHeaderCell extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: _nameColWidth + _summaryColWidth,
      height: _headerH,
      padding: const EdgeInsets.only(left: 12),
      decoration: const BoxDecoration(
        color: Color(0xFFF0F2F5),
        border: Border(
          bottom: BorderSide(color: Color(0xFFDDE0E4)),
          right: BorderSide(color: Color(0xFFDDE0E4)),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const Expanded(
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
            width: _summaryColWidth,
            child: const Text(
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

class _NameCell extends StatelessWidget {
  const _NameCell({
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
      width: _nameColWidth + _summaryColWidth,
      height: _cellH,
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
            width: _summaryColWidth,
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

// ---------------------------------------------------------------------------
// Day header cell — shows day number + abbreviated day name
// ---------------------------------------------------------------------------

class _DayHeaderCell extends StatelessWidget {
  const _DayHeaderCell({
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
      width: _cellW,
      height: _headerH,
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

// ---------------------------------------------------------------------------
// Status cell — colored fill instead of a dot
// ---------------------------------------------------------------------------

class _StatusCell extends StatelessWidget {
  const _StatusCell({
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
      width: _cellW,
      height: _cellH,
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
      // No record — subtle dash
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
      AttendanceStatus.worked => (
          _kGreen,
          Icons.check_rounded,
          16.0,
        ),
      AttendanceStatus.halfDay => (
          _kOrange,
          Icons.remove_rounded,
          14.0,
        ),
      AttendanceStatus.absent => (
          _kRed,
          Icons.close_rounded,
          14.0,
        ),
      AttendanceStatus.leave => (
          _kBlue,
          Icons.pause_rounded,
          14.0,
        ),
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

// ---------------------------------------------------------------------------
// Legend
// ---------------------------------------------------------------------------

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    const items = [
      (color: _kGreen, icon: Icons.check_rounded, label: 'Calisti'),
      (color: _kOrange, icon: Icons.remove_rounded, label: 'Yarim'),
      (color: _kRed, icon: Icons.close_rounded, label: 'Gelmedi'),
      (color: _kBlue, icon: Icons.pause_rounded, label: 'Izinli'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E8EA))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final item in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(item.icon, size: 12, color: item.color),
                ),
                const SizedBox(width: 5),
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
