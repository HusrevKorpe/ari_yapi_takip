import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/local/repositories.dart';
import '../../shared/attendance_status.dart';
import '../../shared/formatters.dart';
import '../../shared/month_utils.dart';
import '../../shared/snackbar_helper.dart';
import '../workers/workers_page.dart';

class PayrollPage extends ConsumerStatefulWidget {
  const PayrollPage({super.key});

  @override
  ConsumerState<PayrollPage> createState() => _PayrollPageState();
}

class _PayrollPageState extends ConsumerState<PayrollPage> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String? _selectedWorkerId;
  bool _isWorkerPickerOpen = false;
  PayrollResult? _result;

  static const _surfaceColor = Color(0xFFF2F2F4);
  static const _accentColor = Color(0xFFD6B100);
  static const _accentDarkColor = Color(0xFF8A7300);

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(workersProvider);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Maas')),
      body: workersAsync.when(
        data: (workers) {
          if (workers.isEmpty) {
            return const Center(
              child: Text('Maas hesaplamak icin calisan ekleyin.'),
            );
          }

          _selectedWorkerId ??= workers.first.id;

          final lastPaidEnd = ref
              .watch(lastPaymentEndProvider(_selectedWorkerId!))
              .valueOrNull;

          final effectiveStart = lastPaidEnd != null
              ? normalizeDay(lastPaidEnd.add(const Duration(days: 1)))
              : monthStart(_selectedMonth);
          final effectiveEnd = monthEnd(_selectedMonth);
          final isPeriodValid = !effectiveStart.isAfter(effectiveEnd);

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            children: [
              const SizedBox(height: 8),
              Text(
                'Hesaplama Donemi',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: const Color(0xFF535353),
                ),
              ),
              const SizedBox(height: 10),
              _buildMonthPickerButton(),
              const SizedBox(height: 8),
              _buildPeriodInfo(
                effectiveStart: effectiveStart,
                effectiveEnd: effectiveEnd,
                isPeriodValid: isPeriodValid,
              ),
              const SizedBox(height: 20),
              Text(
                'Calisan Secimi',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: const Color(0xFF535353),
                ),
              ),
              const SizedBox(height: 10),
              _buildWorkerPicker(workers),
              const SizedBox(height: 18),
              SizedBox(
                height: 58,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: isPeriodValid
                          ? [_accentDarkColor, _accentColor]
                          : [const Color(0xFFAAAAAA), const Color(0xFFCCCCCC)],
                    ),
                  ),
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: const Color(0xFF5F5200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: isPeriodValid
                        ? () => _calculate(
                              workers,
                              periodStart: effectiveStart,
                              periodEnd: effectiveEnd,
                            )
                        : null,
                    child: const Text(
                      'Maasi Hesapla',
                      style: TextStyle(
                        letterSpacing: 1.4,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
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
                      onPressed: () => _showAdvanceDebtDialog(type: 'advance'),
                      icon: const Icon(Icons.add_circle, size: 18),
                      label: const Text(
                        'Avans Ekle',
                        style: TextStyle(
                          fontSize: 30 / 2,
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
                      onPressed: () => _showAdvanceDebtDialog(type: 'debt'),
                      icon: const Icon(Icons.remove_circle, size: 18),
                      label: const Text(
                        'Borc Ekle',
                        style: TextStyle(
                          fontSize: 30 / 2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_result != null) ...[
                Stack(
                  children: [
                    Card(
                      color: _surfaceColor,
                      margin: const EdgeInsets.only(top: 20),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 30, 16, 10),
                            child: Column(
                              children: [
                                _summaryRow('Calisan', _result!.worker.fullName),
                                const SizedBox(height: 14),
                                _summaryRow(
                                  'Donem',
                                  '${formatDate(_result!.periodStart)} – ${formatDate(_result!.periodEnd)}',
                                ),
                                const SizedBox(height: 14),
                                _summaryRow(
                                  'Calistigi Gun',
                                  _formatWorkedDays(_result!.workedDayEquivalent),
                                ),
                                const SizedBox(height: 14),
                                _summaryRow(
                                  'Yevmiye',
                                  formatMoney(
                                    _result!.workedDayEquivalent *
                                        _result!.worker.dailyWage,
                                  ),
                                ),
                                if (_result!.locationBonus > 0) ...[
                                  const SizedBox(height: 14),
                                  _summaryRow(
                                    'Bolge Primi',
                                    '+${formatMoney(_result!.locationBonus)}',
                                    valueColor: const Color(0xFF1A6B5A),
                                  ),
                                ],
                                const SizedBox(height: 14),
                                _summaryRow(
                                  'Kesinti (Avans+Borc)',
                                  formatMoney(_result!.deductions),
                                  valueColor: const Color(0xFFB60A0A),
                                ),
                                if (_result!.attendanceDays.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  const Divider(color: Color(0xFFDCDCDD)),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.calendar_today_rounded,
                                        size: 13,
                                        color: Color(0xFF888888),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'GUNLUK DETAY',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                          color: Color(0xFF888888),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  for (final day in _result!.attendanceDays)
                                    _dayRow(day),
                                ],
                              ],
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE5E5E7),
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(12),
                              ),
                            ),
                            padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                            child: Column(
                              children: [
                                Text(
                                  'Net Odenecek',
                                  style: textTheme.labelLarge?.copyWith(
                                    letterSpacing: 2,
                                    color: const Color(0xFF4E4E4E),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  formatMoney(_result!.net),
                                  style: textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 14,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _accentDarkColor,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: const Text(
                          'Ozet Rapor',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 54,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1A6B5A),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _recordPayment,
                    icon: const Icon(Icons.check_circle_outline, size: 20),
                    label: const Text(
                      'Maas Verildi',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }

  Widget _buildPeriodInfo({
    required DateTime effectiveStart,
    required DateTime effectiveEnd,
    required bool isPeriodValid,
  }) {
    if (!isPeriodValid) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF3CD),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFFCC02)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 16, color: Color(0xFF856404)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Bu ay icin odeme zaten yapilmis.',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF856404),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF7F4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB2DFDB)),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range_rounded, size: 16, color: Color(0xFF1A6B5A)),
          const SizedBox(width: 8),
          Text(
            '${formatDate(effectiveStart)} – ${formatDate(effectiveEnd)}',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF1A6B5A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthPickerButton() {
    return GestureDetector(
      onTap: _showMonthPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFD9C97A)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_month_rounded,
              size: 18,
              color: _accentDarkColor,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                formatMonth(_selectedMonth),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Color(0xFF8A7300),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, {Color? valueColor}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 18,
              color: Color(0xFF494949),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: valueColor ?? const Color(0xFF121212),
          ),
        ),
      ],
    );
  }

  Widget _dayRow(PayrollAttendanceDay day) {
    final isHalf = day.dayEquivalent == 0.5;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Text(
            formatDate(day.date),
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF555555),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isHalf
                  ? const Color(0xFFFFF3CD)
                  : const Color(0xFFEDF7F4),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              day.status.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isHalf
                    ? const Color(0xFF856404)
                    : const Color(0xFF1A6B5A),
              ),
            ),
          ),
          const Spacer(),
          Text(
            formatMoney(day.dailyAmount),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkerPicker(List<Worker> workers) {
    final selectedWorker = workers.firstWhere(
      (worker) => worker.id == _selectedWorkerId,
      orElse: () => workers.first,
    );

    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isWorkerPickerOpen
              ? const Color(0xFFD9C97A)
              : const Color(0xFFDCDCDD),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() {
                _isWorkerPickerOpen = !_isWorkerPickerOpen;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8A7300).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.person_outline_rounded,
                      size: 18,
                      color: _accentDarkColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selectedWorker.fullName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1A1A1A),
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isWorkerPickerOpen ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Color(0xFF8A7300),
                      size: 24,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _isWorkerPickerOpen
                  ? Column(
                      children: [
                        const Divider(height: 1, color: Color(0xFFDCDCDD)),
                        for (final worker in workers)
                          _workerOptionTile(
                            worker: worker,
                            isSelected: worker.id == _selectedWorkerId,
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workerOptionTile({required Worker worker, required bool isSelected}) {
    return Material(
      color: isSelected
          ? const Color(0xFF8A7300).withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedWorkerId = worker.id;
            _result = null;
            _isWorkerPickerOpen = false;
          });
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  worker.fullName,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: const Color(0xFF202020),
                  ),
                ),
              ),
              if (isSelected)
                const Icon(
                  Icons.check_circle_rounded,
                  color: _accentDarkColor,
                  size: 19,
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatWorkedDays(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(1).replaceAll('.', ',');
  }

  Future<void> _showMonthPicker() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _MonthPickerDialog(selected: _selectedMonth),
    );
    if (picked == null) return;
    setState(() {
      _selectedMonth = picked;
      _result = null;
    });
  }

  Future<void> _calculate(
    List<Worker> workers, {
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final worker = workers.firstWhere((item) => item.id == _selectedWorkerId);
    try {
      final result = await ref.read(payrollRepositoryProvider).calculate(
        worker: worker,
        periodStart: periodStart,
        periodEnd: periodEnd,
      );
      setState(() {
        _result = result;
      });
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Hesaplama hatasi: $e');
      }
    }
  }

  Future<void> _recordPayment() async {
    final result = _result;
    if (result == null) return;
    try {
      await ref.read(paymentRepositoryProvider).recordPayment(
        workerId: result.worker.id,
        periodStart: result.periodStart,
        periodEnd: result.periodEnd,
        amount: result.net,
      );
      ref.invalidate(lastPaymentEndProvider(result.worker.id));
      setState(() {
        _result = null;
      });
      if (mounted) {
        showSuccessSnackBar(context, 'Maas odendi olarak kaydedildi');
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Kayit hatasi: $e');
      }
    }
  }

  Future<void> _showAdvanceDebtDialog({required String type}) async {
    final amountController = TextEditingController();
    final noteController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (context) {
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                        onPressed: () => Navigator.pop(context),
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
                            if (_selectedWorkerId == null) return;
                            final amount =
                                double.tryParse(amountController.text.trim()) ??
                                0;
                            if (amount <= 0) return;

                            await ref
                                .read(advanceDebtRepositoryProvider)
                                .add(
                                  workerId: _selectedWorkerId!,
                                  date: DateTime.now(),
                                  type: type,
                                  amount: amount,
                                  note: noteController.text.trim().isEmpty
                                      ? null
                                      : noteController.text.trim(),
                                );

                            if (context.mounted) {
                              Navigator.pop(context);
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
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({required this.selected});

  final DateTime selected;

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  static const _accentDarkColor = Color(0xFF8A7300);
  static const _surfaceColor = Color(0xFFF2F2F4);

  static const _monthNames = [
    'Ocak', 'Subat', 'Mart', 'Nisan',
    'Mayis', 'Haziran', 'Temmuz', 'Agustos',
    'Eylul', 'Ekim', 'Kasim', 'Aralik',
  ];

  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.selected.year;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFCFCFCF)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: () => setState(() => _year--),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: _accentDarkColor,
                ),
                Text(
                  '$_year',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1A1A1A),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() => _year++),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: _accentDarkColor,
                ),
              ],
            ),
            const SizedBox(height: 8),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.2,
              physics: const NeverScrollableScrollPhysics(),
              children: List.generate(12, (i) {
                final month = i + 1;
                final isSelected =
                    _year == widget.selected.year &&
                    month == widget.selected.month;
                return GestureDetector(
                  onTap: () => Navigator.pop(context, DateTime(_year, month)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    decoration: BoxDecoration(
                      color: isSelected ? _accentDarkColor : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected
                            ? _accentDarkColor
                            : const Color(0xFFDCDCDD),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _monthNames[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF2A2A2A),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }
}
