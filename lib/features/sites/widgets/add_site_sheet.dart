import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';

const _accent = Color(0xFF1A6B5A);

Future<void> showAddSiteSheet(BuildContext context, WidgetRef ref) {
  final nameController = TextEditingController();
  final codeController = TextEditingController();
  final bonusController = TextEditingController();

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
                  color: const Color(0x2233A186),
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
                  color: const Color(0xFFCFE6DD),
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFF2F7F4),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFD2E3DC)),
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
                          color: const Color(0xFFBFD0C9),
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
                        color: const Color(0xFFDCEEE6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'YENI SANTIYE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                          color: Color(0xFF245749),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Yeni Santiye',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF16372E),
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Santiye ya da ilceyi temiz bir kartla ekleyin.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF5E706A),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: _inputDecoration(
                        label: 'Ilce / Santiye Adi',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _inputDecoration(
                        label: 'Kisaltma (Opsiyonel)',
                        hint: 'orn: KCB',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bonusController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _inputDecoration(
                        label: 'Gunluk Prim (TL)',
                        hint: 'Merkez icin bos birakin',
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF5F6C67),
                              side: const BorderSide(
                                color: Color(0xFFD3E3DC),
                              ),
                              backgroundColor: const Color(0xFFFBFEFC),
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
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: _accent,
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
                              if (name.isEmpty) return;
                              final code = codeController.text.trim().isEmpty
                                  ? name
                                        .substring(
                                          0,
                                          name.length >= 3 ? 3 : name.length,
                                        )
                                        .toUpperCase()
                                  : codeController.text.trim().toUpperCase();
                              final bonus =
                                  double.tryParse(
                                    bonusController.text.trim(),
                                  ) ??
                                  0;

                              await ref
                                  .read(siteRepositoryProvider)
                                  .createSite(
                                    name: name,
                                    code: code,
                                    dailyBonus: bonus,
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
}

InputDecoration _inputDecoration({required String label, String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFFBFEFC),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFD3E3DC)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: Color(0xFFD3E3DC)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: const BorderSide(color: _accent, width: 1.4),
    ),
  );
}
