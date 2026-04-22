import 'package:flutter/material.dart';

import '../../../../data/local/repositories.dart';
import '../../../../shared/formatters.dart';
import 'expense_category_list.dart';
import 'grand_total_card.dart';
import 'report_summary.dart';
import 'worker_table.dart';

class ReportBody extends StatelessWidget {
  const ReportBody({super.key, required this.report});

  final SiteReportData report;

  static const _accent = Color(0xFF1A6B5A);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        if (report.firstWorkDate != null) ...[
          DateRangeChip(
            first: report.firstWorkDate!,
            last: report.lastWorkDate!,
          ),
          const SizedBox(height: 16),
        ],
        SummaryRow(report: report),
        const SizedBox(height: 24),
        if (report.workerRows.isNotEmpty) ...[
          SectionHeader(
            icon: Icons.people_alt_rounded,
            title: 'Isci Bazli Puantaj',
            trailing: '${report.workerRows.length} isci',
          ),
          const SizedBox(height: 10),
          WorkerTable(
            rows: report.workerRows,
            siteBonus: report.site.dailyBonus,
          ),
          const SizedBox(height: 6),
          TotalRow(
            label: 'Toplam Yevmiye',
            amount: report.totalWages,
            color: _accent,
          ),
          const SizedBox(height: 24),
        ],
        if (report.expenseCategories.isNotEmpty) ...[
          SectionHeader(
            icon: Icons.receipt_long_rounded,
            title: 'Gider Kalemleri',
            trailing: formatMoney(report.totalExpenses),
          ),
          const SizedBox(height: 10),
          ExpenseCategoryList(categories: report.expenseCategories),
          const SizedBox(height: 24),
        ],
        if (report.workerRows.isEmpty && report.expenseCategories.isEmpty)
          ReportEmptyState(siteName: report.site.name),
        if (report.workerRows.isNotEmpty ||
            report.expenseCategories.isNotEmpty)
          GrandTotalCard(report: report),
      ],
    );
  }
}
