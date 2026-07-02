import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/ui/app_form_sheet.dart';

const _accent = AppColors.success;

Future<void> showAddIncomeSheet(
  BuildContext context,
  WidgetRef ref, {
  Income? existing,
}) {
  final isEdit = existing != null;
  final amountController = TextEditingController(
    text: isEdit ? existing.amount.toStringAsFixed(0) : '',
  );
  final categoryController = TextEditingController(
    text: isEdit ? existing.category : '',
  );
  final descriptionController = TextEditingController(
    text: isEdit ? (existing.description ?? '') : '',
  );

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => AppFormSheet(
      title: isEdit ? 'Geliri Düzenle' : 'Gelir Ekle',
      submitLabel: isEdit ? 'Güncelle' : 'Kaydet',
      accent: _accent,
      onSubmit: () async {
        final amount = double.tryParse(
              amountController.text.trim().replaceAll(',', '.'),
            ) ??
            0;
        final category = categoryController.text.trim();
        if (amount <= 0 || category.isEmpty) return;
        final description = descriptionController.text.trim().isEmpty
            ? null
            : descriptionController.text.trim();

        final repo = ref.read(incomeRepositoryProvider);
        if (existing != null) {
          await repo.updateIncome(
            incomeId: existing.id,
            date: existing.incomeDate,
            amount: amount,
            category: category,
            siteId: existing.siteId,
            description: description,
          );
        } else {
          await repo.addIncome(
            date: DateTime.now(),
            amount: amount,
            category: category,
            description: description,
          );
        }

        if (sheetContext.mounted) Navigator.pop(sheetContext);
      },
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: TextField(
                controller: categoryController,
                textInputAction: TextInputAction.next,
                decoration: appInputDecoration(label: 'Kategori', accent: _accent),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              flex: 4,
              child: TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.next,
                decoration: appInputDecoration(label: 'Tutar', accent: _accent),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: descriptionController,
          minLines: 3,
          maxLines: 4,
          decoration: appInputDecoration(
            label: 'Not düşmek istersen',
            accent: _accent,
            alignLabelWithHint: true,
          ),
        ),
      ],
    ),
  );
}
