import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/ui/snackbar_helper.dart';

const _accent = Color(0xFF1A6B5A);
const _accentDark = Color(0xFF0F4F42);
const _paper = Color(0xFFFFFCF3);
const _paperBorder = Color(0xFFE7DDBE);
const _ink = Color(0xFF1E1A12);
const _inkSoft = Color(0xFF6E6856);

Future<void> showNoteEditorSheet(
  BuildContext context,
  WidgetRef ref, {
  required String siteId,
  SiteNote? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (sheetContext) => _NoteEditor(
      ref: ref,
      siteId: siteId,
      existing: existing,
    ),
  );
}

class _NoteEditor extends StatefulWidget {
  const _NoteEditor({
    required this.ref,
    required this.siteId,
    required this.existing,
  });

  final WidgetRef ref;
  final String siteId;
  final SiteNote? existing;

  @override
  State<_NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<_NoteEditor> {
  late final TextEditingController _contentController;
  late DateTime _selectedDate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _contentController =
        TextEditingController(text: widget.existing?.content ?? '');
    _selectedDate = widget.existing?.noteDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _accent,
            onPrimary: Colors.white,
            surface: _paper,
            onSurface: _ink,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      showErrorSnackBar(context, 'Lütfen bir not yazın.');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      await widget.ref.read(siteNoteRepositoryProvider).saveNote(
            id: widget.existing?.id,
            siteId: widget.siteId,
            noteDate: _selectedDate,
            content: content,
          );
      if (!mounted) return;
      Navigator.pop(context);
      showSuccessSnackBar(
        context,
        _isEditing ? 'Not güncellendi.' : 'Not eklendi.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showErrorSnackBar(context, 'Kaydedilemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: viewInsets),
      child: Container(
        margin: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _paper,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: _paperBorder),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 30,
              offset: Offset(0, 14),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Handle(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_accent, _accentDark],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x331A6B5A),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        _isEditing
                            ? Icons.edit_note_rounded
                            : Icons.note_add_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isEditing ? 'Notu Düzenle' : 'Yeni Not',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: _ink,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _isEditing
                                ? 'Mevcut notu güncelliyorsun'
                                : 'Yeni bir günlük girişi oluştur',
                            style: const TextStyle(
                              fontSize: 12,
                              color: _inkSoft,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _DatePill(
                  date: _selectedDate,
                  onTap: _saving ? null : _pickDate,
                ),
                const SizedBox(height: 14),
                _NoteField(
                  controller: _contentController,
                  autofocus: !_isEditing,
                  enabled: !_saving,
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: _inkSoft,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          backgroundColor: const Color(0xFFEFE9D5),
                        ),
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        child: const Text(
                          'Vazgeç',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [_accent, _accentDark],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x401A6B5A),
                              blurRadius: 14,
                              offset: Offset(0, 6),
                            ),
                          ],
                        ),
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: Colors.white,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: _saving ? null : _save,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor:
                                        AlwaysStoppedAnimation(Colors.white),
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: const [
                                    Icon(Icons.check_rounded, size: 20),
                                    SizedBox(width: 6),
                                    Text(
                                      'Kaydet',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 15,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 5,
        decoration: BoxDecoration(
          color: const Color(0xFFD3CAB0),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _DatePill extends StatelessWidget {
  const _DatePill({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFFFFEF8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _paperBorder),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3F0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    date.day.toString(),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: _accent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _monthShort(date.month).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                      letterSpacing: 0.6,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(date),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _weekday(date),
                    style: const TextStyle(
                      fontSize: 12,
                      color: _inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_calendar_rounded,
                color: _inkSoft, size: 20),
          ],
        ),
      ),
    );
  }
}

class _NoteField extends StatelessWidget {
  const _NoteField({
    required this.controller,
    required this.autofocus,
    required this.enabled,
  });

  final TextEditingController controller;
  final bool autofocus;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFEF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _paperBorder),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: TextField(
        controller: controller,
        autofocus: autofocus,
        enabled: enabled,
        minLines: 5,
        maxLines: 12,
        textCapitalization: TextCapitalization.sentences,
        inputFormatters: [LengthLimitingTextInputFormatter(2000)],
        style: const TextStyle(
          fontSize: 15,
          height: 1.45,
          color: _ink,
          fontWeight: FontWeight.w500,
        ),
        decoration: const InputDecoration(
          isCollapsed: true,
          contentPadding: EdgeInsets.symmetric(vertical: 6),
          border: InputBorder.none,
          hintText: 'Bugün ne oldu? Detayları, gözlemleri yaz…',
          hintStyle: TextStyle(
            color: Color(0xFFB5AC8C),
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

String _formatDate(DateTime d) {
  const months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _monthShort(int month) {
  const months = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];
  return months[month - 1];
}

String _weekday(DateTime d) {
  const days = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe',
    'Cuma', 'Cumartesi', 'Pazar',
  ];
  return days[d.weekday - 1];
}
