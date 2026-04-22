import 'package:flutter/material.dart';

import '../../../../data/local/repositories.dart';
import '../../../../shared/formatters.dart';

class WorkerTable extends StatelessWidget {
  const WorkerTable({
    super.key,
    required this.rows,
    required this.siteBonus,
  });

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
          for (var i = 0; i < rows.length; i++)
            _WorkerRow(
              row: rows[i],
              siteBonus: siteBonus,
              isLast: i == rows.length - 1,
            ),
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
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Text(
                  _buildDayLabel(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF333333),
                  ),
                ),
                const Text(
                  'gun',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    color: Color(0xFF999999),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
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
