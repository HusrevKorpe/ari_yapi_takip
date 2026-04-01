import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../data/local/repositories.dart';
import '../../shared/attendance_status.dart';
import '../../shared/formatters.dart';
import '../../shared/month_utils.dart';
import '../../shared/snackbar_helper.dart';

final attendanceWorkersProvider = StreamProvider<List<Worker>>((ref) {
  return ref.watch(workerRepositoryProvider).watchActiveWorkers();
});

final attendanceByDateProvider =
    StreamProvider.family<List<AttendanceEntry>, DateTime>((ref, date) {
      return ref
          .watch(attendanceRepositoryProvider)
          .watchByDate(normalizeDay(date));
    });

final attendanceSitesProvider = StreamProvider<List<Site>>((ref) {
  return ref.watch(siteRepositoryProvider).watchActiveSites();
});

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});

  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  DateTime _selectedDate = normalizeDay(DateTime.now());
  final Map<String, AttendanceStatus> _statusByWorker = {};
  final Map<String, String?> _siteByWorker = {};

  @override
  Widget build(BuildContext context) {
    final workersAsync = ref.watch(attendanceWorkersProvider);
    final entriesAsync = ref.watch(attendanceByDateProvider(_selectedDate));
    final sitesAsync = ref.watch(attendanceSitesProvider);

    return Scaffold(
      appBar: _buildAppBar(context),
      body: workersAsync.when(
        data: (workers) {
          return entriesAsync.when(
            data: (entries) {
              if (workers.isEmpty) {
                return const Center(
                  child: Text('Yoklama icin once calisan ekleyin.'),
                );
              }

              final existingByWorker = {for (final e in entries) e.workerId: e};
              final sites = sitesAsync.valueOrNull ?? [];

              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                itemCount: workers.length,
                itemBuilder: (context, index) {
                  final worker = workers[index];
                  final existing = existingByWorker[worker.id];

                  final selectedStatus = _statusByWorker.containsKey(worker.id)
                      ? _statusByWorker[worker.id]
                      : _statusFromEntry(existing);

                  final selectedSiteId = _siteByWorker.containsKey(worker.id)
                      ? _siteByWorker[worker.id]
                      : existing?.siteId ?? worker.defaultSiteId;

                  return _WorkerAttendanceCard(
                    worker: worker,
                    selectedStatus: selectedStatus,
                    selectedSiteId: selectedSiteId,
                    sites: sites,
                    onStatusChanged: (status) {
                      setState(() {
                        _statusByWorker[worker.id] = status;
                      });
                    },
                    onSiteChanged: (siteId) {
                      setState(() {
                        _siteByWorker[worker.id] = siteId;
                      });
                    },
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

  PreferredSizeWidget _buildAppBar(BuildContext context) {
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
            formatDate(_selectedDate),
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _save(context, ref),
          icon: const Icon(Icons.save_outlined, size: 18),
          label: const Text('Kaydet'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF0A7A5C),
            textStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
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
                initialDate: _selectedDate,
              );
              if (picked != null) {
                setState(() {
                  _selectedDate = normalizeDay(picked);
                  _statusByWorker.clear();
                  _siteByWorker.clear();
                });
              }
            },
            icon: const Icon(Icons.calendar_month_rounded),
            tooltip: 'Tarih sec',
          ),
        ),
      ],
    );
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

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final workers = await ref.read(workerRepositoryProvider).getActiveWorkers();
    final existingEntries = await ref
        .read(attendanceRepositoryProvider)
        .watchByDate(_selectedDate)
        .first;
    final sites = await ref
        .read(siteRepositoryProvider)
        .watchActiveSites()
        .first;

    final existingByWorker = {for (final e in existingEntries) e.workerId: e};
    final fallbackSiteId = sites.isNotEmpty ? sites.first.id : null;

    final inputs = <AttendanceInput>[];

    for (final worker in workers) {
      final status = _statusByWorker.containsKey(worker.id)
          ? _statusByWorker[worker.id]
          : _statusFromEntry(existingByWorker[worker.id]);

      if (status == null) continue;

      final resolvedSiteId = status.requiresSite
          ? (_siteByWorker[worker.id] ??
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
          .saveDailyAttendance(date: _selectedDate, entries: inputs);

      if (context.mounted) {
        showSuccessSnackBar(context, 'Yoklama kaydedildi.');
      }
    } catch (e) {
      if (context.mounted) {
        final message = _readableSaveError(e);
        showErrorSnackBar(context, message);
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

class _WorkerAttendanceCard extends StatelessWidget {
  const _WorkerAttendanceCard({
    required this.worker,
    required this.selectedStatus,
    required this.selectedSiteId,
    required this.sites,
    required this.onStatusChanged,
    required this.onSiteChanged,
  });

  final Worker worker;
  final AttendanceStatus? selectedStatus;
  final String? selectedSiteId;
  final List<Site> sites;
  final ValueChanged<AttendanceStatus> onStatusChanged;
  final ValueChanged<String?> onSiteChanged;

  @override
  Widget build(BuildContext context) {
    final presentSelected = selectedStatus == AttendanceStatus.worked;
    final absentSelected = selectedStatus == AttendanceStatus.absent;
    final halfDaySelected = selectedStatus == AttendanceStatus.halfDay;
    final showSites = (presentSelected || halfDaySelected) && sites.isNotEmpty;

    final accent = presentSelected
        ? const Color(0xFF0C8A7A)
        : absentSelected
        ? const Color(0xFFC62828)
        : halfDaySelected
        ? const Color(0xFFE67E00)
        : const Color(0xFF8D8D8D);

    final subtitle = (worker.notes ?? '').trim().isEmpty
        ? 'CALISAN'
        : worker.notes!.trim().toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: accent, width: 2.8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 6,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8E8E8),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials(worker.fullName),
                    style: const TextStyle(
                      color: Color(0xFF6F6F6F),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        worker.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7A7A7A),
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatusButton(
                    label: 'GELDI',
                    selected: presentSelected,
                    selectedColor: const Color(0xFF4CAF50),
                    onTap: () => onStatusChanged(AttendanceStatus.worked),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatusButton(
                    label: 'YARIM GUN',
                    selected: halfDaySelected,
                    selectedColor: const Color(0xFFE67E00),
                    selectedTextColor: Colors.white,
                    onTap: () => onStatusChanged(AttendanceStatus.halfDay),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _StatusButton(
                    label: 'GELMEDI',
                    selected: absentSelected,
                    selectedColor: const Color(0xFFC62828),
                    selectedTextColor: Colors.white,
                    onTap: () => onStatusChanged(AttendanceStatus.absent),
                  ),
                ),
              ],
            ),
            if (showSites) ...[
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: sites.map((site) {
                    final isSelected = selectedSiteId == site.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _SiteChip(
                        label: site.name,
                        selected: isSelected,
                        onTap: () => onSiteChanged(isSelected ? null : site.id),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '--';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

class _SiteChip extends StatelessWidget {
  const _SiteChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1A6B5A) : const Color(0xFFEEEEEE),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : const Color(0xFF666666),
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }
}

class _StatusButton extends StatelessWidget {
  const _StatusButton({
    required this.label,
    required this.selected,
    required this.selectedColor,
    required this.onTap,
    this.selectedTextColor,
  });

  final String label;
  final bool selected;
  final Color selectedColor;
  final Color? selectedTextColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final background = selected ? selectedColor : const Color(0xFFE7E7E7);
    final textColor = selected
        ? (selectedTextColor ?? const Color(0xFF444444))
        : const Color(0xFF767676);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ),
    );
  }
}
