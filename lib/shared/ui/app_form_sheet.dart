import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

/// Uygulama genelinde tek tip "ekle / düzenle" alt sayfası (bottom sheet).
///
/// Form alanlarını [children] olarak ver; başlık, tutamaç (drag handle),
/// Vazgeç/Kaydet düğmeleri ve klavye boşluğu burada yönetilir. Her özellik
/// kendi [accent] rengini geçer. Hard-coded renk/ölçü yerine design token
/// kullanır; böylece tüm formlar (gider, gelir, çalışan, şantiye, ortak) aynı
/// görünür.
class AppFormSheet extends StatelessWidget {
  const AppFormSheet({
    super.key,
    required this.title,
    required this.submitLabel,
    required this.onSubmit,
    required this.children,
    this.subtitle,
    this.accent = AppColors.brand,
    this.cancelLabel = 'Vazgeç',
  });

  final String title;
  final String? subtitle;
  final Color accent;
  final String submitLabel;
  final String cancelLabel;
  final VoidCallback onSubmit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      // Klavye açıldığında sayfayı yukarı it.
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.xl),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.md,
              AppSpacing.xl,
              AppSpacing.xl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(title, style: AppTextStyles.pageTitle),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: AppTextStyles.caption),
                ],
                const SizedBox(height: AppSpacing.lg),
                ...children,
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          foregroundColor: AppColors.textSecondary,
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
                        onPressed: onSubmit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: accent,
                          foregroundColor: AppColors.textOnBrand,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        child: Text(submitLabel, style: AppTextStyles.button),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Tüm form alanları için tek tip görünüm. `focusedBorder` [accent] rengini
/// alır; geri kalan her şey design token'lardan gelir.
InputDecoration appInputDecoration({
  required String label,
  String? hint,
  Color accent = AppColors.brand,
  bool alignLabelWithHint = false,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: label,
    hintText: hint,
    alignLabelWithHint: alignLabelWithHint,
    filled: true,
    fillColor: AppColors.surface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.lg,
      vertical: AppSpacing.lg,
    ),
    border: border(AppColors.border),
    enabledBorder: border(AppColors.border),
    focusedBorder: border(accent, 1.4),
  );
}
