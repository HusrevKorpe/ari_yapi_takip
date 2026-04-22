import 'package:flutter/material.dart';

import 'grid_constants.dart';

class GridLegend extends StatelessWidget {
  const GridLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (color: kGridGreen, icon: Icons.check_rounded, label: 'Calisti'),
      (color: kGridOrange, icon: Icons.remove_rounded, label: 'Yarim'),
      (color: kGridRed, icon: Icons.close_rounded, label: 'Gelmedi'),
      (color: kGridBlue, icon: Icons.pause_rounded, label: 'Izinli'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE8E8EA))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final item in items)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Icon(item.icon, size: 12, color: item.color),
                ),
                const SizedBox(width: 5),
                Text(
                  item.label,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
