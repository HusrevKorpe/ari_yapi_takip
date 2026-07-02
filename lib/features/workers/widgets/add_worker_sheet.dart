import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/pay_frequency.dart';
import '../../../shared/ui/app_form_sheet.dart';

const _accent = AppColors.brand;

Future<void> showAddWorkerSheet(
  BuildContext context,
  WidgetRef ref, {
  Worker? existing,
}) {
  final isEditing = existing != null;
  final nameController = TextEditingController(text: existing?.fullName ?? '');
  final wageController = TextEditingController(
    text: existing != null ? _formatWage(existing.dailyWage) : '',
  );
  final noteController = TextEditingController(text: existing?.notes ?? '');
  var selectedFrequency = existing != null
      ? PayFrequencyX.fromCode(existing.payFrequency)
      : PayFrequency.weekly;
  var receivesBonus = existing?.receivesBonus ?? true;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (_, setSheetState) {
          return AppFormSheet(
            title: isEditing ? 'Çalışanı Düzenle' : 'Yeni Çalışan',
            submitLabel: 'Kaydet',
            accent: _accent,
            onSubmit: () async {
              final name = nameController.text.trim();
              final wage = double.tryParse(
                    wageController.text.trim().replaceAll(',', '.'),
                  ) ??
                  0;
              if (name.isEmpty || wage <= 0) return;

              await ref.read(workerRepositoryProvider).saveWorker(
                    id: existing?.id,
                    fullName: name,
                    dailyWage: wage,
                    payFrequency: selectedFrequency.code,
                    receivesBonus: receivesBonus,
                    notes: noteController.text.trim().isEmpty
                        ? null
                        : noteController.text.trim(),
                  );

              if (sheetContext.mounted) Navigator.pop(sheetContext);
            },
            children: [
              TextField(
                controller: nameController,
                decoration:
                    appInputDecoration(label: 'Ad Soyad', accent: _accent),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: wageController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration:
                    appInputDecoration(label: 'Günlük Ücret', accent: _accent),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Ödeme Periyodu',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.all(5),
                child: Row(
                  children: PayFrequency.values.map((freq) {
                    final isSelected = freq == selectedFrequency;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setSheetState(() => selectedFrequency = freq),
                        child: AnimatedContainer(
                          duration: AppDuration.normal,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          decoration: BoxDecoration(
                            color: isSelected ? _accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            freq.label,
                            style: AppTextStyles.chip.copyWith(
                              fontWeight: FontWeight.w700,
                              color: isSelected
                                  ? AppColors.textOnBrand
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: AppColors.border),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Prim Alıyor', style: AppTextStyles.bodyStrong),
                          SizedBox(height: 2),
                          Text(
                            'Kapalı ise şantiye primi 0 hesaplanır.',
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: receivesBonus,
                      activeTrackColor: _accent,
                      onChanged: (v) =>
                          setSheetState(() => receivesBonus = v),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: noteController,
                minLines: 3,
                maxLines: 4,
                decoration: appInputDecoration(
                  label: 'Not (Opsiyonel)',
                  accent: _accent,
                  alignLabelWithHint: true,
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

String _formatWage(double wage) {
  if (wage == wage.roundToDouble()) {
    return wage.toStringAsFixed(0);
  }
  return wage.toString();
}
