import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/repositories.dart';
import '../../shared/formatters.dart';

class SiteReportPage extends ConsumerWidget {
  const SiteReportPage({super.key, required this.siteId, required this.siteName});

  final String siteId;
  final String siteName;

  static const _bg = Color(0xFFF7F9F8);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(siteReportProvider(siteId));

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              siteName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161616),
              ),
            ),
            const Text(
              'Santiye Raporu',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7B75),
              ),
            ),
          ],
        ),
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (report) => _ReportBody(report: report),
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.report});

  final SiteReportData report;

  static const _accent = Color(0xFF1A6B5A);

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: [
        // Tarih aralığı
        if (report.firstWorkDate != null) ...[
          _DateRangeChip(
            first: report.firstWorkDate!,
            last: report.lastWorkDate!,
          ),
          const SizedBox(height: 16),
        ],

        // Özet kartlar
        _SummaryRow(report: report),
        const SizedBox(height: 24),

        // İşçi puantaj tablosu
        if (report.workerRows.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.people_alt_rounded,
            title: 'Isci Bazli Puantaj',
            trailing: '${report.workerRows.length} isci',
          ),
          const SizedBox(height: 10),
          _WorkerTable(rows: report.workerRows, siteBonus: report.site.dailyBonus),
          const SizedBox(height: 6),
          _TotalRow(
            label: 'Toplam Yevmiye',
            amount: report.totalWages,
            color: _accent,
          ),
          const SizedBox(height: 24),
        ],

        // Gider kategorileri
        if (report.expenseCategories.isNotEmpty) ...[
          _SectionHeader(
            icon: Icons.receipt_long_rounded,
            title: 'Gider Kalemleri',
            trailing: formatMoney(report.totalExpenses),
          ),
          const SizedBox(height: 10),
          _ExpenseCategoryList(categories: report.expenseCategories),
          const SizedBox(height: 24),
        ],

        // Boş durumlar
        if (report.workerRows.isEmpty && report.expenseCategories.isEmpty)
          _EmptyState(siteName: report.site.name),

        // Genel toplam
        if (report.workerRows.isNotEmpty || report.expenseCategories.isNotEmpty)
          _GrandTotalCard(report: report),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tarih aralığı
// ---------------------------------------------------------------------------

class _DateRangeChip extends StatelessWidget {
  const _DateRangeChip({required this.first, required this.last});

  final DateTime first;
  final DateTime last;

  @override
  Widget build(BuildContext context) {
    final sameDay = first.year == last.year &&
        first.month == last.month &&
        first.day == last.day;
    final label = sameDay
        ? formatDayMonth(first)
        : '${formatDate(first)} — ${formatDate(last)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFDCEEE6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.calendar_today_rounded,
            size: 14,
            color: Color(0xFF1A6B5A),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A6B5A),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Özet kartlar
// ---------------------------------------------------------------------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.report});

  final SiteReportData report;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            label: 'Toplam\nYevmiye',
            amount: report.totalWages,
            color: const Color(0xFF1A6B5A),
            bgColor: const Color(0xFFDCEEE6),
            icon: Icons.people_alt_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            label: 'Toplam\nGider',
            amount: report.totalExpenses,
            color: const Color(0xFFC04000),
            bgColor: const Color(0xFFFFF0E6),
            icon: Icons.receipt_long_rounded,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _SummaryCard(
            label: 'Genel\nToplam',
            amount: report.grandTotal,
            color: const Color(0xFF1A3A6B),
            bgColor: const Color(0xFFE6ECF8),
            icon: Icons.summarize_rounded,
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.bgColor,
    required this.icon,
  });

  final String label;
  final double amount;
  final Color color;
  final Color bgColor;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            formatMoney(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF1A6B5A)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1A6B5A),
            letterSpacing: 0.4,
          ),
        ),
        const Spacer(),
        if (trailing != null)
          Text(
            trailing!,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF888888),
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// İşçi tablosu
// ---------------------------------------------------------------------------

class _WorkerTable extends StatelessWidget {
  const _WorkerTable({required this.rows, required this.siteBonus});

