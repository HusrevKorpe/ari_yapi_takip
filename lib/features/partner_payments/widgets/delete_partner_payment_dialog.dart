import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/snackbar_helper.dart';
import '../../../shared/ui/app_confirm_dialog.dart';

Future<void> confirmDeletePartnerPayment(
  BuildContext context,
  WidgetRef ref, {
  required PartnerPayment payment,
}) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: 'Ortak Ödemesini Sil',
    message: 'Bu kayıt kalıcı olarak silinecek. Devam etmek istiyor musunuz?',
    detailTitle: payment.partnerName,
    detailAmount: payment.amount,
    detailNote: payment.description,
  );
  if (!confirmed) return;

  await ref
      .read(partnerPaymentRepositoryProvider)
      .deletePartnerPayment(paymentId: payment.id);

  if (context.mounted) {
    showSuccessSnackBar(context, 'Ortak ödemesi silindi.');
  }
}
