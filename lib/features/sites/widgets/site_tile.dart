import 'package:flutter/material.dart';

import '../../../data/local/app_database.dart';

const _cardBg = Color(0xFFF5F5F6);
const _accent = Color(0xFF1A6B5A);

class SiteTile extends StatelessWidget {
  const SiteTile({
    super.key,
    required this.site,
    required this.onDelete,
    required this.onEditBonus,
    required this.onReport,
  });

  final Site site;
  final VoidCallback onDelete;
  final VoidCallback onEditBonus;
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    final hasBonus = site.dailyBonus > 0;

    return Container(
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: hasBonus ? 84 : 72,
            decoration: const BoxDecoration(
              color: _accent,
              borderRadius: BorderRadius.horizontal(left: Radius.circular(14)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD8EEE9),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      site.code,
                      style: const TextStyle(
                        color: _accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          site.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (hasBonus) ...[
                          const SizedBox(height: 3),
                          Text(
                            '+${site.dailyBonus.toStringAsFixed(0)} TL / gun',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: onReport,
                    icon: const Icon(
                      Icons.bar_chart_rounded,
                      color: _accent,
                    ),
                    tooltip: 'Rapor Gör',
                    iconSize: 22,
                  ),
                  IconButton(
                    onPressed: onEditBonus,
                    icon: const Icon(Icons.edit, color: Color(0xFF888888)),
                    tooltip: 'Prim Duzenle',
                    iconSize: 20,
                  ),
                  IconButton(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete, color: Color(0xFFC81616)),
                    tooltip: 'Santiyeyi Sil',
                    iconSize: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
