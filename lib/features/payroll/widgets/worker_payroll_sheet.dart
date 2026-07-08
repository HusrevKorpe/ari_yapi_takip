import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../data/local/repositories.dart';
import '../../../shared/formatters.dart';
import '../../../shared/snackbar_helper.dart';
import 'payment_history_list.dart';
import 'payroll_breakdown_card.dart';

class WorkerPayrollSheet extends ConsumerWidget {
  const WorkerPayrollSheet({super.key, required this.worker});

  final Worker worker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payrollAsync = ref.watch(workerPayrollProvider(worker));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFFF2F2F4),
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
            child: payrollAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Hesaplama hatası: $e'),
              ),
              data: (result) => _SheetBody(worker: worker, result: result),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetBody extends ConsumerStatefulWidget {
  const _SheetBody({required this.worker, required this.result});

  final Worker worker;
  final PayrollResult? result;

  @override
  ConsumerState<_SheetBody> createState() => _SheetBodyState();
}

class _SheetBodyState extends ConsumerState<_SheetBody> {
  bool _saving = false;
  late final TextEditingController _amountController;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(
      text: _formatAmountForInput(widget.result?.net),
    );
  }

  @override
  void didUpdateWidget(covariant _SheetBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sonuç yenilendiğinde (başka cihazdan sync, avans eklendi vs.) alanı
    // güncel hak edişle doldur; kullanıcının eski nete göre yazdığı tutar
    // yanıltıcı olur.
    if (oldWidget.result?.net != widget.result?.net) {
      _amountController.text = _formatAmountForInput(widget.result?.net);
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  static String _formatAmountForInput(double? value) {
    if (value == null || value <= 0) return '';
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
  }

  double? _enteredAmount() {
    final raw = _amountController.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    return double.tryParse(raw);
  }

  Future<void> _recordPayment() async {
    final stale = widget.result;
    if (stale == null || stale.net <= 0) return;
    final entered = _enteredAmount();
    if (entered == null || entered <= 0) {
      showErrorSnackBar(context, 'Geçerli bir tutar girin.');
      return;
    }
    // Hızlı çift tıklama veya uzun süren ağ yazımı sırasında ikinci kayıt
    // denenmesin — repository tarafında da unique index + pre-check var ama
    // UI burada blokluyor ki kullanıcı "kaydediliyor" geri bildirimini görsün.
    if (_saving) return;
    setState(() => _saving = true);

    try {
      // Sheet açıldığında hesaplanan `stale` net bayat olabilir: bu sırada
      // başka sekmeden avans/borç eklenmiş ya da başka cihazdan sync gelmiş
      // olabilir. Ödeme anında güncel durumu yeniden hesaplayıp doğruluyoruz;
      // (skipLoadingOnRefresh=true olduğundan bu refresh sheet'i unmount etmez).
      final fresh = await ref.refresh(
        workerPayrollProvider(widget.worker).future,
      );

      if (fresh == null || fresh.net <= 0) {
        // Artık ödenecek tutar yok (ör. başka cihaz ödedi ya da kesintiler
        // brütü aştı). Ekran refresh sonrası doğru durumu gösteriyor.
        if (mounted) {
          showErrorSnackBar(
            context,
            'Bu dönem için ödenecek tutar kalmadı. Ekran güncellendi.',
          );
        }
        return;
      }

      if ((fresh.net - stale.net).abs() >= 0.01) {
        // Tutar değişti: kullanıcı güncel tutarı görüp yeniden onaylamalı.
        if (mounted) {
          showErrorSnackBar(
            context,
            'Ödenecek tutar güncellendi: ${formatMoney(fresh.net)}. '
            'Lütfen kontrol edip tekrar onaylayın.',
          );
        }
        return;
      }

      // Girilen tutarı hak edişe göre böl: fazlası otomatik avans olur,
      // eksiği devreden bakiye olarak sonraki dönemde kendiliğinden görünür.
      var salaryPart = entered < fresh.net ? entered : fresh.net;
      var excess = entered - fresh.net;
      if (excess.abs() < 0.01) {
        excess = 0;
        salaryPart = fresh.net;
      }
      final shortfall = fresh.net - salaryPart;

      if (excess > 0 || shortfall >= 0.01) {
        if (!mounted) return;
        final confirmed = await _confirmAmountMismatch(
          entered: entered,
          net: fresh.net,
          excess: excess,
        );
        if (!confirmed) return;
      }

      // Her zaman güncel (fresh) sonucu yaz — asla bayat değeri değil.
      await ref.read(payrollRepositoryProvider).saveSnapshot(fresh);
      await ref.read(paymentRepositoryProvider).recordPayment(
            workerId: fresh.worker.id,
            periodStart: fresh.periodStart,
            periodEnd: fresh.periodEnd,
            amount: salaryPart,
            excessAdvance: excess > 0 ? excess : 0,
            excessAdvanceNote: excess > 0
                ? 'Maaş ödemesi fazlası '
                    '(${formatDate(fresh.periodStart)} – ${formatDate(fresh.periodEnd)} dönemi)'
                : null,
          );
      ref.invalidate(lastPaymentEndProvider(fresh.worker.id));
      ref.invalidate(workerPayrollProvider(widget.worker));

      if (mounted) {
        if (excess > 0) {
          showSuccessSnackBar(
            context,
            'Maaş ödendi; fazla ${formatMoney(excess)} avans olarak kaydedildi',
          );
        } else if (shortfall >= 0.01) {
          showSuccessSnackBar(
            context,
            'Ödeme kaydedildi; kalan ${formatMoney(shortfall)} sonraki '
            'döneme devretti',
          );
        } else {
          showSuccessSnackBar(context, 'Maaş ödendi olarak kaydedildi');
        }
      }
    } on DuplicatePaymentException catch (e) {
      // İki cihazdan eşzamanlı ödeme: ikinci cihazda pull sync sonrası bu
      // satır görünür hâle gelir; provider invalidate edilirse zaten doğru
      // dönem hesaplanacak.
      ref.invalidate(lastPaymentEndProvider(e.workerId));
      ref.invalidate(workerPayrollProvider(widget.worker));
      if (mounted) {
        showErrorSnackBar(
          context,
          'Bu döneme ait ödeme zaten kayıtlı. Ekran yenilendi.',
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, 'Kayıt hatası: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Girilen tutar hak edişten farklıysa ne olacağını açıklayıp onay ister.
  Future<bool> _confirmAmountMismatch({
    required double entered,
    required double net,
    required double excess,
  }) async {
    final message = excess > 0
        ? 'Hak ediş ${formatMoney(net)}, ödenecek tutar ${formatMoney(entered)}.\n\n'
            'Fazla olan ${formatMoney(excess)} otomatik olarak avans '
            'kaydedilecek ve sonraki maaştan düşülecek.'
        : 'Hak ediş ${formatMoney(net)}, ödenecek tutar ${formatMoney(entered)}.\n\n'
            'Eksik kalan ${formatMoney(net - entered)} sonraki döneme '
            'devredecek.';
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ödemeyi Onayla'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Onayla ve Öde'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final current = widget.result;

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Text(
          widget.worker.fullName,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Yevmiye: ${formatMoney(widget.worker.dailyWage)}',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF888888),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        if (current != null) ...[
          PayrollBreakdownCard(result: current),
          if (current.net > 0) ...[
            const SizedBox(height: 12),
            _PaymentAmountField(
              controller: _amountController,
              net: current.net,
            ),
          ],
          const SizedBox(height: 16),
          PayrollPayButton(
            result: current,
            saving: _saving,
            onPay: _recordPayment,
          ),
        ] else
          const PayrollNoPendingBanner(),
        const SizedBox(height: 28),
        PaymentHistoryList(workerId: widget.worker.id),
      ],
    );
  }
}

/// Ödenecek tutar girişi: hak edişle önceden dolu gelir, kullanıcı isterse
/// değiştirir. Girilen tutara göre altta ne olacağını canlı açıklar
/// (fazlası otomatik avans, eksiği sonraki döneme devir).
class _PaymentAmountField extends StatelessWidget {
  const _PaymentAmountField({required this.controller, required this.net});

  final TextEditingController controller;
  final double net;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCDCDD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A1A1A),
            ),
            decoration: const InputDecoration(
              labelText: 'Ödenecek Tutar',
              suffixText: '₺',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final entered = double.tryParse(
                value.text.trim().replaceAll(',', '.'),
              );

              final String hint;
              final Color color;
              if (entered == null || entered <= 0) {
                hint = 'Hak edilen tutar: ${formatMoney(net)}';
                color = const Color(0xFF888888);
              } else if (entered - net >= 0.01) {
                hint =
                    'Fazla ${formatMoney(entered - net)} otomatik avans olarak '
                    'kaydedilecek.';
                color = const Color(0xFF0A7E82);
              } else if (net - entered >= 0.01) {
                hint =
                    'Kalan ${formatMoney(net - entered)} sonraki döneme '
                    'devredecek.';
                color = const Color(0xFFE65100);
              } else {
                hint = 'Hak edilen tutarın tamamı ödenecek.';
                color = const Color(0xFF888888);
              }

              return Text(
                hint,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
