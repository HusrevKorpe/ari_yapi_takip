import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/local/repositories.dart';
import '../../shared/formatters.dart';
import '../../shared/snackbar_helper.dart';
import '../payroll/widgets/day_detail_expander.dart';
import '../payroll/widgets/payroll_shared.dart';
import 'widgets/worker_attendance_month_grid.dart';
import 'widgets/worker_header_card.dart';
import 'widgets/worker_stats_grid.dart';

class WorkerDetailPage extends ConsumerStatefulWidget {
  const WorkerDetailPage({super.key, required this.worker});

  final Worker worker;

  @override
  ConsumerState<WorkerDetailPage> createState() => _WorkerDetailPageState();
}

class _WorkerDetailPageState extends ConsumerState<WorkerDetailPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.worker.fullName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: AppColors.background,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.brandDark,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.brand,
              indicatorWeight: 3,
              labelStyle: AppTextStyles.button,
              unselectedLabelStyle: AppTextStyles.button,
              tabs: const [
                Tab(text: 'Özet'),
                Tab(text: 'Avans & Borç'),
                Tab(text: 'Yevmiye'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _SummaryTab(worker: widget.worker),
          _AdvanceDebtTab(worker: widget.worker),
          _AttendanceTab(worker: widget.worker),
        ],
      ),
    );
  }
}

class _SummaryTab extends ConsumerWidget {
  const _SummaryTab({required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payrollAsync = ref.watch(workerPayrollProvider(worker));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      children: [
        WorkerHeaderCard(worker: worker),
        const SizedBox(height: AppSpacing.md),
        WorkerStatsGrid(workerId: worker.id),
        const SizedBox(height: AppSpacing.lg),
        const _SectionLabel(
          icon: Icons.receipt_long_rounded,
          label: 'MEVCUT DÖNEM',
        ),
        const SizedBox(height: AppSpacing.sm),
        payrollAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => _ErrorBox(message: 'Hesaplama hatası: $e'),
          data: (result) {
            if (result == null) {
              return const _InfoBanner(
                icon: Icons.check_circle_rounded,
                color: AppColors.success,
                bg: AppColors.successLight,
                message: 'Tüm ödemeler güncel.',
              );
            }
            return _PayrollSummaryCard(result: result);
          },
        ),
      ],
    );
  }
}

class _PayrollSummaryCard extends StatelessWidget {
  const _PayrollSummaryCard({required this.result});

  final PayrollResult result;

  @override
  Widget build(BuildContext context) {
    final negative = result.net < 0;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.sm,
            ),
            child: Column(
              children: [
                PayrollSummaryRow(
                  label: 'Dönem',
                  value:
                      '${formatDate(result.periodStart)} – ${formatDate(result.periodEnd)}',
                ),
                const SizedBox(height: AppSpacing.sm),
                PayrollSummaryRow(
                  label: 'Çalıştığı Gün',
                  value: formatWorkedDays(result.workedDayEquivalent),
                ),
                const SizedBox(height: AppSpacing.sm),
                PayrollSummaryRow(
                  label: 'Yevmiye Toplam',
                  value: formatMoney(
                    result.workedDayEquivalent * result.worker.dailyWage,
                  ),
                ),
                if (result.locationBonus > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  PayrollSummaryRow(
                    label: 'Bölge Primi',
                    value: '+${formatMoney(result.locationBonus)}',
                    valueColor: AppColors.success,
                  ),
                ],
                if (result.deductions > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  PayrollSummaryRow(
                    label: 'Kesinti (Avans+Borç)',
                    value: '-${formatMoney(result.deductions)}',
                    valueColor: AppColors.danger,
                  ),
                ] else if (result.deductions < 0) ...[
                  // Borç avansı aştığında net brütten büyük olur; bu artışı
                  // gizlemeyip ayrı bir "Alacak" satırı olarak gösteriyoruz.
                  const SizedBox(height: AppSpacing.sm),
                  PayrollSummaryRow(
                    label: 'Alacak (Avans+Borç)',
                    value: '+${formatMoney(-result.deductions)}',
                    valueColor: AppColors.success,
                  ),
                ],
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: negative ? AppColors.dangerLight : AppColors.successLight,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppRadius.md),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  negative ? 'Net (Negatif)' : 'Net Ödenecek',
                  style: AppTextStyles.bodyStrong.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  formatMoney(result.net),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: negative ? AppColors.danger : AppColors.success,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          if (result.attendanceDays.isNotEmpty)
            DayDetailExpander(days: result.attendanceDays),
        ],
      ),
    );
  }
}

