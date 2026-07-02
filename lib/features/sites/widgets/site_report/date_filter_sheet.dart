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
    backgroundColor: Colors.transparent,
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
  static const _accentMid = Color(0xFF2B8D78);
  static const _accentSoft = Color(0xFFE8F3EE);
  static const _ink = Color(0xFF0F1F1B);
  static const _muted = Color(0xFF6B7B75);
  static const _weekend = Color(0xFFC0451B);
  static const _hairline = Color(0xFFEDEFEE);

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

  void _jumpToToday() {
    final now = DateTime.now();
    setState(() => _month = DateTime(now.year, now.month));
  }

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
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: ColoredBox(
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHandle(),
                _buildHeader(),
                const SizedBox(height: 4),
                _buildMonthNav(),
                _buildWeekdayHeader(),
                const SizedBox(height: 4),
                _buildDayGrid(),
                const SizedBox(height: 18),
                _buildFooter(),
                const SizedBox(height: 10),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      width: 38,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E6E4),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildHeader() {
    final count = _selected.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 10, 6),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_accent, _accentMid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: _accent.withValues(alpha: 0.28),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: const Icon(
              Icons.calendar_month_rounded,
              size: 20,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Tarih Seç',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                    height: 1.15,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  count == 0
                      ? 'Filtrelemek için gün seçin'
                      : '$count gün seçildi',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: count == 0 ? _muted : _accent,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 22, color: _muted),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthNav() {
    final label = DateFormat('MMMM yyyy', 'tr_TR').format(_month);
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      child: Row(
        children: [
          _navButton(Icons.chevron_left_rounded, _prevMonth),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _capitalizeWords(label),
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (!isCurrent) ...[
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: _jumpToToday,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _accentSoft,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Bugüne dön',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _accent,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _navButton(Icons.chevron_right_rounded, _nextMonth),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: const Color(0xFFF3F5F4),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 22, color: _ink),
        ),
      ),
    );
  }

  Widget _buildWeekdayHeader() {
    const labels = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: _hairline, width: 1),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: i >= 5 ? _weekend : _muted,
                    letterSpacing: 0.8,
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
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

          return _DayCell(
            day: day,
            isSelected: isSelected,
            isToday: isToday,
            isWeekend: isWeekend,
            onTap: () => _toggleDay(date),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    final count = _selected.length;
    final hasSelection = count > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 50,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Sıfırla'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _muted,
                  side: const BorderSide(color: Color(0xFFE2E6E4), width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _clearAndApply,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(
                    colors: [_accent, _accentMid],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.32),
                      blurRadius: 16,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: _apply,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_rounded,
                            size: 19,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            hasSelection ? 'Uygula ($count)' : 'Uygula',
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _capitalizeWords(String input) {
    return input
        .split(' ')
        .map((w) => w.isEmpty
            ? w
            : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isSelected,
    required this.isToday,
    required this.isWeekend,
    required this.onTap,
  });

  static const _accent = Color(0xFF1A6B5A);
  static const _accentMid = Color(0xFF2B8D78);
  static const _weekend = Color(0xFFC0451B);
  static const _ink = Color(0xFF0F1F1B);

  final int day;
  final bool isSelected;
  final bool isToday;
  final bool isWeekend;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color textColor;
    if (isSelected) {
      textColor = Colors.white;
    } else if (isToday) {
      textColor = _accent;
    } else if (isWeekend) {
      textColor = _weekend;
    } else {
      textColor = _ink;
    }

    return Padding(
      padding: const EdgeInsets.all(3),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isSelected
                ? const LinearGradient(
                    colors: [_accent, _accentMid],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: _accent.withValues(alpha: 0.32),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
            border: isToday && !isSelected
                ? Border.all(
                    color: _accent.withValues(alpha: 0.45),
                    width: 1.4,
                  )
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text(
                '$day',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: (isSelected || isToday)
                      ? FontWeight.w800
                      : FontWeight.w600,
                  color: textColor,
                ),
              ),
              if (isToday && !isSelected)
                Positioned(
                  bottom: 5,
                  child: Container(
                    width: 4,
                    height: 4,
                    decoration: const BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
