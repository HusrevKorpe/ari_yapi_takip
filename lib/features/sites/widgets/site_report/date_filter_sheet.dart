import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers.dart';

Future<void> showSiteReportDateFilterSheet(
  BuildContext context, {
  required String siteId,
  required DateTime initialMonth,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _DateFilterSheet(
      siteId: siteId,
      initialMonth: DateTime(initialMonth.year, initialMonth.month),
    ),
  );
}

class _DateFilterSheet extends ConsumerStatefulWidget {
  const _DateFilterSheet({required this.siteId, required this.initialMonth});

  final String siteId;
  final DateTime initialMonth;

  @override
  ConsumerState<_DateFilterSheet> createState() => _DateFilterSheetState();
}

class _DateFilterSheetState extends ConsumerState<_DateFilterSheet> {
  static const _accent = Color(0xFF1A6B5A);
  static const _accentBg = Color(0xFFDCEEE6);

  late DateTime _month;
  late Set<DateTime> _selected;

  @override
  void initState() {
    super.initState();
    _month = widget.initialMonth;
    final current = ref.read(siteReportDateFilterProvider(widget.siteId));
    _selected = current == null
        ? <DateTime>{}
        : current.map((d) => DateTime(d.year, d.month, d.day)).toSet();
  }

  void _toggleDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    setState(() {
      if (_selected.contains(normalized)) {
        _selected.remove(normalized);
      } else {
        _selected.add(normalized);
      }
    });
  }

  void _prevMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month - 1));

  void _nextMonth() =>
      setState(() => _month = DateTime(_month.year, _month.month + 1));

  void _apply() {
    final value = _selected.isEmpty ? null : Set<DateTime>.from(_selected);
    ref
        .read(siteReportDateFilterProvider(widget.siteId).notifier)
        .state = value;
    Navigator.pop(context);
  }

  void _clearAndApply() {
    ref
        .read(siteReportDateFilterProvider(widget.siteId).notifier)
        .state = null;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHandle(),
            _buildHeader(),
            const Divider(height: 1, color: Color(0xFFEAEAEA)),
            _buildMonthNav(),
            _buildWeekdayHeader(),
            _buildDayGrid(),
            const SizedBox(height: 12),
            _buildFooter(),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFD9D9D9),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    final count = _selected.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 12),
      child: Row(
        children: [
          const Icon(Icons.event_rounded, size: 18, color: _accent),
          const SizedBox(width: 8),
          const Text(
            'Tarih Seç',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF161616),
            ),
          ),
          const SizedBox(width: 10),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _accentBg,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count gün',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _accent,
                ),
              ),
            ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 22),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNav() {
    final label = DateFormat('MMMM yyyy', 'tr_TR').format(_month);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: _prevMonth,
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161616),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: _nextMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    const labels = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: i >= 5
                          ? const Color(0xFFBF360C)
                          : const Color(0xFF6B7B75),
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayGrid() {
    final firstOfMonth = DateTime(_month.year, _month.month, 1);
    final leadingBlanks = firstOfMonth.weekday - 1;
    final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
    final totalCells = ((leadingBlanks + daysInMonth + 6) ~/ 7) * 7;
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
          childAspectRatio: 1.0,
        ),
        itemCount: totalCells,
        itemBuilder: (context, index) {
          final dayOffset = index - leadingBlanks;
          if (dayOffset < 0 || dayOffset >= daysInMonth) {
            return const SizedBox.shrink();
          }
          final day = dayOffset + 1;
          final date = DateTime(_month.year, _month.month, day);
          final isSelected = _selected.contains(date);
          final isToday = date == todayKey;
          final weekday = date.weekday;
          final isWeekend =
              weekday == DateTime.saturday || weekday == DateTime.sunday;

          final Color textColor;
          final Color bgColor;
          if (isSelected) {
            textColor = Colors.white;
            bgColor = _accent;
          } else {
            textColor = isWeekend
                ? const Color(0xFFBF360C)
                : const Color(0xFF161616);
            bgColor = Colors.transparent;
          }

          return Padding(
            padding: const EdgeInsets.all(3),
            child: Material(
              color: bgColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: isToday && !isSelected
                    ? const BorderSide(color: _accent, width: 1.4)
                    : BorderSide.none,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _toggleDay(date),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.w800 : FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    final count = _selected.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Temizle'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF6B7B75),
                side: const BorderSide(color: Color(0xFFDDDDDD)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _clearAndApply,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: FilledButton.icon(
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(count == 0 ? 'Uygula' : 'Uygula ($count)'),
              style: FilledButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: _apply,
            ),
          ),
        ],
      ),
    );
  }
}
