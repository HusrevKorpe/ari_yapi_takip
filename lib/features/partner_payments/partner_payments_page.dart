import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/design_tokens.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/ui/live_list.dart';
import '../../shared/ui/total_summary_card.dart';
import 'widgets/add_partner_payment_sheet.dart';
import 'widgets/delete_partner_payment_dialog.dart';
import 'widgets/partner_payment_row_card.dart';

class PartnerPaymentsPage extends ConsumerWidget {
  const PartnerPaymentsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(allPartnerPaymentsProvider);

    return Scaffold(
      body: LiveList<PartnerPayment>(
        async: payments,
        idOf: (p) => p.id,
        builder: (context, items, onRefresh) {
          final totalAmount = items.fold<double>(
            0,
            (sum, payment) => sum + payment.amount,
          );

          return RefreshIndicator(
            onRefresh: onRefresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
                100,
              ),
              children: [
                TotalSummaryCard(
                  label: 'Toplam Ortak Ödemesi',
                  amount: totalAmount,
                  icon: Icons.handshake_rounded,
                  accent: AppColors.info,
                ),
                const SizedBox(height: AppSpacing.md),
                if (items.isEmpty)
                  const _EmptyState()
                else
                  ...items.map(
                    (payment) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: PartnerPaymentRowCard(
                        payment: payment,
                        accent: AppColors.info,
                        onEdit: () => showAddPartnerPaymentSheet(
                          context,
                          ref,
                          existing: payment,
                        ),
                        onDelete: () => confirmDeletePartnerPayment(
                          context,
                          ref,
                          payment: payment,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddPartnerPaymentSheet(context, ref),
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.textOnBrand,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Ödeme Ekle'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: const Center(
        child: Text(
          'Henüz ortak ödemesi kaydı yok.',
          style: AppTextStyles.body,
        ),
      ),
    );
  }
}
