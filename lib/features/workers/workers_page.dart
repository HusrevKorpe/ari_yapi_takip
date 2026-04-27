import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/ui/live_list.dart';
import 'widgets/add_worker_sheet.dart';
import 'widgets/delete_worker_dialog.dart';
import 'widgets/worker_tile.dart';
import 'worker_detail_sheet.dart';

final workersProvider = StreamProvider<List<Worker>>((ref) {
  return ref.watch(workerRepositoryProvider).watchActiveWorkers();
});

const _accentGold = Color(0xFFD6B100);
const _accentGoldDark = Color(0xFF8A7300);

class WorkersPage extends ConsumerWidget {
  const WorkersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workers = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const Row(
          children: [
            Text(
              'Calisan Yonetimi',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161616),
              ),
            ),
            SizedBox(width: 10),
            Icon(Icons.groups_2_rounded, color: _accentGoldDark, size: 26),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [_accentGoldDark, _accentGold],
                ),
              ),
              child: FilledButton.icon(
                onPressed: () => showAddWorkerSheet(context, ref),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: const Color(0xFF171717),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text(
                  'Ekle',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ),
        ],
      ),
      body: LiveList<Worker>(
        async: workers,
        idOf: (w) => w.id,
        builder: (context, items, onRefresh) {
          return SafeArea(
            bottom: false,
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YONETIM PANELI',
                        style: TextStyle(
                          color: _accentGoldDark,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: onRefresh,
                    child: items.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: const [
                              SizedBox(height: 120),
                              Center(
                                child: Text('Henuz calisan eklenmedi.'),
                              ),
                            ],
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding:
                                const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final worker = items[index];
                              return WorkerTile(
                                worker: worker,
                                onTap: () =>
                                    _showWorkerDetail(context, worker),
                                onEdit: () => showAddWorkerSheet(
                                  context,
                                  ref,
                                  existing: worker,
                                ),
                                onDelete: () =>
                                    confirmDeleteWorker(context, ref, worker),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          );
        },
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
