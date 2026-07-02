import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/snackbar_helper.dart';
import '../../../shared/ui/app_confirm_dialog.dart';

Future<void> confirmDeleteExpense(
  BuildContext context,
  WidgetRef ref, {
  required Expense expense,
}) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: 'Gideri Sil',
    message: 'Bu kayıt kalıcı olarak silinecek. Devam etmek istiyor musunuz?',
    detailTitle: expense.category,
    detailAmount: expense.amount,
    detailNote: expense.description,
  );
  if (!confirmed) return;

  await ref.read(expenseRepositoryProvider).deleteExpense(expenseId: expense.id);

  if (context.mounted) {
    showSuccessSnackBar(context, 'Gider silindi.');
  }
}
