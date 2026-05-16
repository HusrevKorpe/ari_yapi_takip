import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/design_tokens.dart';
import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/local/repositories.dart';
import '../../shared/attendance_status.dart';
import '../../shared/month_utils.dart';
import '../../shared/snackbar_helper.dart';
import '../../shared/ui/empty_state_view.dart';
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
    this.secondSiteByWorker = const {},
    this.savedSuccessfully = false,
  });

  final Map<String, AttendanceStatus?> statusByWorker;
  final Map<String, String?> siteByWorker;
  final Map<String, String?> secondSiteByWorker;
  final bool savedSuccessfully;

  bool get isDirty =>
      statusByWorker.isNotEmpty ||
      siteByWorker.isNotEmpty ||
      secondSiteByWorker.isNotEmpty;

  AttendanceDraft copyWith({
    Map<String, AttendanceStatus?>? statusByWorker,
    Map<String, String?>? siteByWorker,
    Map<String, String?>? secondSiteByWorker,
    bool? savedSuccessfully,
  }) {
    return AttendanceDraft(
      statusByWorker: statusByWorker ?? this.statusByWorker,
      siteByWorker: siteByWorker ?? this.siteByWorker,
      secondSiteByWorker: secondSiteByWorker ?? this.secondSiteByWorker,
      savedSuccessfully: savedSuccessfully ?? this.savedSuccessfully,
    );
  }
}

class AttendanceDraftNotifier extends StateNotifier<AttendanceDraft> {
  AttendanceDraftNotifier() : super(const AttendanceDraft());

  void setStatus(String workerId, AttendanceStatus? status) {
    final next = <String, AttendanceStatus?>{
      ...state.statusByWorker,
      workerId: status,
    };
    // Tam gün dışındaki durumlarda ikinci şantiye temizlensin.
    final clearedSecond = status == AttendanceStatus.worked
        ? state.secondSiteByWorker
        : {...state.secondSiteByWorker, workerId: null};
    // Durum kaldırıldıysa şantiye seçimi de temizlensin.
    final clearedSite = status == null
        ? {...state.siteByWorker, workerId: null}
        : state.siteByWorker;
    state = state.copyWith(
      statusByWorker: next,
      siteByWorker: clearedSite,
      secondSiteByWorker: clearedSecond,
      savedSuccessfully: false,
    );
  }

  void setSite(String workerId, String? siteId) {
    final currentSecond = state.secondSiteByWorker.containsKey(workerId)
        ? state.secondSiteByWorker[workerId]
        : null;
    final shouldClearSecond = currentSecond != null && currentSecond == siteId;
    state = state.copyWith(
      siteByWorker: {...state.siteByWorker, workerId: siteId},
      secondSiteByWorker: shouldClearSecond
          ? {...state.secondSiteByWorker, workerId: null}
          : state.secondSiteByWorker,
      savedSuccessfully: false,
    );
  }

