import 'package:flutter/material.dart';

import '../../../app/design_tokens.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/formatters.dart';

class WorkerTile extends StatelessWidget {
  const WorkerTile({
    super.key,
    required this.worker,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Worker worker;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              _Avatar(initials: _initials(worker.fullName)),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      worker.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: 14,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${formatMoney(worker.dailyWage)} / gün',
                          style: AppTextStyles.caption.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (worker.receivesBonus) ...[
                          const SizedBox(width: AppSpacing.sm),
                          const _DotSeparator(),
                          const SizedBox(width: AppSpacing.sm),
                          _BonusChip(),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_WorkerAction>(
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
                    case _WorkerAction.edit:
                      onEdit();
                    case _WorkerAction.delete:
                      onDelete();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: _WorkerAction.edit,
                    child: _MenuRow(
                      icon: Icons.edit_outlined,
                      label: 'Düzenle',
                    ),
                  ),
                  PopupMenuItem(
                    value: _WorkerAction.delete,
                    child: _MenuRow(
                      icon: Icons.delete_outline_rounded,
                      label: 'Sil',
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

  String _initials(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      return '?';
    }
    if (parts.length == 1) {
      return parts.first.characters.first.toUpperCase();
    }
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brandSurface, Color(0xFFFCEFB3)],
        ),
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.18)),
      ),
      child: Text(
        initials,
        style: AppTextStyles.bodyStrong.copyWith(
          color: AppColors.brandDark,
          fontSize: 15,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _BonusChip extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.brandSurface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        'Prim',
        style: AppTextStyles.caption.copyWith(
          color: AppColors.brandDark,
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _DotSeparator extends StatelessWidget {
  const _DotSeparator();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3,
      height: 3,
      decoration: const BoxDecoration(
        color: AppColors.textTertiary,
        shape: BoxShape.circle,
      ),
    );
  }
}

enum _WorkerAction { edit, delete }

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
