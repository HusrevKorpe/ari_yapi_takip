import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/formatters.dart';

class SiteTile extends StatelessWidget {
  const SiteTile({
    super.key,
    required this.site,
    required this.onDelete,
    required this.onEditBonus,
    required this.onReport,
    required this.onNotes,
  });

  final Site site;
  final VoidCallback onDelete;
  final VoidCallback onEditBonus;
  final VoidCallback onReport;
  final VoidCallback onNotes;

  @override
  Widget build(BuildContext context) {
    final hasBonus = site.dailyBonus > 0;

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onReport,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.infoLight,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  site.code,
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: AppColors.info,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle,
                    ),
                    if (hasBonus) ...[
                      const SizedBox(height: 2),
                      Text(
                        '+${formatMoney(site.dailyBonus)} / gün prim',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.info,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onNotes,
                icon: const Icon(Icons.sticky_note_2_outlined, size: 20),
                tooltip: 'Notlar',
                color: AppColors.textSecondary,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(
                  minWidth: 36,
                  minHeight: 36,
                ),
              ),
              PopupMenuButton<_SiteAction>(
                tooltip: 'Daha fazla',
                color: Colors.white,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: const BorderSide(color: AppColors.border),
                ),
                icon: const Icon(
                  Icons.more_vert_rounded,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
                onSelected: (action) {
                  switch (action) {
                    case _SiteAction.report:
                      onReport();
                    case _SiteAction.editBonus:
                      onEditBonus();
                    case _SiteAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _SiteAction.report,
                    child: _MenuRow(
                      icon: Icons.bar_chart_rounded,
                      label: 'Raporu Aç',
                    ),
                  ),
                  PopupMenuItem(
                    value: _SiteAction.editBonus,
                    child: _MenuRow(
                      icon: Icons.edit_outlined,
                      label: 'Primi Düzenle',
                    ),
                  ),
                  PopupMenuItem(
                    value: _SiteAction.delete,
                    child: _MenuRow(
                      icon: Icons.delete_outline_rounded,
                      label: 'Şantiyeyi Sil',
                      destructive: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _SiteAction { report, editBonus, delete }

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? AppColors.danger : AppColors.textPrimary;
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: AppSpacing.sm),
        Text(label, style: AppTextStyles.body.copyWith(color: color)),
      ],
    );
  }
}