  void setSecondSite(String workerId, String? siteId) {
    state = state.copyWith(
      secondSiteByWorker: {...state.secondSiteByWorker, workerId: siteId},
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
      appBar: AppBar(
        title: const Text('Yoklama'),
        actions: [
          _SaveAction(selectedDate: selectedDate),
          IconButton(
            tooltip: 'Aylık çizelge',
            icon: const Icon(Icons.grid_on_rounded),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AttendanceGridPage(),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: workersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Hata: $error')),
        data: (workers) {
          return entriesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text('Hata: $error')),
            data: (entries) {
              final sites = sitesAsync.valueOrNull ?? const <Site>[];

              return Column(
                children: [
                  _DateBar(selectedDate: selectedDate),
                  _SummaryStrip(
                    workers: workers,
                    entries: entries,
                  ),
                  Expanded(
                    child: workers.isEmpty
                        ? const EmptyStateView(
                            icon: Icons.groups_2_rounded,
                            title: 'Henüz çalışan yok',
                            message:
                                'Yoklama almak için önce Çalışanlar sekmesinden çalışan ekleyin.',
                            padding: EdgeInsets.all(AppSpacing.xxl),
                          )
                        : _WorkerList(
                            workers: workers,
                            entries: entries,
                            sites: sites,
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Tarih navigatörü: prev / Bugün etiketi / next + takvim ikonu.
class _DateBar extends ConsumerWidget {
  const _DateBar({required this.selectedDate});

  final DateTime selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = normalizeDay(DateTime.now());
    final isToday = selectedDate == today;
    final isYesterday =
        selectedDate == today.subtract(const Duration(days: 1));
    final dayLabel = isToday
        ? 'Bugün'
        : isYesterday
            ? 'Dün'
            : DateFormat('EEEE', 'tr_TR').format(selectedDate);
    final dateLabel = DateFormat('d MMMM yyyy', 'tr_TR').format(selectedDate);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          _DateArrow(
            icon: Icons.chevron_left_rounded,
            onTap: () => _changeBy(context, ref, days: -1),
          ),
          Expanded(
            child: Center(
              child: InkWell(
                onTap: () => _pickDate(context, ref),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dayLabel,
                        style: AppTextStyles.bodyStrong.copyWith(
                          color: isToday
                              ? AppColors.brand
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateLabel,
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          _DateArrow(
            icon: Icons.chevron_right_rounded,
            onTap: () => _changeBy(context, ref, days: 1),
          ),
        ],
      ),
    );
  }

  Future<void> _changeBy(BuildContext context, WidgetRef ref,
      {required int days}) async {
    final newDate = selectedDate.add(Duration(days: days));
    await _safeChangeDate(context, ref, newDate);
  }

  Future<void> _pickDate(BuildContext context, WidgetRef ref) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime(2100),
      initialDate: selectedDate,
      locale: const Locale('tr', 'TR'),
    );
    if (picked == null) return;
    if (!context.mounted) return;
    await _safeChangeDate(context, ref, normalizeDay(picked));
  }

  Future<void> _safeChangeDate(
    BuildContext context,
    WidgetRef ref,
    DateTime newDate,
  ) async {
    final draft = ref.read(attendanceDraftProvider);
    if (draft.isDirty) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Kaydedilmemiş değişiklikler'),
          content: const Text(
            'Bu günde kaydedilmemiş değişiklikler var. Tarihi değiştirirseniz değişiklikler kaybolacak.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Değişiklikleri at'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    ref.read(selectedAttendanceDateProvider.notifier).state = newDate;
    ref.read(attendanceDraftProvider.notifier).reset();
  }
}

class _DateArrow extends StatelessWidget {
  const _DateArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceMuted,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, size: 24, color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

/// Üst özet sayaç: geldi / yarım gün / gelmedi / işlenmemiş.
class _SummaryStrip extends ConsumerWidget {
  const _SummaryStrip({required this.workers, required this.entries});

  final List<Worker> workers;
  final List<AttendanceEntry> entries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(attendanceDraftProvider);

    int worked = 0;
    int halfDay = 0;
    int absent = 0;
    int pending = 0;

    final existingByWorker = {for (final e in entries) e.workerId: e};

    for (final worker in workers) {
      final status = draft.statusByWorker.containsKey(worker.id)
          ? draft.statusByWorker[worker.id]
          : _statusFromEntry(existingByWorker[worker.id]);

      switch (status) {
        case AttendanceStatus.worked:
          worked++;
        case AttendanceStatus.halfDay:
          halfDay++;
        case AttendanceStatus.absent:
          absent++;
        case AttendanceStatus.leave:
          pending++;
        case null:
          pending++;
      }
    }

    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryTile(
              count: worked,
              label: 'Geldi',
              color: AppColors.success,
              icon: Icons.check_circle_rounded,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _SummaryTile(
              count: halfDay,
              label: 'Yarım',
              color: AppColors.warning,
              icon: Icons.contrast_rounded,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _SummaryTile(
              count: absent,
              label: 'Gelmedi',
              color: AppColors.danger,
              icon: Icons.cancel_rounded,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _SummaryTile(
              count: pending,
              label: 'Bekliyor',
              color: AppColors.textTertiary,
              icon: Icons.help_outline_rounded,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.count,
    required this.label,
    required this.color,
    required this.icon,
  });

  final int count;
  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: AppTextStyles.bodyStrong.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// AppBar aksiyonu: Kaydet (taslak değiştiyse aktif, son kaydet başarılıysa
/// onay rengiyle gösterilir).
class _SaveAction extends ConsumerWidget {
  const _SaveAction({required this.selectedDate});

  final DateTime selectedDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final draft = ref.watch(attendanceDraftProvider);
    final isDirty = draft.isDirty;
    final showSaved = draft.savedSuccessfully && !isDirty;

    final iconColor = showSaved
        ? AppColors.success
        : isDirty
            ? AppColors.brand
            : null;

    return IconButton(
      tooltip: showSaved ? 'Kaydedildi' : 'Kaydet',
      onPressed: isDirty ? () => _save(context, ref) : null,
      icon: Icon(
        showSaved ? Icons.check_circle_rounded : Icons.save_rounded,
        color: iconColor,
      ),
    );
  }

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final draft = ref.read(attendanceDraftProvider);
    final workers =
        await ref.read(workerRepositoryProvider).getActiveWorkers();
    final existingEntries = await ref
        .read(attendanceRepositoryProvider)
        .watchByDate(selectedDate)
        .first;
    final existingByWorker = {for (final e in existingEntries) e.workerId: e};

    final inputs = <AttendanceInput>[];
    final toClearWorkerIds = <String>[];

    for (final worker in workers) {
      final status = draft.statusByWorker.containsKey(worker.id)
          ? draft.statusByWorker[worker.id]
          : _statusFromEntry(existingByWorker[worker.id]);

      if (status == null) {
        if (existingByWorker.containsKey(worker.id)) {
          toClearWorkerIds.add(worker.id);
        }
        continue;
      }

      final resolvedSiteId = status.requiresSite
          ? (draft.siteByWorker.containsKey(worker.id)
              ? draft.siteByWorker[worker.id]
              : existingByWorker[worker.id]?.siteId)
          : null;
      final rawSecondSiteId = status == AttendanceStatus.worked
          ? (draft.secondSiteByWorker.containsKey(worker.id)
              ? draft.secondSiteByWorker[worker.id]
              : existingByWorker[worker.id]?.secondSiteId)
          : null;
      final resolvedSecondSiteId =
          (rawSecondSiteId != null && rawSecondSiteId != resolvedSiteId)
              ? rawSecondSiteId
              : null;

      inputs.add(
        AttendanceInput(
          workerId: worker.id,
          status: status,
          siteId: resolvedSiteId,
          secondSiteId: resolvedSecondSiteId,
        ),
      );
    }

    try {
      final repo = ref.read(attendanceRepositoryProvider);
      if (toClearWorkerIds.isNotEmpty) {
        await repo.deleteEntriesForWorkers(
          date: selectedDate,
          workerIds: toClearWorkerIds,
        );
      }
      await repo.saveDailyAttendance(date: selectedDate, entries: inputs);

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
    return 'Yoklama kaydedilirken bir hata oluştu. Lütfen tekrar deneyin.';
  }
}

class _WorkerList extends ConsumerWidget {
  const _WorkerList({
    required this.workers,
    required this.entries,
    required this.sites,
  });

  final List<Worker> workers;
  final List<AttendanceEntry> entries;
  final List<Site> sites;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final existingByWorker = {for (final e in entries) e.workerId: e};

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xxl,
      ),
      itemCount: workers.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final worker = workers[index];
        return _AttendanceCardConsumer(
          worker: worker,
          existing: existingByWorker[worker.id],
          sites: sites,
        );
      },
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
    final draftSecondSite = ref.watch(
      attendanceDraftProvider.select(
        (s) => s.secondSiteByWorker.containsKey(worker.id)
            ? (hasKey: true, value: s.secondSiteByWorker[worker.id])
            : (hasKey: false, value: null),
      ),
    );

    final selectedStatus = draftStatus.hasKey
        ? draftStatus.value
        : _statusFromEntry(existing);
    final selectedSiteId = draftSite.hasKey
        ? draftSite.value
        : existing?.siteId;
    final selectedSecondSiteId = draftSecondSite.hasKey
        ? draftSecondSite.value
        : existing?.secondSiteId;

    final notifier = ref.read(attendanceDraftProvider.notifier);

    return WorkerAttendanceCard(
      worker: worker,
      selectedStatus: selectedStatus,
      selectedSiteId: selectedSiteId,
      selectedSecondSiteId: selectedSecondSiteId,
      sites: sites,
      onStatusChanged: (status) => notifier.setStatus(worker.id, status),
      onSiteChanged: (siteId) => notifier.setSite(worker.id, siteId),
      onSecondSiteChanged: (siteId) =>
          notifier.setSecondSite(worker.id, siteId),
    );
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
