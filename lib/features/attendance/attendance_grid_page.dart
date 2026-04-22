import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/month_utils.dart';
import '../../shared/ui/live_list.dart';
import 'attendance_page.dart';
import 'widgets/grid_body.dart';
import 'widgets/grid_legend.dart';
import 'widgets/month_navigator.dart';

final _monthEntriesProvider =
    StreamProvider.autoDispose.family<List<AttendanceEntry>, DateTime>((
      ref,
      month,
    ) {
  return ref.watch(attendanceRepositoryProvider).watchAllEntriesInRange(
    start: monthStart(month),
    end: monthEnd(month),
  );
});

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
          MonthNavigator(
            month: _month,
            onPrev: _prevMonth,
            onNext: _nextMonth,
          ),
          Expanded(
            child: workersAsync.when(
              data: (workers) {
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
                return LiveList<AttendanceEntry>(
                  async: entriesAsync,
                  idOf: (e) =>
                      '${e.workerId}|${e.workDate.toIso8601String()}',
                  resetKey: _month,
                  builder: (context, entries, _) {
                    return GridBody(
                      workers: workers,
                      entries: entries,
                      daysInMonth: daysInMonth,
                      month: _month,
                    );
                  },
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Hata: $e')),
            ),
          ),
          const GridLegend(),
        ],
      ),
    );
  }
}
