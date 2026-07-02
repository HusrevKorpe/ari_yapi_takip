import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/snackbar_helper.dart';
import '../../../shared/ui/app_confirm_dialog.dart';

Future<void> confirmDeleteWorker(
  BuildContext context,
  WidgetRef ref,
  Worker worker,
) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: 'Çalışanı Sil',
    message: 'Bu çalışan listeden kaldırılacak. Devam etmek istiyor musunuz?',
    detailTitle: worker.fullName,
  );
  if (!confirmed) return;

  await ref.read(workerRepositoryProvider).deactivateWorker(workerId: worker.id);

  if (context.mounted) {
    showSuccessSnackBar(context, 'Çalışan silindi.');
  }
}
