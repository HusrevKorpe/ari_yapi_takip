import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../shared/ui/live_list.dart';
import '../workers/workers_page.dart';
import 'widgets/worker_payroll_card.dart';
import 'widgets/worker_payroll_sheet.dart';

class PayrollPage extends ConsumerWidget {
  const PayrollPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Maas')),
      body: LiveList<Worker>(
        async: workersAsync,
        idOf: (w) => w.id,
        builder: (context, workers, onRefresh) {
          return RefreshIndicator(
            onRefresh: onRefresh,
            child: workers.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text('Maas hesaplamak icin calisan ekleyin.'),
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: workers.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final worker = workers[index];
                      return WorkerPayrollCard(
                        worker: worker,
                        onTap: () => _openWorkerSheet(context, worker),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }

  void _openWorkerSheet(BuildContext context, Worker worker) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkerPayrollSheet(worker: worker),
    );
  }
}
