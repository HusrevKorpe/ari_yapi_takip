import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/app_database.dart';
import '../../shared/ui/empty_state_view.dart';
import '../../shared/ui/live_list_view.dart';
import '../workers/workers_page.dart';
import 'widgets/worker_payroll_card.dart';
import 'widgets/worker_payroll_sheet.dart';

class PayrollPage extends ConsumerWidget {
  const PayrollPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(workersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Maaş')),
      body: LiveListView<Worker>(
        async: workersAsync,
        idOf: (w) => w.id,
        emptyState: const EmptyStateView(
          icon: Icons.payments_rounded,
          title: 'Maaş hesaplanacak çalışan yok',
          message: 'Önce Çalışanlar sekmesinden çalışan ekleyin.',
        ),
        itemBuilder: (context, worker) => WorkerPayrollCard(
          worker: worker,
          onTap: () => _openWorkerSheet(context, worker),
        ),
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

