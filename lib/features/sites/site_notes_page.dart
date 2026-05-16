import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/app_database.dart';
import '../../shared/ui/live_list.dart';
import '../../shared/ui/snackbar_helper.dart';
import 'widgets/note_editor_sheet.dart';

const _accent = Color(0xFF1A6B5A);
const _accentDark = Color(0xFF0F4F42);
const _accentSoft = Color(0xFFEAF3F0);
const _paper = Color(0xFFFAF6E9);
const _paperDeep = Color(0xFFF5F5F6);
const _paperBorder = Color(0xFFE6E6E8);
const _ink = Color(0xFF1E1A12);
const _inkSoft = Color(0xFF6E6856);

final siteNotesProvider =
    StreamProvider.family<List<SiteNote>, String>((ref, siteId) {
  return ref.watch(siteNoteRepositoryProvider).watchNotesForSite(siteId);
});

class SiteNotesPage extends ConsumerWidget {
  const SiteNotesPage({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  final String siteId;
  final String siteName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notesAsync = ref.watch(siteNotesProvider(siteId));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: _ink,
        title: const Text(
          'Şantiye Notları',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: _ink,
          ),
        ),
      ),
      floatingActionButton: _AddNoteFab(
        onPressed: () => showNoteEditorSheet(
          context,
          ref,
          siteId: siteId,
        ),
      ),
      body: LiveList<SiteNote>(
        async: notesAsync,
        idOf: (n) => n.id,
        builder: (context, notes, onRefresh) {
          return RefreshIndicator(
            color: _accent,
            onRefresh: onRefresh,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _SiteHeader(
                    siteName: siteName,
                    noteCount: notes.length,
                  ),
                ),
                if (notes.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else
                  ..._buildGroupedSlivers(context, ref, notes),
                const SliverToBoxAdapter(child: SizedBox(height: 120)),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildGroupedSlivers(
    BuildContext context,
    WidgetRef ref,
    List<SiteNote> notes,
  ) {
    final groups = <String, List<SiteNote>>{};
    for (final n in notes) {
      final key = _monthKey(n.noteDate);
      groups.putIfAbsent(key, () => []).add(n);
    }

    final widgets = <Widget>[];
    groups.forEach((label, group) {
      widgets.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
          sliver: SliverToBoxAdapter(
            child: _MonthHeader(label: label, count: group.length),
          ),
        ),
      );
      widgets.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverList.separated(
            itemCount: group.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) => _NoteCard(
              note: group[i],
              accentIndex: i,
              onEdit: () => showNoteEditorSheet(
                context,
                ref,
                siteId: siteId,
                existing: group[i],
              ),
              onDelete: () => _confirmDelete(context, ref, group[i]),
            ),
          ),
        ),
      );
    });
    return widgets;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    SiteNote note,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _paper,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Notu sil',
          style: TextStyle(fontWeight: FontWeight.w800, color: _ink),
        ),
        content: const Text(
          'Bu not kalıcı olarak silinsin mi?',
          style: TextStyle(color: _inkSoft),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(foregroundColor: _inkSoft),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFC81616),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Sil',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(siteNoteRepositoryProvider).deleteNote(noteId: note.id);
      if (context.mounted) showSuccessSnackBar(context, 'Not silindi.');
    } catch (e) {
      if (context.mounted) showErrorSnackBar(context, 'Silinemedi: $e');
    }
  }

  String _monthKey(DateTime d) {
    const months = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

class _SiteHeader extends StatelessWidget {
  const _SiteHeader({required this.siteName, required this.noteCount});

  final String siteName;
  final int noteCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_accent, _accentDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x331A6B5A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.menu_book_rounded,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  siteName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  noteCount == 0
                      ? 'Henüz not yok'
                      : '$noteCount günlük girişi',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 18,
          decoration: BoxDecoration(
            color: _accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: _ink,
            letterSpacing: -0.1,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: _accentSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            count.toString(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _accent,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.accentIndex,
    required this.onEdit,
    required this.onDelete,
  });

  final SiteNote note;
  final int accentIndex;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final relative = _relativeLabel(note.noteDate);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onEdit,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFCFCFD),
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
                child: Row(
                  children: [
                    _DateChip(date: note.noteDate),
                    const SizedBox(width: 10),
                    if (relative != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _accentSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          relative,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: _accent,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ),
                    const Spacer(),
                    _IconAction(
                      icon: Icons.edit_outlined,
                      color: _inkSoft,
                      onTap: onEdit,
                    ),
                    _IconAction(
                      icon: Icons.delete_outline_rounded,
                      color: const Color(0xFFC81616),
                      onTap: onDelete,
                    ),
                  ],
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14),
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _paperBorder.withValues(alpha: 0),
                      _paperBorder,
                      _paperBorder.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Text(
                  note.content,
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    color: _ink,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _relativeLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    final diff = today.difference(target).inDays;
    if (diff == 0) return 'BUGÜN';
    if (diff == 1) return 'DÜN';
    if (diff > 1 && diff < 7) return '$diff GÜN ÖNCE';
    if (diff < 0) return 'PLANLI';
    return null;
  }
}

class _DateChip extends StatelessWidget {
  const _DateChip({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: _paperDeep,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            date.day.toString(),
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: _accent,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _monthShort(date.month).toUpperCase(),
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: _accentDark,
              letterSpacing: 0.6,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: _accentSoft,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(
              Icons.auto_stories_rounded,
              color: _accent,
              size: 46,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Henüz not yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _ink,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Şantiyenin günlüğünü buradan tut: gözlemler, talimatlar, '
            'önemli olaylar — hepsi tek bir yerde.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.5,
              color: _inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _AddNoteFab extends StatelessWidget {
  const _AddNoteFab({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [_accent, _accentDark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x401A6B5A),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton.extended(
        backgroundColor: Colors.transparent,
        elevation: 0,
        highlightElevation: 0,
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
        label: const Text(
          'Yeni Not',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

String _monthShort(int month) {
  const months = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];
  return months[month - 1];
}
