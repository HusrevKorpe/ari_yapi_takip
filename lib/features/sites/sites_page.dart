import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/ui/app_bar_add_button.dart';
import '../../shared/ui/empty_state_view.dart';
import '../../shared/ui/live_list_view.dart';
import 'site_notes_page.dart';
import 'site_report_page.dart';
import 'widgets/add_site_sheet.dart';
import 'widgets/delete_site_dialog.dart';
import 'widgets/edit_bonus_dialog.dart';
import 'widgets/site_tile.dart';

final sitesPageProvider = StreamProvider<List<Site>>((ref) {
  return ref.watch(siteRepositoryProvider).watchActiveSites();
});

class SitesPage extends ConsumerWidget {
  const SitesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sitesAsync = ref.watch(sitesPageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Şantiyeler'),
        actions: [
          AppBarAddButton(
            onPressed: () => showAddSiteSheet(context, ref),
          ),
        ],
      ),
      body: LiveListView<Site>(
        async: sitesAsync,
        idOf: (s) => s.id,
        emptyState: const EmptyStateView(
          icon: Icons.location_city_rounded,
          title: 'Henüz şantiye eklenmedi',
          message:
              'Sağ üstteki "Ekle" butonuna dokunarak yeni şantiye ekleyebilirsiniz.',
        ),
        itemBuilder: (context, site) => SiteTile(
          site: site,
          onDelete: () => confirmDeleteSite(context, ref, site),
          onEditBonus: () => showEditBonusDialog(context, ref, site),
          onReport: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SiteReportPage(
                siteId: site.id,
                siteName: site.name,
              ),
            ),
          ),
          onNotes: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SiteNotesPage(
                siteId: site.id,
                siteName: site.name,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

