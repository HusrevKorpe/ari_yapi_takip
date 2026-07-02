import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/providers.dart';
import '../../../shared/ui/app_form_sheet.dart';

const _accent = AppColors.info;

Future<void> showAddSiteSheet(BuildContext context, WidgetRef ref) {
  final nameController = TextEditingController();
  final codeController = TextEditingController();
  final bonusController = TextEditingController();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AppFormSheet(
      title: 'Yeni Şantiye',
      submitLabel: 'Kaydet',
      accent: _accent,
      onSubmit: () async {
        final name = nameController.text.trim();
        if (name.isEmpty) return;
        final code = codeController.text.trim().isEmpty
            ? name
                .substring(0, name.length >= 3 ? 3 : name.length)
                .toUpperCase()
            : codeController.text.trim().toUpperCase();
        final bonus = double.tryParse(bonusController.text.trim()) ?? 0;

        await ref.read(siteRepositoryProvider).createSite(
              name: name,
              code: code,
              dailyBonus: bonus,
            );

        if (sheetContext.mounted) Navigator.pop(sheetContext);
      },
      children: [
        TextField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          decoration: appInputDecoration(
            label: 'İlçe / Şantiye Adı',
            accent: _accent,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: codeController,
          textCapitalization: TextCapitalization.characters,
          decoration: appInputDecoration(
            label: 'Kısaltma (Opsiyonel)',
            hint: 'örn: KCB',
            accent: _accent,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: bonusController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: appInputDecoration(
            label: 'Günlük Prim (TL)',
            hint: 'Merkez için boş bırakın',
            accent: _accent,
          ),
        ),
      ],
    ),
  );
}
