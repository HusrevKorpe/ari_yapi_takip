import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/attendance_status.dart';
import '../../../shared/formatters.dart';
import '../../../shared/payroll_calculator.dart';
import '../../../shared/wage_history.dart';
import '../../attendance/widgets/grid_constants.dart';
import '../../attendance/widgets/month_navigator.dart';

class WorkerAttendanceMonthGrid extends ConsumerStatefulWidget {
  const WorkerAttendanceMonthGrid({super.key, required this.worker});

  final Worker worker;

  @override
  ConsumerState<WorkerAttendanceMonthGrid> createState() =>
      _WorkerAttendanceMonthGridState();
}

class _WorkerAttendanceMonthGridState
    extends ConsumerState<WorkerAttendanceMonthGrid> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  void _prev() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1));
  void _next() =>
      setState(() => _month = DateTime(_month.year, _month.month + 1));

  @override
  Widget build(BuildContext context) {
    final entriesAsync = ref.watch(
      workerMonthAttendanceProvider((
        workerId: widget.worker.id,
        month: _month,
      )),
    );
    final sitesAsync = ref.watch(_workerDetailSitesProvider);
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MonthNavigator(month: _month, onPrev: _prev, onNext: _next),
        const SizedBox(height: AppSpacing.sm),
        entriesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(AppSpacing.xxl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text('Hata: $e'),
          ),
          data: (entries) {
            final siteCodes = sitesAsync.maybeWhen(
              data: (sites) => {for (final s in sites) s.id: s.code},
              orElse: () => <String, String>{},
            );
            return _MonthTable(
              month: _month,
              daysInMonth: daysInMonth,
              entries: entries,
              dailyWage: widget.worker.dailyWage,
              wageHistoryJson: widget.worker.wageHistory,
              siteCodes: siteCodes,
            );
          },
        ),
      ],
    );
  }
}

class _MonthTable extends StatelessWidget {
  const _MonthTable({
    required this.month,
    required this.daysInMonth,
    required this.entries,
    required this.dailyWage,
    required this.wageHistoryJson,
    required this.siteCodes,
  });

  final DateTime month;
  final int daysInMonth;
  final List<AttendanceEntry> entries;
  final double dailyWage;
  final String? wageHistoryJson;
  final Map<String, String> siteCodes;

