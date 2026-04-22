import 'package:flutter/material.dart';

import '../../../data/local/repositories.dart';
import '../../../shared/formatters.dart';
import 'day_detail_expander.dart';
import 'payroll_shared.dart';

class PayrollBreakdownCard extends StatelessWidget {
  const PayrollBreakdownCard({super.key, required this.result});

  final PayrollResult result;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCDCDD)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Column(
              children: [
                PayrollSummaryRow(
                  label: 'Donem',
                  value:
                      '${formatDate(result.periodStart)} – ${formatDate(result.periodEnd)}',
                ),
                const SizedBox(height: 10),
                PayrollSummaryRow(
                  label: 'Calistigi Gun',
                  value: formatWorkedDays(result.workedDayEquivalent),
                ),
                const SizedBox(height: 10),
                PayrollSummaryRow(
                  label: 'Yevmiye Toplam',
                  value: formatMoney(
                    result.workedDayEquivalent * result.worker.dailyWage,
                  ),
                ),
                if (result.locationBonus > 0) ...[
                  const SizedBox(height: 10),
                  PayrollSummaryRow(
                    label: 'Bolge Primi',
                    value: '+${formatMoney(result.locationBonus)}',
                    valueColor: const Color(0xFF1A6B5A),
                  ),
                ],
                if (result.deductions > 0) ...[
                  const SizedBox(height: 10),
                  PayrollSummaryRow(
                    label: 'Kesinti (Avans+Borc)',
                    value: '-${formatMoney(result.deductions)}',
                    valueColor: const Color(0xFFB60A0A),
                  ),
                ],
              ],
            ),
          ),
          _NetRow(result: result),
          if (result.attendanceDays.isNotEmpty)
            DayDetailExpander(days: result.attendanceDays),
        ],
      ),
    );
  }
}

class _NetRow extends StatelessWidget {
  const _NetRow({required this.result});

  final PayrollResult result;

  @override
  Widget build(BuildContext context) {
    final negative = result.net < 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: negative ? const Color(0xFFFFE0E0) : const Color(0xFFEDF7F4),
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(12),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Net Odenecek',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF4E4E4E),
                ),
          ),
          Text(
            formatMoney(result.net),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: negative
                      ? const Color(0xFFB60A0A)
                      : const Color(0xFF1A6B5A),
                ),
          ),
        ],
      ),
    );
  }
}

class PayrollNoPendingBanner extends StatelessWidget {
  const PayrollNoPendingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF7F4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB2DFDB)),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 20,
            color: Color(0xFF1A6B5A),
          ),
          SizedBox(width: 10),
          Text(
            'Tum odemeler guncel.',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1A6B5A),
            ),
          ),
        ],
      ),
    );
  }
}

class PayrollPayButton extends StatelessWidget {
  const PayrollPayButton({
    super.key,
    required this.result,
    required this.onPay,
  });

  final PayrollResult result;
  final VoidCallback onPay;

  @override
  Widget build(BuildContext context) {
    if (result.net <= 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE0E0),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFF5252)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 16,
              color: Color(0xFFB60A0A),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                result.net == 0
                    ? 'Odenecek tutar yok.'
                    : 'Kesintiler brutten fazla. Net tutar negatif.',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFFB60A0A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF145A4A), Color(0xFF1A6B5A)],
          ),
        ),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: onPay,
          icon: const Icon(Icons.check_circle_outline, size: 20),
          label: const Text(
            'Maas Ver',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ),
      ),
    );
  }
}
