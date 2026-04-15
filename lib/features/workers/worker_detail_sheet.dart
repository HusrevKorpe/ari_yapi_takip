import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/formatters.dart';
import '../../shared/snackbar_helper.dart';

class WorkerDetailSheet extends ConsumerWidget {
  const WorkerDetailSheet({super.key, required this.worker});

  final Worker worker;

  static const _surfaceColor = Color(0xFFF2F2F4);
  static const _accentDarkColor = Color(0xFF8A7300);
  static const _accentColor = Color(0xFFD6B100);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtsAsync = ref.watch(workerAdvanceDebtsProvider(worker.id));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFCCCCCC),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: [
                _buildWorkerInfo(context),
                const SizedBox(height: 18),
                _buildActionButtons(context, ref),
                const SizedBox(height: 22),
                _buildHistorySection(context, ref, debtsAsync),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerInfo(BuildContext context) {
    final initials = worker.fullName
        .split(' ')
        .where((s) => s.isNotEmpty)
        .take(2)
        .map((s) => s[0].toUpperCase())
        .join();

    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _accentDarkColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _accentDarkColor,
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                worker.fullName,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1A1A1A),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Gunluk: ${formatMoney(worker.dailyWage)}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF666666),
                ),
              ),
              if (worker.notes != null && worker.notes!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  worker.notes!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: _surfaceColor,
              foregroundColor: const Color(0xFF171717),
              side: const BorderSide(color: Color(0xFFC8B787)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => _showAddDialog(context, ref, type: 'advance'),
            icon: const Icon(Icons.add_circle, size: 18),
            label: const Text(
              'Avans Ekle',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: _surfaceColor,
              foregroundColor: const Color(0xFF171717),
              side: const BorderSide(color: Color(0xFFC8B787)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => _showAddDialog(context, ref, type: 'debt'),
            icon: const Icon(Icons.remove_circle, size: 18),
            label: const Text(
              'Borc Ekle',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistorySection(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<AdvanceDebt>> debtsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.history_rounded,
              size: 15,
              color: Color(0xFF888888),
            ),
            const SizedBox(width: 6),
            const Text(
              'AVANS & BORC GECMISI',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: Color(0xFF888888),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        debtsAsync.when(
          data: (debts) {
            if (debts.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE8E8E8)),
                ),
                child: const Text(
                  'Henuz avans veya borc kaydi yok.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF999999),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              );
            }

            return Column(
              children: [
                for (final debt in debts)
                  _debtRow(context, ref, debt),
              ],
            );
          },
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _debtRow(BuildContext context, WidgetRef ref, AdvanceDebt debt) {
    final isAdvance = debt.type == 'advance';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE8E8E8)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: isAdvance
                    ? const Color(0xFF1A6B5A).withValues(alpha: 0.1)
                    : const Color(0xFFB60A0A).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isAdvance
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 16,
                color: isAdvance
                    ? const Color(0xFF1A6B5A)
                    : const Color(0xFFB60A0A),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isAdvance
                              ? const Color(0xFFEDF7F4)
                              : const Color(0xFFFFE0E0),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          isAdvance ? 'Avans' : 'Borc',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isAdvance
                                ? const Color(0xFF1A6B5A)
                                : const Color(0xFFB60A0A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatDate(debt.eventDate),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF888888),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (debt.note != null && debt.note!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      debt.note!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Text(
              formatMoney(debt.amount),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isAdvance
                    ? const Color(0xFF1A6B5A)
                    : const Color(0xFFB60A0A),
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _confirmDelete(context, ref, debt),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: Color(0xFFAAAAAA),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDialog(
    BuildContext context,
    WidgetRef ref, {
    required String type,
  }) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              color: _surfaceColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFCFCFCF)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  type == 'advance' ? 'Avans Ekle' : 'Borc Ekle',
                  style: Theme.of(dialogContext).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1A1A1A),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD4D4D4)),
                  ),
                  child: TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Tutar',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD4D4D4)),
                  ),
                  child: TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'Not',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      border: InputBorder.none,
                    ),
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
                        onPressed: () => Navigator.pop(dialogContext),
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
                            colors: [_accentDarkColor, _accentColor],
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
                          onPressed: () async {
                            final amount = double.tryParse(
                                  amountController.text.trim(),
                                ) ??
                                0;
                            if (amount <= 0) return;

                            await ref
                                .read(advanceDebtRepositoryProvider)
                                .add(
                                  workerId: worker.id,
                                  date: DateTime.now(),
                                  type: type,
                                  amount: amount,
                                  note: noteController.text.trim().isEmpty
                                      ? null
                                      : noteController.text.trim(),
                                );

                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (context.mounted) {
                              showSuccessSnackBar(
                                context,
                                type == 'advance'
                                    ? 'Avans kaydedildi'
                                    : 'Borc kaydedildi',
                              );
                            }
                          },
                          child: const Text(
                            'Kaydet',
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
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    AdvanceDebt debt,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kaydi Sil'),
        content: Text(
          '${debt.type == 'advance' ? 'Avans' : 'Borc'} kaydi silinecek (${formatMoney(debt.amount)}). Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgec'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFB60A0A),
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(advanceDebtRepositoryProvider).delete(id: debt.id);

    if (context.mounted) {
      showSuccessSnackBar(context, 'Kayit silindi');
    }
  }
}
