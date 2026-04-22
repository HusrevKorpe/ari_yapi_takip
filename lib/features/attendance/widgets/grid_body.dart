import 'package:flutter/material.dart';

import '../../../data/local/app_database.dart';
import '../../../shared/attendance_status.dart';
import 'grid_cells.dart';
import 'grid_constants.dart';

class GridBody extends StatefulWidget {
  const GridBody({
    super.key,
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
  State<GridBody> createState() => _GridBodyState();
}

class _GridBodyState extends State<GridBody> {
  late final ScrollController _leftVertical;
  late final ScrollController _rightVertical;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _leftVertical = ScrollController();
    _rightVertical = ScrollController();
    _leftVertical.addListener(_syncFromLeft);
    _rightVertical.addListener(_syncFromRight);
  }

  @override
  void dispose() {
    _leftVertical.removeListener(_syncFromLeft);
    _rightVertical.removeListener(_syncFromRight);
    _leftVertical.dispose();
    _rightVertical.dispose();
    super.dispose();
  }

  void _syncFromLeft() {
    if (_syncing || !_rightVertical.hasClients) return;
    _syncing = true;
    _rightVertical.jumpTo(_leftVertical.offset);
    _syncing = false;
  }

  void _syncFromRight() {
    if (_syncing || !_leftVertical.hasClients) return;
    _syncing = true;
    _leftVertical.jumpTo(_rightVertical.offset);
    _syncing = false;
  }

  @override
  Widget build(BuildContext context) {
    final lookup = <String, Map<int, AttendanceStatus>>{};
    for (final e in widget.entries) {
      final map = lookup.putIfAbsent(e.workerId, () => {});
      map[e.workDate.day] = AttendanceStatusX.fromCode(e.status);
    }

    final today = DateTime.now();
    final isCurrentMonth =
        widget.month.year == today.year && widget.month.month == today.month;

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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LeftPane(
            workers: widget.workers,
            lookup: lookup,
            daysInMonth: widget.daysInMonth,
            controller: _leftVertical,
          ),
          Expanded(
            child: _RightPane(
              workers: widget.workers,
              lookup: lookup,
              daysInMonth: widget.daysInMonth,
              month: widget.month,
              isCurrentMonth: isCurrentMonth,
              today: today,
              verticalController: _rightVertical,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftPane extends StatelessWidget {
  const _LeftPane({
    required this.workers,
    required this.lookup,
    required this.daysInMonth,
    required this.controller,
  });

  final List<Worker> workers;
  final Map<String, Map<int, AttendanceStatus>> lookup;
  final int daysInMonth;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kNameColWidth + kSummaryColWidth,
      child: Column(
        children: [
          const NameHeaderCell(),
          Expanded(
            child: ListView.builder(
              controller: controller,
              physics: const ClampingScrollPhysics(),
              itemCount: workers.length,
              itemExtent: kCellH,
              itemBuilder: (context, index) {
                final w = workers[index];
                return NameCell(
                  name: w.fullName,
                  workedDays: _countStatus(lookup[w.id], daysInMonth),
                  totalDays: daysInMonth,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  int _countStatus(Map<int, AttendanceStatus>? dayMap, int days) {
    if (dayMap == null) return 0;
    var count = 0;
    for (var d = 1; d <= days; d++) {
      final s = dayMap[d];
      if (s == AttendanceStatus.worked || s == AttendanceStatus.halfDay) {
        count++;
      }
    }
    return count;
  }
}

class _RightPane extends StatelessWidget {
  const _RightPane({
    required this.workers,
    required this.lookup,
    required this.daysInMonth,
    required this.month,
    required this.isCurrentMonth,
    required this.today,
    required this.verticalController,
  });

  final List<Worker> workers;
  final Map<String, Map<int, AttendanceStatus>> lookup;
  final int daysInMonth;
  final DateTime month;
  final bool isCurrentMonth;
  final DateTime today;
  final ScrollController verticalController;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: kCellW * daysInMonth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: kHeaderH,
              child: Row(
                children: List.generate(daysInMonth, (i) {
                  final day = i + 1;
                  final date = DateTime(month.year, month.month, day);
                  final isWeekend = date.weekday >= 6;
                  final isToday = isCurrentMonth && day == today.day;
                  return DayHeaderCell(
                    day: day,
                    dayName: kDayNames[date.weekday - 1],
                    isWeekend: isWeekend,
                    isToday: isToday,
                  );
                }),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: verticalController,
                physics: const ClampingScrollPhysics(),
                itemCount: workers.length,
                itemExtent: kCellH,
                itemBuilder: (context, index) {
                  final w = workers[index];
                  final workerLookup = lookup[w.id];
                  return _WorkerDayRow(
                    workerLookup: workerLookup,
                    daysInMonth: daysInMonth,
                    month: month,
                    isCurrentMonth: isCurrentMonth,
                    today: today,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkerDayRow extends StatelessWidget {
  const _WorkerDayRow({
    required this.workerLookup,
    required this.daysInMonth,
    required this.month,
    required this.isCurrentMonth,
    required this.today,
  });

  final Map<int, AttendanceStatus>? workerLookup;
  final int daysInMonth;
  final DateTime month;
  final bool isCurrentMonth;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(daysInMonth, (i) {
        final day = i + 1;
        final date = DateTime(month.year, month.month, day);
        final isWeekend = date.weekday >= 6;
        final isToday = isCurrentMonth && day == today.day;
        final status = workerLookup?[day];
        return StatusCell(
          status: status,
          isWeekend: isWeekend,
          isToday: isToday,
        );
      }),
    );
  }
}
