import 'package:flutter/material.dart';

import '../../../../data/local/repositories.dart';
import '../../../../shared/formatters.dart';

class GrandTotalCard extends StatelessWidget {
  const GrandTotalCard({super.key, required this.report});

  final SiteReportData report;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1A3A6B), Color(0xFF2B5EA7)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'GENEL TOPLAM MALIYET',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white60,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatMoney(report.grandTotal),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          const Divider(color: Colors.white24, height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _GrandTotalItem(
                  label: 'Yevmiye',
                  amount: report.totalWages,
                  icon: Icons.people_alt_rounded,
                ),
              ),
              Container(width: 1, height: 36, color: Colors.white24),
              Expanded(
                child: _GrandTotalItem(
                  label: 'Gider',
                  amount: report.totalExpenses,
                  icon: Icons.receipt_long_rounded,
                ),
              ),
              if (report.workerRows.isNotEmpty) ...[
                Container(width: 1, height: 36, color: Colors.white24),
                Expanded(
                  child: _GrandTotalItem(
                    label: 'Isci Sayisi',
                    value: '${report.workerRows.length}',
                    icon: Icons.badge_rounded,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GrandTotalItem extends StatelessWidget {
  const _GrandTotalItem({
    required this.label,
    required this.icon,
    this.amount,
    this.value,
  }) : assert(amount != null || value != null);

  final String label;
  final IconData icon;
  final double? amount;
  final String? value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 16, color: Colors.white54),
        const SizedBox(height: 4),
        Text(
          amount != null ? formatMoney(amount!) : value!,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.white54),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class ReportEmptyState extends StatelessWidget {
  const ReportEmptyState({super.key, required this.siteName});

  final String siteName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            const Icon(
              Icons.bar_chart_rounded,
              size: 64,
              color: Color(0xFFCCCCCC),
            ),
            const SizedBox(height: 16),
            Text(
              '"$siteName" icin henuz yoklama\nveya gider kaydı yok.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF999999), height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
