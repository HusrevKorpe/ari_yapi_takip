import 'package:flutter/material.dart';

import '../../../data/local/app_database.dart';
import '../../../shared/attendance_status.dart';

class WorkerAttendanceCard extends StatelessWidget {
  const WorkerAttendanceCard({
    super.key,
    required this.worker,
    required this.selectedStatus,
    required this.selectedSiteId,
    required this.sites,
    required this.onStatusChanged,
    required this.onSiteChanged,
  });

  final Worker worker;
  final AttendanceStatus? selectedStatus;
  final String? selectedSiteId;
  final List<Site> sites;
  final ValueChanged<AttendanceStatus> onStatusChanged;
  final ValueChanged<String?> onSiteChanged;

  @override
  Widget build(BuildContext context) {
    final presentSelected = selectedStatus == AttendanceStatus.worked;
    final absentSelected = selectedStatus == AttendanceStatus.absent;
    final halfDaySelected = selectedStatus == AttendanceStatus.halfDay;
    final showSites = (presentSelected || halfDaySelected) && sites.isNotEmpty;

    final accent = presentSelected
        ? const Color(0xFF0C8A7A)
        : absentSelected
        ? const Color(0xFFC62828)
        : halfDaySelected
        ? const Color(0xFFE67E00)
        : const Color(0xFF8D8D8D);

    final subtitle = (worker.notes ?? '').trim().isEmpty
        ? 'CALISAN'
        : worker.notes!.trim().toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 2.8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E8E8),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(worker.fullName),
                    style: const TextStyle(
                      color: Color(0xFF6F6F6F),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worker.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7A7A7A),
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatusButton(
                    label: 'GELDI',
                    selected: presentSelected,
                    selectedColor: const Color(0xFF4CAF50),
                    onTap: () => onStatusChanged(AttendanceStatus.worked),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatusButton(
                    label: 'YARIM GUN',
                    selected: halfDaySelected,
                    selectedColor: const Color(0xFFE67E00),
                    selectedTextColor: Colors.white,
                    onTap: () => onStatusChanged(AttendanceStatus.halfDay),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatusButton(
                    label: 'GELMEDI',
                    selected: absentSelected,
                    selectedColor: const Color(0xFFC62828),
                    selectedTextColor: Colors.white,
                    onTap: () => onStatusChanged(AttendanceStatus.absent),
                  ),
                ),
              ],
            ),
            if (showSites) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: sites.map((site) {
                    final isSelected = selectedSiteId == site.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _SiteChip(
                        label: site.name,
                        selected: isSelected,
                        onTap: () => onSiteChanged(isSelected ? null : site.id),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '--';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _SiteChip extends StatelessWidget {
  const _SiteChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1A6B5A) : const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF666666),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
    this.selectedTextColor,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color? selectedTextColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? selectedColor : const Color(0xFFE7E7E7);
    final textColor = selected
        ? (selectedTextColor ?? const Color(0xFF444444))
        : const Color(0xFF767676);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
