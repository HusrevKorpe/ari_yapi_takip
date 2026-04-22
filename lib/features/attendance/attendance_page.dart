import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/local/repositories.dart';
import '../../shared/attendance_status.dart';
import '../../shared/formatters.dart';
import '../../shared/month_utils.dart';
import '../../shared/snackbar_helper.dart';
import 'attendance_grid_page.dart';
import 'widgets/worker_attendance_card.dart';

final attendanceWorkersProvider = StreamProvider<List<Worker>>((ref) {
  return ref.watch(workerRepositoryProvider).watchActiveWorkers();
});

final attendanceByDateProvider =
    StreamProvider.autoDispose.family<List<AttendanceEntry>, DateTime>((
      ref,
      date,
    ) {
      return ref
          .watch(attendanceRepositoryProvider)
          .watchByDate(normalizeDay(date));
    });

final attendanceSitesProvider = StreamProvider<List<Site>>((ref) {
  return ref.watch(siteRepositoryProvider).watchActiveSites();
});

final selectedAttendanceDateProvider = StateProvider<DateTime>(
  (ref) => normalizeDay(DateTime.now()),
);

class AttendanceDraft {
  const AttendanceDraft({
    this.statusByWorker = const {},
    this.siteByWorker = const {},
    this.savedSuccessfully = false,
  });

  final Map<String, AttendanceStatus> statusByWorker;
  final Map<String, String?> siteByWorker;
  final bool savedSuccessfully;

  bool get isDirty =>
      statusByWorker.isNotEmpty || siteByWorker.isNotEmpty;

  AttendanceDraft copyWith({
    Map<String, AttendanceStatus>? statusByWorker,
    Map<String, String?>? siteByWorker,
    bool? savedSuccessfully,
  }) {
    return AttendanceDraft(
      statusByWorker: statusByWorker ?? this.statusByWorker,
      siteByWorker: siteByWorker ?? this.siteByWorker,
      savedSuccessfully: savedSuccessfully ?? this.savedSuccessfully,
    );
  }
}

class AttendanceDraftNotifier extends StateNotifier<AttendanceDraft> {
  AttendanceDraftNotifier() : super(const AttendanceDraft());

  void setStatus(String workerId, AttendanceStatus status) {
    state = state.copyWith(
      statusByWorker: {...state.statusByWorker, workerId: status},
      savedSuccessfully: false,
    );
  }

  void setSite(String workerId, String? siteId) {
    state = state.copyWith(
      siteByWorker: {...state.siteByWorker, workerId: siteId},
      savedSuccessfully: false,
    );
  }

  void reset() => state = const AttendanceDraft();

  void markSaved() => state = const AttendanceDraft(savedSuccessfully: true);
}

final attendanceDraftProvider =
    StateNotifierProvider<AttendanceDraftNotifier, AttendanceDraft>(
  (ref) => AttendanceDraftNotifier(),
);

