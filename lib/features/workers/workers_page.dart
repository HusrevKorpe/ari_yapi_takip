import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/ui/app_bar_add_button.dart';
import '../../shared/ui/empty_state_view.dart';
import '../../shared/ui/live_list_view.dart';
import 'widgets/add_worker_sheet.dart';
import 'widgets/delete_worker_dialog.dart';
import 'widgets/worker_tile.dart';
import 'worker_detail_sheet.dart';

final workersProvider = StreamProvider<List<Worker>>((ref) {
  return ref.watch(workerRepositoryProvider).watchActiveWorkers();
});

class WorkersPage extends ConsumerWidget {
  const WorkersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Çalışanlar'),
        actions: [
          AppBarAddButton(
            onPressed: () => showAddWorkerSheet(context, ref),
          ),
        ],
      ),
      body: LiveListView<Worker>(
        async: workers,
        idOf: (w) => w.id,
        emptyState: const EmptyStateView(
          icon: Icons.groups_2_rounded,
          title: 'Henüz çalışan eklenmedi',
          message:
              'Sağ üstteki "Ekle" butonuna dokunarak yeni çalışan ekleyebilirsiniz.',
        ),
        itemBuilder: (context, worker) => WorkerTile(
          worker: worker,
          onTap: () => _showWorkerDetail(context, worker),
          onEdit: () => showAddWorkerSheet(
            context,
            ref,
            existing: worker,
          ),
          onDelete: () => confirmDeleteWorker(context, ref, worker),
        ),
      ),
    );
  }

  void _showWorkerDetail(BuildContext context, Worker worker) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkerDetailSheet(worker: worker),
    );
  }
}

