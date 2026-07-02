import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/snackbar_helper.dart';
import '../../../shared/ui/app_confirm_dialog.dart';

Future<void> confirmDeleteSite(
  BuildContext context,
  WidgetRef ref,
  Site site,
) async {
  final confirmed = await showAppConfirmDialog(
    context,
    title: 'Şantiyeyi Sil',
    message: 'Bu şantiye listeden kaldırılacak. Devam etmek istiyor musunuz?',
    detailTitle: site.name,
  );
  if (!confirmed) return;

  await ref.read(siteRepositoryProvider).deactivateSite(siteId: site.id);

  if (context.mounted) {
    showSuccessSnackBar(context, 'Şantiye silindi.');
  }
}
