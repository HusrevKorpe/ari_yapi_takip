import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/attendance_status.dart';

/// Bir çalışan için günlük yoklama kartı: durum seçimi (Geldi / Yarım Gün /
/// Gelmedi), 1. şantiye ve isteğe bağlı 2. şantiye.
class WorkerAttendanceCard extends StatefulWidget {
  const WorkerAttendanceCard({
    super.key,
    required this.worker,
    required this.selectedStatus,
    required this.selectedSiteId,
    required this.selectedSecondSiteId,
    required this.sites,
    required this.onStatusChanged,
    required this.onSiteChanged,
    required this.onSecondSiteChanged,
  });

  final Worker worker;
  final AttendanceStatus? selectedStatus;
  final String? selectedSiteId;
  final String? selectedSecondSiteId;
  final List<Site> sites;
  final ValueChanged<AttendanceStatus?> onStatusChanged;
  final ValueChanged<String?> onSiteChanged;
  final ValueChanged<String?> onSecondSiteChanged;

  @override
  State<WorkerAttendanceCard> createState() => _WorkerAttendanceCardState();
}

class _WorkerAttendanceCardState extends State<WorkerAttendanceCard> {
  bool _secondSiteExpanded = false;

  @override
  Widget build(BuildContext context) {
    final status = widget.selectedStatus;
    final isWorked = status == AttendanceStatus.worked;
    final isHalfDay = status == AttendanceStatus.halfDay;
    final isAbsent = status == AttendanceStatus.absent;
    final isUnset = status == null;

    final showSiteRow =
        (isWorked || isHalfDay) && widget.sites.isNotEmpty;
    final canAddSecondSite = isWorked &&
        widget.selectedSiteId != null &&
        widget.sites.length > 1;
    final hasSecondSite = widget.selectedSecondSiteId != null;
    final showSecondSiteRow =
        canAddSecondSite && (_secondSiteExpanded || hasSecondSite);

    final accent = _accentFor(status);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isUnset ? AppColors.border : accent.withValues(alpha: 0.35),
        ),
        boxShadow: AppShadows.card,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              name: widget.worker.fullName,
              initials: _initials(widget.worker.fullName),
              statusLabel: status?.label,
              accent: accent,
            ),
            const SizedBox(height: AppSpacing.md),
            _StatusSegment(
              isWorked: isWorked,
              isHalfDay: isHalfDay,
              isAbsent: isAbsent,
              onChanged: widget.onStatusChanged,
            ),
            if (showSiteRow) ...[
              const SizedBox(height: AppSpacing.md),
              _SiteSection(
                label: showSecondSiteRow ? '1. ŞANTİYE' : 'ŞANTİYE',
                sites: widget.sites,
                selectedSiteId: widget.selectedSiteId,
                onSelected: widget.onSiteChanged,
              ),
            ],
            if (canAddSecondSite && !showSecondSiteRow) ...[
              const SizedBox(height: AppSpacing.sm),
              _AddSecondSiteButton(
                onTap: () => setState(() => _secondSiteExpanded = true),
              ),
            ],
            if (showSecondSiteRow) ...[
              const SizedBox(height: AppSpacing.md),
              _SiteSection(
                label: '2. ŞANTİYE',
                sites: widget.sites
                    .where((s) => s.id != widget.selectedSiteId)
                    .toList(),
                selectedSiteId: widget.selectedSecondSiteId,
                onSelected: widget.onSecondSiteChanged,
                trailing: _RemoveSecondSiteButton(
                  onTap: () {
                    widget.onSecondSiteChanged(null);
                    setState(() => _secondSiteExpanded = false);
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

Color _accentFor(AttendanceStatus? status) {
  switch (status) {
    case AttendanceStatus.worked:
      return AppColors.success;
    case AttendanceStatus.halfDay:
      return AppColors.warning;
    case AttendanceStatus.absent:
      return AppColors.danger;
    case AttendanceStatus.leave:
      return AppColors.info;
    case null:
      return AppColors.textTertiary;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.initials,
    required this.statusLabel,
    required this.accent,
  });

  final String name;
  final String initials;
  final String? statusLabel;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Text(
            initials,
            style: AppTextStyles.cardSubtitle.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.cardTitle,
          ),
        ),
        if (statusLabel != null) ...[
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              statusLabel!,
              style: AppTextStyles.chip.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusSegment extends StatelessWidget {
  const _StatusSegment({
    required this.isWorked,
    required this.isHalfDay,
    required this.isAbsent,
    required this.onChanged,
  });

  final bool isWorked;
  final bool isHalfDay;
  final bool isAbsent;
  final ValueChanged<AttendanceStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _StatusButton(
            label: 'Geldi',
            icon: Icons.check_circle_rounded,
            selected: isWorked,
            selectedColor: AppColors.success,
            onTap: () =>
                onChanged(isWorked ? null : AttendanceStatus.worked),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatusButton(
            label: 'Yarım',
            icon: Icons.contrast_rounded,
            selected: isHalfDay,
            selectedColor: AppColors.warning,
            onTap: () =>
                onChanged(isHalfDay ? null : AttendanceStatus.halfDay),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _StatusButton(
            label: 'Gelmedi',
            icon: Icons.cancel_rounded,
            selected: isAbsent,
            selectedColor: AppColors.danger,
            onTap: () =>
                onChanged(isAbsent ? null : AttendanceStatus.absent),
          ),
        ),
      ],
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final Color selectedColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = selected ? selectedColor : AppColors.surfaceMuted;
    final fg = selected ? Colors.white : AppColors.textSecondary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTextStyles.buttonSmall.copyWith(color: fg),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SiteSection extends StatelessWidget {
  const _SiteSection({
    required this.label,
    required this.sites,
    required this.selectedSiteId,
    required this.onSelected,
    this.trailing,
  });

  final String label;
  final List<Site> sites;
  final String? selectedSiteId;
  final ValueChanged<String?> onSelected;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.sectionLabel.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.4,
                ),
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final site in sites)
              _SiteChip(
                label: site.name,
                selected: selectedSiteId == site.id,
                onTap: () => onSelected(
                  selectedSiteId == site.id ? null : site.id,
                ),
              ),
          ],
        ),
      ],
    );
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
    final bg = selected ? AppColors.brand : AppColors.surfaceMuted;
    final fg = selected ? Colors.white : AppColors.textPrimary;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 7,
          ),
          child: Text(
            label,
            style: AppTextStyles.chip.copyWith(color: fg),
          ),
        ),
      ),
    );
  }
}

class _AddSecondSiteButton extends StatelessWidget {
  const _AddSecondSiteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: AppColors.brandSurface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.brand.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.add_rounded, size: 16, color: AppColors.brand),
            const SizedBox(width: 6),
            Text(
              '2. şantiye ekle',
              style: AppTextStyles.buttonSmall.copyWith(
                color: AppColors.brand,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RemoveSecondSiteButton extends StatelessWidget {
  const _RemoveSecondSiteButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      icon: const Icon(Icons.close_rounded, size: 16),
      tooltip: '2. şantiyeyi kaldır',
      color: AppColors.textTertiary,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
    );
  }
}
