import 'package:flutter/material.dart';

import '../../app/design_tokens.dart';

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
  });

  final IconData icon;
  final String title;
  final String message;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brandSurface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Icon(
                icon,
                color: AppColors.brand,
                size: 32,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: AppTextStyles.cardTitle),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
          ],
        ),
      ),
    );
  }
}
