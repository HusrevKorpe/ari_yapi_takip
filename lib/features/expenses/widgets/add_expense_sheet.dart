import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

Future<void> showAddExpenseSheet(BuildContext context, WidgetRef ref) {
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
                  color: const Color(0x22D6B100),
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
                  color: const Color(0xFFEEE4B8),
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
                      child: const Text(
                        'YENI KAYIT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: Color(0xFF6D5A00),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Gider Ekle',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF1E1A12),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kisa, temiz ve hizli bir kayit alani.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF6E6759),
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
                                  .read(expenseRepositoryProvider)
                                  .addExpense(
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
                              foregroundColor: const Color(0xFFF7F2E7),
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
      borderSide: const BorderSide(color: Color(0xFFB89B29), width: 1.4),
    ),
  );
}