  final List<SiteWorkerRow> rows;
  final double siteBonus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EDE9)),
      ),
      child: Column(
        children: [
          // Başlık satırı
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: const BoxDecoration(
              color: Color(0xFFF0F7F4),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                const Expanded(
                  flex: 5,
                  child: Text(
                    'ISCI',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A6B5A),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(
                  width: 44,
                  child: Text(
                    'GUN',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A6B5A),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                if (siteBonus > 0)
                  const SizedBox(
                    width: 48,
                    child: Text(
                      'PRIM',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A6B5A),
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                if (siteBonus > 0) const SizedBox(width: 6),
                const SizedBox(
                  width: 80,
                  child: Text(
                    'TUTAR',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A6B5A),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Satırlar
          ...rows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            final isLast = i == rows.length - 1;
            return _WorkerRow(
              row: row,
              siteBonus: siteBonus,
              isLast: isLast,
            );
          }),
        ],
      ),
    );
  }
}

class _WorkerRow extends StatelessWidget {
  const _WorkerRow({
    required this.row,
    required this.siteBonus,
    required this.isLast,
  });

  final SiteWorkerRow row;
  final double siteBonus;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final dayLabel = _buildDayLabel();

    return Container(
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(color: Color(0xFFEEF3F1), width: 1),
              ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          // İşçi adı + günlük ücret
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.workerName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF161616),
                  ),
                ),
                Text(
                  '${formatMoney(row.dailyWage)}/gun',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF888888),
                  ),
                ),
              ],
            ),
          ),
          // Gün
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(
                  dayLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF333333),
                  ),
                ),
                Text(
                  'gun',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Prim (varsa)
          if (siteBonus > 0)
            SizedBox(
              width: 48,
              child: Column(
                children: [
                  Text(
                    '+${siteBonus.toStringAsFixed(0)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2E9E82),
                    ),
                  ),
                  const Text(
                    'TL/gun',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: Color(0xFF999999)),
                  ),
                ],
              ),
            ),
          if (siteBonus > 0) const SizedBox(width: 6),
          // Toplam
          SizedBox(
            width: 80,
            child: Text(
              formatMoney(row.totalWage),
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161616),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildDayLabel() {
    if (row.halfDays == 0) return '${row.fullDays}';
    if (row.fullDays == 0) return '${row.halfDays}×½';
    return '${row.fullDays}+${row.halfDays}×½';
  }
}

// ---------------------------------------------------------------------------
// Toplam satırı
// ---------------------------------------------------------------------------

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.amount,
    required this.color,
  });

  final String label;
  final double amount;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          Text(
            formatMoney(amount),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Gider kategorileri
// ---------------------------------------------------------------------------

class _ExpenseCategoryList extends StatelessWidget {
  const _ExpenseCategoryList({required this.categories});

  final List<SiteExpenseCategory> categories;

  @override
  Widget build(BuildContext context) {
    final total =
        categories.fold<double>(0, (s, c) => s + c.total);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE8E3)),
      ),
      child: Column(
        children: categories.asMap().entries.map((entry) {
          final i = entry.key;
          final cat = entry.value;
          final isLast = i == categories.length - 1;
          final pct = total > 0 ? cat.total / total : 0.0;

          return Container(
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : const Border(
                      bottom: BorderSide(color: Color(0xFFF0EBE6), width: 1),
                    ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cat.category,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A1A1A),
                        ),
                      ),
                    ),
                    Text(
                      formatMoney(cat.total),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFC04000),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 4,
                    backgroundColor: const Color(0xFFF0EBE6),
                    valueColor: const AlwaysStoppedAnimation(Color(0xFFC04000)),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Genel toplam kartı
// ---------------------------------------------------------------------------

class _GrandTotalCard extends StatelessWidget {
  const _GrandTotalCard({required this.report});

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
              Container(
                width: 1,
                height: 36,
                color: Colors.white24,
              ),
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

// ---------------------------------------------------------------------------
// Boş durum
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.siteName});

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
