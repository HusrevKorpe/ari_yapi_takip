import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/snackbar_helper.dart';

Future<void> cancelPaymentFlow(
  BuildContext sheetContext,
  PayrollPayment payment,
) async {
  final confirmed = await showDialog<bool>(
    context: sheetContext,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (_) => const _ConfirmDialog(),
  );

  if (confirmed != true) return;

  if (!sheetContext.mounted) return;

  final container = ProviderScope.containerOf(sheetContext, listen: false);
  try {
    await container
        .read(paymentRepositoryProvider)
        .deletePayment(paymentId: payment.id);
    container.invalidate(lastPaymentEndProvider(payment.workerId));
    container.invalidate(workerPaymentsProvider(payment.workerId));
    container.invalidate(workerPayrollProvider);

    if (sheetContext.mounted) {
      Navigator.pop(sheetContext);
      showSuccessSnackBar(sheetContext, 'Odeme iptal edildi');
    }
  } catch (e) {
    if (sheetContext.mounted) {
      showErrorSnackBar(sheetContext, 'Iptal hatasi: $e');
    }
  }
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F4),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFD8D8DA)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x26000000),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB60A0A).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 18,
                    color: Color(0xFFB60A0A),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Odemeyi Iptal Et',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1A1A1A),
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Text(
              'Bu odeme iptal edilecek ve donem tekrar hesaplanabilir olacak. Emin misiniz?',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF4E4E4E),
                fontWeight: FontWeight.w500,
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
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text(
                      'Vazgec',
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
                        colors: [Color(0xFF8D0E0E), Color(0xFFD33A3A)],
                      ),
                    ),
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text(
                        'Iptal Et',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
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
  }
}
