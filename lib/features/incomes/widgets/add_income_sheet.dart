import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

Future<void> showAddIncomeSheet(BuildContext context, WidgetRef ref) {
  final amountController = TextEditingController();
  final categoryController = TextEditingController();
  final descriptionController = TextEditingController();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
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
                  color: const Color(0x222E7D32),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
            Positioned(
              top: 104,
              left: 18,
              child: Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFFB8D8B8),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF3F9F3),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFC2D9C2)),
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
                          color: const Color(0xFFB0CAB0),
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
                        color: const Color(0xFFC8E6C9),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'YENI KAYIT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: Color(0xFF1B5E20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Gelir Ekle',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1A2E1A),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kisa, temiz ve hizli bir kayit alani.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF4E6750),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 6,
                          child: TextField(
                            controller: categoryController,
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(label: 'Kategori'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 4,
                          child: TextField(
                            controller: amountController,
                            keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                            textInputAction: TextInputAction.next,
                            decoration: _inputDecoration(label: 'Tutar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descriptionController,
                      minLines: 3,
                      maxLines: 4,
                      decoration: _inputDecoration(
                        label: 'Not dusmek istersen',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF4E5A50),
                              side: const BorderSide(
                                color: Color(0xFFB8D0B8),
                              ),
                              backgroundColor: const Color(0xFFFAFDFA),
                              padding: const EdgeInsets.symmetric(
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: const Text(
                              'Vazgec',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              final amount =
                                  double.tryParse(
                                    amountController.text.trim(),
                                  ) ??
                                  0;
                              final category = categoryController.text.trim();
                              if (amount <= 0 || category.isEmpty) {
                                return;
                              }

                              await ref
                                  .read(incomeRepositoryProvider)
                                  .addIncome(
                                    date: DateTime.now(),
                                    amount: amount,
                                    category: category,
                                    description:
                                        descriptionController.text
                                                .trim()
                                                .isEmpty
                                            ? null
                                            : descriptionController.text.trim(),
                                  );

                              if (context.mounted) {
                                Navigator.pop(context);
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF1F4037),
                              foregroundColor: const Color(0xFFF0F7F0),
                              padding: const EdgeInsets.symmetric(
                                vertical: 15,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
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
}

InputDecoration _inputDecoration({
  required String label,
  bool alignLabelWithHint = false,
}) {
  return InputDecoration(
    labelText: label,
    alignLabelWithHint: alignLabelWithHint,
    filled: true,
    fillColor: const Color(0xFFF8FDF8),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFB8D8B8)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFB8D8B8)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFF43A047), width: 1.4),
    ),
  );
}