  @override
  Widget build(BuildContext context) {
    final byDay = <int, AttendanceEntry>{
      for (final e in entries) e.workDate.day: e,
    };
    final today = DateTime.now();
    final isCurrentMonth = month.year == today.year && month.month == today.month;

    final workedEquiv = PayrollCalculator.workedEquivalent(
      entries.map((e) => AttendanceStatusX.fromCode(e.status)),
    );
    // Tarih bazlı yevmiye: her gün kendi günündeki ücretle toplanır ki ay
    // içinde zam olduysa kazanç doğru çıksın.
    final wages = WageHistory.decode(wageHistoryJson);
    final grossWage = entries.fold<double>(0, (sum, e) {
      final eq = PayrollCalculator.workedEquivalent(
        [AttendanceStatusX.fromCode(e.status)],
      );
      return sum + wages.wageForDate(e.workDate, dailyWage) * eq;
    });

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _HeaderRow(
                  month: month,
                  daysInMonth: daysInMonth,
                  isCurrentMonth: isCurrentMonth,
                  today: today,
                ),
                _BodyRow(
                  month: month,
                  daysInMonth: daysInMonth,
                  byDay: byDay,
                  siteCodes: siteCodes,
                  isCurrentMonth: isCurrentMonth,
                  today: today,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: const BoxDecoration(
              color: AppColors.background,
              border: Border(
                top: BorderSide(color: AppColors.border),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _SummaryItem(
                    label: 'Yevmiye',
                    value: _formatDays(workedEquiv),
                  ),
                ),
                Container(
                  width: 1,
                  height: 24,
                  color: AppColors.border,
                ),
                Expanded(
                  child: _SummaryItem(
                    label: 'Kazanç',
                    value: formatMoney(grossWage),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDays(double value) {
    if (value == value.truncateToDouble()) {
      return '${value.toInt()}';
    }
    return value.toStringAsFixed(1);
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({
    required this.month,
    required this.daysInMonth,
    required this.isCurrentMonth,
    required this.today,
  });

  final DateTime month;
  final int daysInMonth;
  final bool isCurrentMonth;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var day = 1; day <= daysInMonth; day++)
          _DayHeader(
            day: day,
            date: DateTime(month.year, month.month, day),
            isToday: isCurrentMonth && day == today.day,
          ),
      ],
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({
    required this.day,
    required this.date,
    required this.isToday,
  });

  final int day;
  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final weekday = date.weekday;
    final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;

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
            kDayNames[weekday - 1],
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

class _BodyRow extends StatelessWidget {
  const _BodyRow({
    required this.month,
    required this.daysInMonth,
    required this.byDay,
    required this.siteCodes,
    required this.isCurrentMonth,
    required this.today,
  });

  final DateTime month;
  final int daysInMonth;
  final Map<int, AttendanceEntry> byDay;
  final Map<String, String> siteCodes;
  final bool isCurrentMonth;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var day = 1; day <= daysInMonth; day++)
          _DayCell(
            entry: byDay[day],
            date: DateTime(month.year, month.month, day),
            isToday: isCurrentMonth && day == today.day,
            siteCodes: siteCodes,
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.entry,
    required this.date,
    required this.isToday,
    required this.siteCodes,
  });

  final AttendanceEntry? entry;
  final DateTime date;
  final bool isToday;
  final Map<String, String> siteCodes;

  @override
  Widget build(BuildContext context) {
    final weekday = date.weekday;
    final isWeekend = weekday == DateTime.saturday || weekday == DateTime.sunday;

    Color? cellBg;
    if (isToday) {
      cellBg = const Color(0xFF1A6B5A).withValues(alpha: 0.04);
    } else if (isWeekend) {
      cellBg = const Color(0xFFFFFBF5);
    }

    final status =
        entry != null ? AttendanceStatusX.fromCode(entry!.status) : null;

    return Tooltip(
      message: _tooltipText(status),
      preferBelow: false,
      child: Container(
        width: kCellW,
        height: kCellH + 8,
        decoration: BoxDecoration(
          color: cellBg,
          border: const Border(
            bottom: BorderSide(color: Color(0xFFF0F0F2)),
            right: BorderSide(color: Color(0xFFEEEFF2)),
          ),
        ),
        child: status == null
            ? Center(
                child: Container(
                  width: 10,
                  height: 2,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDDDDDD),
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _StatusIndicator(status: status),
                  const SizedBox(height: 2),
                  _SiteCodeLabel(
                    code: entry?.siteId == null
                        ? null
                        : siteCodes[entry!.siteId!],
                  ),
                ],
              ),
      ),
    );
  }

  String _tooltipText(AttendanceStatus? status) {
    final dateLabel = formatDate(date);
    if (status == null) return '$dateLabel\nKayıt yok';
    final siteCode = entry?.siteId != null ? siteCodes[entry!.siteId!] : null;
    final siteLine = siteCode != null ? '\nŞantiye: $siteCode' : '';
    return '$dateLabel\n${status.label}$siteLine';
  }
}

class _StatusIndicator extends StatelessWidget {
  const _StatusIndicator({required this.status});

  final AttendanceStatus status;

  @override
  Widget build(BuildContext context) {
    final (color, icon, size) = switch (status) {
      AttendanceStatus.worked => (kGridGreen, Icons.check_rounded, 14.0),
      AttendanceStatus.halfDay => (kGridOrange, Icons.remove_rounded, 12.0),
      AttendanceStatus.absent => (kGridRed, Icons.close_rounded, 12.0),
      AttendanceStatus.leave => (kGridBlue, Icons.pause_rounded, 12.0),
    };

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, size: size, color: color),
    );
  }
}

class _SiteCodeLabel extends StatelessWidget {
  const _SiteCodeLabel({required this.code});

  final String? code;

  @override
  Widget build(BuildContext context) {
    final label = (code == null || code!.isEmpty) ? '—' : code!;
    return Text(
      label,
      style: TextStyle(
        fontSize: 8,
        fontWeight: FontWeight.w700,
        color: code == null
            ? AppColors.textDisabled
            : AppColors.textSecondary,
        letterSpacing: 0.2,
      ),
      maxLines: 1,
      overflow: TextOverflow.clip,
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          value,
          style: AppTextStyles.bodyStrong.copyWith(
            color: AppColors.textPrimary,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}

final _workerDetailSitesProvider = StreamProvider.autoDispose<List<Site>>((ref) {
  return ref.watch(siteRepositoryProvider).watchActiveSites();
});
