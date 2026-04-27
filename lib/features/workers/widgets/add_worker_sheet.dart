import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/pay_frequency.dart';

const _accentGoldDark = Color(0xFF8A7300);

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

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final viewInsets = MediaQuery.of(context).viewInsets.bottom;

          return Padding(
            padding: EdgeInsets.fromLTRB(12, 0, 12, viewInsets + 12),
            child: Stack(
              children: [
                Positioned(
                  top: 28,
                  right: 24,
                  child: Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: const Color(0x22D6B100),
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                ),
                Positioned(
                  top: 108,
                  left: 18,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2E4AB),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F5EC),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: const Color(0xFFE5DCC0)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: const Color(0xFFD3CAB0),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEDE1A8),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            isEditing ? 'CALISANI DUZENLE' : 'YENI CALISAN',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: Color(0xFF6D5A00),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          isEditing ? 'Calisani Duzenle' : 'Yeni Calisan',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF1E1A12),
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          isEditing
                              ? 'Bilgileri guncelleyip kaydedin.'
                              : 'Ekibe yeni kisiyi hizli ve temiz bir akista ekleyin.',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: const Color(0xFF6E6759),
                                height: 1.35,
                              ),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          controller: nameController,
                          decoration: _inputDecoration(label: 'Ad Soyad'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: wageController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: _inputDecoration(label: 'Gunluk Ucret'),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Odeme Periyodu',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: const Color(0xFF6E6759),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFCF5),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: const Color(0xFFE2D8BC),
                            ),
                          ),
                          padding: const EdgeInsets.all(5),
                          child: Row(
                            children: PayFrequency.values.map((freq) {
                              final isSelected = freq == selectedFrequency;
                              return Expanded(
                                child: GestureDetector(
                                  onTap: () {
                                    setDialogState(() {
                                      selectedFrequency = freq;
                                    });
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(
                                      milliseconds: 180,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 11,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? _accentGoldDark
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    alignment: Alignment.center,
                                    child: Text(
                                      freq.label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected
                                            ? Colors.white
                                            : const Color(0xFF5E5A50),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: noteController,
                          minLines: 3,
                          maxLines: 4,
                          decoration: _inputDecoration(
                            label: 'Not (Opsiyonel)',
                            alignLabelWithHint: true,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF5F5A50),
                                  side: const BorderSide(
                                    color: Color(0xFFD8CFB2),
                                  ),
                                  backgroundColor: const Color(0xFFFDFBF4),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: () => Navigator.pop(context),
                                child: const Text(
                                  'Vazgec',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _accentGoldDark,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                onPressed: () async {
                                  final name = nameController.text.trim();
                                  final wage =
                                      double.tryParse(
                                        wageController.text
                                            .trim()
                                            .replaceAll(',', '.'),
                                      ) ??
                                      0;
                                  if (name.isEmpty || wage <= 0) {
                                    return;
                                  }

                                  await ref
                                      .read(workerRepositoryProvider)
                                      .saveWorker(
                                        id: existing?.id,
                                        fullName: name,
                                        dailyWage: wage,
                                        payFrequency: selectedFrequency.code,
                                        notes:
                                            noteController.text.trim().isEmpty
                                            ? null
                                            : noteController.text.trim(),
                                      );

                                  if (context.mounted) {
                                    Navigator.pop(context);
                                  }
                                },
                                child: const Text(
                                  'Kaydet',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

InputDecoration _inputDecoration({
  required String label,
  bool alignLabelWithHint = false,
}) {
  return InputDecoration(
    labelText: label,
    alignLabelWithHint: alignLabelWithHint,
    filled: true,
    fillColor: const Color(0xFFFFFCF5),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFE2D8BC)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFE2D8BC)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: _accentGoldDark, width: 1.4),
    ),
  );
}

String _formatWage(double wage) {
  if (wage == wage.roundToDouble()) {
    return wage.toStringAsFixed(0);
  }
  return wage.toString();
}
