import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';
import '../formatters.dart';

/// Uygulama genelinde tek tip onay penceresi (silme vb.).
///
/// `true` dönerse kullanıcı onayladı. İsteğe bağlı [detailTitle]/[detailAmount]/
/// [detailNote] verilirse mesajın üstünde küçük bir özet kartı gösterir. Silme
/// akışları için varsayılan [accent] `AppColors.danger` (kırmızı) — böylece
/// yıkıcı işlem net görünür.
Future<bool> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Sil',
  String cancelLabel = 'İptal',
  Color accent = AppColors.danger,
  IconData icon = Icons.delete_outline_rounded,
  String? detailTitle,
  double? detailAmount,
  String? detailNote,
}) async {
  final hasDetail = detailTitle != null ||
      detailAmount != null ||
      (detailNote != null && detailNote.trim().isNotEmpty);

  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: AppColors.background,
        insetPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Icon(icon, color: accent, size: 22),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(title, style: AppTextStyles.cardTitle),
                  ),
                ],
              ),
              if (hasDetail) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (detailTitle != null)
                        Text(detailTitle, style: AppTextStyles.bodyStrong),
                      if (detailAmount != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          formatMoney(detailAmount),
                          style: AppTextStyles.bodyStrong.copyWith(color: accent),
                        ),
                      ],
                      if (detailNote != null &&
                          detailNote.trim().isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        Text(detailNote.trim(), style: AppTextStyles.caption),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                message,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: Text(cancelLabel, style: AppTextStyles.button),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                        backgroundColor: accent,
                        foregroundColor: AppColors.textOnBrand,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      child: Text(confirmLabel, style: AppTextStyles.button),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );

  return result ?? false;
}