class _AdvanceDebtTab extends ConsumerWidget {
  const _AdvanceDebtTab({required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtsAsync = ref.watch(workerAdvanceDebtsProvider(worker.id));

    return Column(
      children: [
        Expanded(
          child: debtsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) =>
                Center(child: _ErrorBox(message: 'Liste yüklenemedi: $e')),
            data: (debts) {
              if (debts.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(AppSpacing.xl),
                    child: Text(
                      'Henüz avans veya borç kaydı yok.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                itemCount: debts.length,
                itemBuilder: (context, i) => _DebtRow(
                  debt: debts[i],
                  onEdit: () => _showAdvanceDebtDialog(
                    context,
                    workerId: worker.id,
                    type: debts[i].type,
                    existing: debts[i],
                  ),
                  onDelete: () => _confirmDelete(context, ref, debts[i]),
                ),
              );
            },
          ),
        ),
        _AdvanceDebtActions(workerId: worker.id),
      ],
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
        title: const Text('Kaydı Sil'),
        content: Text(
          '${debt.type == 'advance' ? 'Avans' : 'Borç'} kaydı silinecek '
          '(${formatMoney(debt.amount)}). Emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      await ref.read(advanceDebtRepositoryProvider).delete(id: debt.id);
      if (context.mounted) {
        showSuccessSnackBar(context, 'Kayıt silindi');
      }
    } catch (_) {
      if (context.mounted) {
        showErrorSnackBar(context, 'Kayıt silinemedi. Lütfen tekrar deneyin.');
      }
    }
  }
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({
    required this.debt,
    required this.onEdit,
    required this.onDelete,
  });

  final AdvanceDebt debt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isAdvance = debt.type == 'advance';
    final tint = isAdvance ? AppColors.info : AppColors.danger;
    final tintBg = isAdvance ? AppColors.infoLight : AppColors.dangerLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm + 2,
        ),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: tintBg,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                isAdvance
                    ? Icons.arrow_downward_rounded
                    : Icons.arrow_upward_rounded,
                size: 16,
                color: tint,
              ),
            ),
            const SizedBox(width: AppSpacing.sm + 2),
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
                          color: tintBg,
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                        ),
                        child: Text(
                          isAdvance ? 'Avans' : 'Borç',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: tint,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        formatDate(debt.eventDate),
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textTertiary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (debt.note != null && debt.note!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      debt.note!,
                      style: AppTextStyles.caption,
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
                color: tint,
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: onEdit,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: onDelete,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdvanceDebtActions extends StatelessWidget {
  const _AdvanceDebtActions({required this.workerId});

  final String workerId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: AppColors.info,
                  side: const BorderSide(color: AppColors.info),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                label: const Text(
                  'Avans Ekle',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: () => _showAdvanceDebtDialog(
                  context,
                  workerId: workerId,
                  type: 'advance',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: AppColors.danger,
                  side: const BorderSide(color: AppColors.danger),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                label: const Text(
                  'Borç Ekle',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                onPressed: () => _showAdvanceDebtDialog(
                  context,
                  workerId: workerId,
                  type: 'debt',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _showAdvanceDebtDialog(
  BuildContext context, {
  required String workerId,
  required String type,
  AdvanceDebt? existing,
}) async {
  final isEdit = existing != null;
  final amountController = TextEditingController(
    text: isEdit ? existing.amount.toStringAsFixed(0) : '',
  );
  final noteController = TextEditingController(
    text: isEdit ? (existing.note ?? '') : '',
  );
  var selectedDate = isEdit ? existing.eventDate : DateTime.now();

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final title = isEdit
          ? (type == 'advance' ? 'Avansı Düzenle' : 'Borcu Düzenle')
          : (type == 'advance' ? 'Avans Ekle' : 'Borç Ekle');
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Tutar',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Not',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    locale: const Locale('tr', 'TR'),
                  );
                  if (picked != null) {
                    setState(() => selectedDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm + 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Tarih',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        formatDate(selectedDate),
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      const Icon(
                        Icons.edit_calendar_outlined,
                        size: 16,
                        color: AppColors.brand,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('İptal'),
            ),
            Consumer(
              builder: (_, ref, _) => FilledButton(
                onPressed: () async {
                  final amount = double.tryParse(
                          amountController.text.trim().replaceAll(',', '.')) ??
                      0;
                  if (amount <= 0) return;
                  final note = noteController.text.trim().isEmpty
                      ? null
                      : noteController.text.trim();
                  final repo = ref.read(advanceDebtRepositoryProvider);
                  try {
                    if (isEdit) {
                      await repo.update(
                        id: existing.id,
                        date: selectedDate,
                        type: type,
                        amount: amount,
                        note: note,
                      );
                    } else {
                      await repo.add(
                        workerId: workerId,
                        date: selectedDate,
                        type: type,
                        amount: amount,
                        note: note,
                      );
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                    if (context.mounted) {
                      showSuccessSnackBar(
                        context,
                        isEdit
                            ? 'Kayıt güncellendi'
                            : (type == 'advance'
                                ? 'Avans kaydedildi'
                                : 'Borç kaydedildi'),
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      showErrorSnackBar(
                        context,
                        'Kayıt kaydedilemedi. Lütfen tekrar deneyin.',
                      );
                    }
                  }
                },
                child: Text(isEdit ? 'Güncelle' : 'Kaydet'),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _AttendanceTab extends StatelessWidget {
  const _AttendanceTab({required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xl),
      children: [
        WorkerAttendanceMonthGrid(worker: worker),
        const SizedBox(height: AppSpacing.md),
        const _Legend(),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.sm,
        children: const [
          _LegendChip(
            color: Color(0xFF2E7D32),
            icon: Icons.check_rounded,
            label: 'Tam',
          ),
          _LegendChip(
            color: Color(0xFFE65100),
            icon: Icons.remove_rounded,
            label: 'Yarım',
          ),
          _LegendChip(
            color: Color(0xFFC62828),
            icon: Icons.close_rounded,
            label: 'Gelmedi',
          ),
          _LegendChip(
            color: Color(0xFF1565C0),
            icon: Icons.pause_rounded,
            label: 'İzinli',
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  const _LegendChip({
    required this.color,
    required this.icon,
    required this.label,
  });

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Icon(icon, size: 12, color: color),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 6),
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.bg,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final Color bg;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AppSpacing.sm),
          Text(
            message,
            style: AppTextStyles.bodyStrong.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(
        message,
        style: AppTextStyles.body.copyWith(color: AppColors.danger),
      ),
    );
  }
}