class AttendancePage extends ConsumerWidget {
  const AttendancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedAttendanceDateProvider);
    final workersAsync = ref.watch(attendanceWorkersProvider);
    final entriesAsync = ref.watch(attendanceByDateProvider(selectedDate));
    final sitesAsync = ref.watch(attendanceSitesProvider);

    return Scaffold(
      appBar: _AttendanceAppBar(selectedDate: selectedDate),
      body: workersAsync.when(
        data: (workers) {
          return entriesAsync.when(
            data: (entries) {
              if (workers.isEmpty) {
                return const Center(
                  child: Text('Yoklama icin once calisan ekleyin.'),
                );
              }

              final existingByWorker = {
                for (final e in entries) e.workerId: e,
              };
              final sites = sitesAsync.valueOrNull ?? const <Site>[];

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                itemCount: workers.length,
                itemBuilder: (context, index) {
                  final worker = workers[index];
                  return _AttendanceCardConsumer(
                    worker: worker,
                    existing: existingByWorker[worker.id],
                    sites: sites,
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(error.toString())),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }
}

class _AttendanceCardConsumer extends ConsumerWidget {
  const _AttendanceCardConsumer({
    required this.worker,
    required this.existing,
    required this.sites,
  });

  final Worker worker;
  final AttendanceEntry? existing;
  final List<Site> sites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draftStatus = ref.watch(
      attendanceDraftProvider.select(
        (s) => s.statusByWorker.containsKey(worker.id)
            ? (hasKey: true, value: s.statusByWorker[worker.id])
            : (hasKey: false, value: null),
      ),
    );
    final draftSite = ref.watch(
      attendanceDraftProvider.select(
        (s) => s.siteByWorker.containsKey(worker.id)
            ? (hasKey: true, value: s.siteByWorker[worker.id])
            : (hasKey: false, value: null),
      ),
    );

    final selectedStatus = draftStatus.hasKey
        ? draftStatus.value
        : _statusFromEntry(existing);
    final selectedSiteId = draftSite.hasKey
        ? draftSite.value
        : existing?.siteId ?? worker.defaultSiteId;

    final notifier = ref.read(attendanceDraftProvider.notifier);

    return WorkerAttendanceCard(
      worker: worker,
      selectedStatus: selectedStatus,
      selectedSiteId: selectedSiteId,
      sites: sites,
      onStatusChanged: (status) => notifier.setStatus(worker.id, status),
      onSiteChanged: (siteId) => notifier.setSite(worker.id, siteId),
    );
  }
}

class _AttendanceAppBar extends ConsumerWidget
    implements PreferredSizeWidget {
  const _AttendanceAppBar({required this.selectedDate});

  final DateTime selectedDate;

  @override
  Size get preferredSize => const Size.fromHeight(84);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(attendanceDraftProvider);
    final isDirty = draft.isDirty;
    final savedSuccessfully = draft.savedSuccessfully;

    return AppBar(
      toolbarHeight: 84,
      titleSpacing: 12,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Yoklama',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            formatDate(selectedDate),
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: OutlinedButton.icon(
            onPressed: isDirty ? () => _save(context, ref) : null,
            icon: Icon(
              savedSuccessfully && !isDirty
                  ? Icons.check_rounded
                  : Icons.save_rounded,
              size: 17,
            ),
            label: Text(
              savedSuccessfully && !isDirty ? 'Kaydedildi' : 'Kaydet',
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: isDirty
                  ? const Color(0xFF8A7300)
                  : savedSuccessfully
                      ? const Color(0xFF2E7D32)
                      : const Color(0xFFAAAAAA),
              side: BorderSide(
                color: isDirty
                    ? const Color(0xFF8A7300)
                    : savedSuccessfully
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFCCCCCC),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AttendanceGridPage(),
              ),
            ),
            icon: const Icon(Icons.grid_on_rounded, size: 17),
            label: const Text('Cizelge'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8A7300),
              side: const BorderSide(color: Color(0xFF8A7300)),
              backgroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                letterSpacing: 0.2,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                firstDate: DateTime(2024),
                lastDate: DateTime(2100),
                initialDate: selectedDate,
              );
              if (picked != null) {
                ref.read(selectedAttendanceDateProvider.notifier).state =
                    normalizeDay(picked);
                ref.read(attendanceDraftProvider.notifier).reset();
              }
            },
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'Tarih sec',
          ),
        ),
      ],
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final selectedDate = ref.read(selectedAttendanceDateProvider);
    final draft = ref.read(attendanceDraftProvider);
    final workers = await ref.read(workerRepositoryProvider).getActiveWorkers();
    final existingEntries = await ref
        .read(attendanceRepositoryProvider)
        .watchByDate(selectedDate)
        .first;
    final sites =
        await ref.read(siteRepositoryProvider).watchActiveSites().first;

    final existingByWorker = {for (final e in existingEntries) e.workerId: e};
    final fallbackSiteId = sites.isNotEmpty ? sites.first.id : null;

    final inputs = <AttendanceInput>[];

    for (final worker in workers) {
      final status = draft.statusByWorker.containsKey(worker.id)
          ? draft.statusByWorker[worker.id]
          : _statusFromEntry(existingByWorker[worker.id]);

      if (status == null) continue;

      final resolvedSiteId = status.requiresSite
          ? (draft.siteByWorker[worker.id] ??
              existingByWorker[worker.id]?.siteId ??
              worker.defaultSiteId ??
              fallbackSiteId)
          : null;

      if (status.requiresSite && resolvedSiteId == null) {
        if (context.mounted) {
          showErrorSnackBar(
            context,
            'Geldi secimi icin varsayilan santiye bulunamadi. Once santiye ekleyin.',
          );
        }
        return;
      }

      inputs.add(
        AttendanceInput(
          workerId: worker.id,
          status: status,
          siteId: resolvedSiteId,
        ),
      );
    }

    try {
      await ref
          .read(attendanceRepositoryProvider)
          .saveDailyAttendance(date: selectedDate, entries: inputs);

      ref.read(attendanceDraftProvider.notifier).markSaved();
      if (context.mounted) {
        showSuccessSnackBar(context, 'Yoklama kaydedildi.');
      }
    } catch (e) {
      if (context.mounted) {
        showErrorSnackBar(context, _readableSaveError(e));
      }
    }
  }

  String _readableSaveError(Object error) {
    if (error is ArgumentError) {
      final message = error.message?.toString().trim();
      if (message != null && message.isNotEmpty) {
        return message;
      }
      return 'Yoklama kaydedilemedi.';
    }
    return 'Yoklama kaydedilirken bir hata olustu. Lutfen tekrar deneyin.';
  }
}

AttendanceStatus? _statusFromEntry(AttendanceEntry? entry) {
  if (entry == null) return null;
  final mapped = AttendanceStatusX.fromCode(entry.status);
  if (mapped == AttendanceStatus.worked ||
      mapped == AttendanceStatus.halfDay ||
      mapped == AttendanceStatus.absent) {
    return mapped;
  }
  return AttendanceStatus.absent;
}
