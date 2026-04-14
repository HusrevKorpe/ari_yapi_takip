import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/formatters.dart';
import '../../shared/pay_frequency.dart';
import '../../shared/snackbar_helper.dart';
import 'worker_detail_sheet.dart';

final workersProvider = StreamProvider<List<Worker>>((ref) {
  return ref.watch(workerRepositoryProvider).watchActiveWorkers();
});

class WorkersPage extends ConsumerWidget {
  const WorkersPage({super.key});
  static const _cardBg = Color(0xFFF5F5F6);
  static const _accentTeal = Color(0xFF0A7E82);
  static const _accentGold = Color(0xFFD6B100);
  static const _accentGoldDark = Color(0xFF8A7300);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            Text(
              'Calisan Yonetimi',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161616),
              ),
            ),
            SizedBox(width: 10),
            Icon(Icons.groups_2_rounded, color: _accentGoldDark, size: 26),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_accentGoldDark, _accentGold],
                ),
              ),
              child: FilledButton.icon(
                onPressed: () => _showWorkerDialog(context, ref),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: const Color(0xFF171717),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Ekle',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
      body: workers.when(
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('Henuz calisan eklenmedi.'));
          }

          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YONETIM PANELI',
                        style: TextStyle(
                          color: _accentGoldDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 28 / 2,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final worker = items[index];
                      return _WorkerTile(
                        worker: worker,
                        onTap: () => _showWorkerDetail(context, worker),
                        onDelete: () =>
                            _confirmDeleteWorker(context, ref, worker),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }

  Future<void> _showWorkerDialog(BuildContext context, WidgetRef ref) async {
    final nameController = TextEditingController();
    final wageController = TextEditingController();
    final noteController = TextEditingController();
    var selectedFrequency = PayFrequency.weekly;

    await showModalBottomSheet<void>(
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
                            child: const Text(
                              'YENI CALISAN',
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
                            'Yeni Calisan',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xFF1E1A12),
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Ekibe yeni kisiyi hizli ve temiz bir akista ekleyin.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: const Color(0xFF6E6759),
                                  height: 1.35,
                                ),
                          ),
                          const SizedBox(height: 20),
                          TextField(
                            controller: nameController,
                            decoration: _sheetInputDecoration(
                              label: 'Ad Soyad',
                              fillColor: const Color(0xFFFFFCF5),
                              borderColor: const Color(0xFFE2D8BC),
                              focusedColor: _accentGoldDark,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: wageController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: _sheetInputDecoration(
                              label: 'Gunluk Ucret',
                              fillColor: const Color(0xFFFFFCF5),
                              borderColor: const Color(0xFFE2D8BC),
                              focusedColor: _accentGoldDark,
                            ),
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
                            decoration: _sheetInputDecoration(
                              label: 'Not (Opsiyonel)',
                              alignLabelWithHint: true,
                              fillColor: const Color(0xFFFFFCF5),
                              borderColor: const Color(0xFFE2D8BC),
                              focusedColor: _accentGoldDark,
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
                                          wageController.text.trim(),
                                        ) ??
                                        0;
                                    if (name.isEmpty || wage <= 0) {
                                      return;
                                    }

                                    await ref
                                        .read(workerRepositoryProvider)
                                        .saveWorker(
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

  InputDecoration _sheetInputDecoration({
    required String label,
    required Color fillColor,
    required Color borderColor,
    required Color focusedColor,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: alignLabelWithHint,
      filled: true,
      fillColor: fillColor,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: focusedColor, width: 1.4),
      ),
    );
  }

  void _showWorkerDetail(BuildContext context, Worker worker) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkerDetailSheet(worker: worker),
    );
  }

  Future<void> _confirmDeleteWorker(
    BuildContext context,
    WidgetRef ref,
    Worker worker,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFD0D0D4)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Calisani Sil',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${worker.fullName} isimli calisani silmek istiyor musunuz?',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: const Color(0xFF3D3D3D),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFF1A1A1A),
                          side: const BorderSide(color: Color(0xFFD2D2D2)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text(
                          'Iptal',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [_accentGoldDark, _accentGold],
                          ),
                        ),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            foregroundColor: const Color(0xFF5F5200),
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text(
                            'Sil',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
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

    if (confirmed != true) {
      return;
    }

    await ref
        .read(workerRepositoryProvider)
        .deactivateWorker(workerId: worker.id);

    if (context.mounted) {
      showSuccessSnackBar(context, 'Calisan silindi.');
    }
  }
}

class _WorkerTile extends StatelessWidget {
  const _WorkerTile({
    required this.worker,
    required this.onTap,
    required this.onDelete,
  });

  final Worker worker;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: WorkersPage._cardBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 5,
              height: 94,
              decoration: const BoxDecoration(
                color: WorkersPage._accentTeal,
                borderRadius: BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Row(
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE1E1E4),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _initials(worker.fullName),
                        style: const TextStyle(
                          color: WorkersPage._accentGoldDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            worker.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              height: 1.05,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'GUNLUK: ${formatMoney(worker.dailyWage)}',
                            style: const TextStyle(
                              color: Color(0xFF505050),
                              fontSize: 13,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete, color: Color(0xFFC81616)),
                      tooltip: 'Calisani Sil',
                      iconSize: 24,
                    ),
                  ],
                ),
              ),
            ),
          ],
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
