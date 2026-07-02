import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/design_tokens.dart';
import '../../../core/providers.dart';
import '../../../data/local/app_database.dart';
import '../../../shared/ui/app_form_sheet.dart';
import '../../../shared/ui/snackbar_helper.dart';

const _accent = AppColors.info;

Future<void> showAddPartnerPaymentSheet(
  BuildContext context,
  WidgetRef ref, {
  PartnerPayment? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PartnerPaymentSheet(existing: existing),
  );
}

class _PartnerPaymentSheet extends ConsumerStatefulWidget {
  const _PartnerPaymentSheet({this.existing});

  final PartnerPayment? existing;

  @override
  ConsumerState<_PartnerPaymentSheet> createState() =>
      _PartnerPaymentSheetState();
}

class _PartnerPaymentSheetState extends ConsumerState<_PartnerPaymentSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _descriptionController;
  final TextEditingController _newNameController = TextEditingController();

  late List<String> _names;
  String? _selectedName;
  bool _addingNew = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(0) : '',
    );
    _descriptionController = TextEditingController(
      text: existing != null ? (existing.description ?? '') : '',
    );

    _names = List<String>.from(ref.read(knownPartnerNamesProvider));

    if (existing != null) {
      final name = existing.partnerName.trim();
      if (name.isNotEmpty && !_names.contains(name)) {
        _names.insert(0, name);
      }
      _selectedName = name.isEmpty ? null : name;
      _addingNew = _names.isEmpty;
    } else if (_names.length == 1) {
      // Tek ortak → otomatik seçili gelsin.
      _selectedName = _names.first;
    } else if (_names.isEmpty) {
      // Hiç kayıt yoksa doğrudan isim yazma moduna geç.
      _addingNew = true;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _newNameController.dispose();
    super.dispose();
  }

  String get _effectiveName => _addingNew
      ? _newNameController.text.trim()
      : (_selectedName?.trim() ?? '');

  Future<void> _save() async {
    final amount =
        double.tryParse(_amountController.text.trim().replaceAll(',', '.')) ?? 0;
    final partnerName = _effectiveName;
    if (amount <= 0 || partnerName.isEmpty) return;

    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    try {
      final repo = ref.read(partnerPaymentRepositoryProvider);
      final existing = widget.existing;
      if (existing != null) {
        await repo.updatePartnerPayment(
          paymentId: existing.id,
          date: existing.paymentDate,
          amount: amount,
          partnerName: partnerName,
          description: description,
        );
      } else {
        await repo.addPartnerPayment(
          date: DateTime.now(),
          amount: amount,
          partnerName: partnerName,
          description: description,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        showErrorSnackBar(
          context,
          'Ortak ödemesi kaydedilemedi. Lütfen tekrar deneyin.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppFormSheet(
      title: _isEdit ? 'Ortak Ödemesini Düzenle' : 'Ortak Ödemesi Ekle',
      submitLabel: _isEdit ? 'Güncelle' : 'Kaydet',
      accent: _accent,
      onSubmit: _save,
      children: [
        Text(
          'Ortak',
          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        _buildPartnerSelector(),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _amountController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.next,
          decoration: appInputDecoration(label: 'Tutar', accent: _accent),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _descriptionController,
          minLines: 3,
          maxLines: 4,
          decoration: appInputDecoration(
            label: 'Not düşmek istersen',
            accent: _accent,
            alignLabelWithHint: true,
          ),
        ),
      ],
    );
  }

  Widget _buildPartnerSelector() {
    if (_addingNew) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _newNameController,
            autofocus: _names.isNotEmpty,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: appInputDecoration(label: 'Ortak adı', accent: _accent),
          ),
          if (_names.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _addingNew = false;
                  _newNameController.clear();
                  if (_names.length == 1) _selectedName = _names.first;
                }),
                icon: const Icon(Icons.list_rounded, size: 18),
                style: TextButton.styleFrom(
                  foregroundColor: _accent,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                label: const Text(
                  'Listeden seç',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      );
    }

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final name in _names)
          ChoiceChip(
            label: Text(name),
            selected: _selectedName == name,
            onSelected: (_) => setState(() => _selectedName = name),
            showCheckmark: false,
            selectedColor: _accent,
            backgroundColor: AppColors.surface,
            labelStyle: AppTextStyles.chip.copyWith(
              fontWeight: FontWeight.w700,
              color: _selectedName == name
                  ? AppColors.textOnBrand
                  : AppColors.textSecondary,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: BorderSide(
                color: _selectedName == name ? _accent : AppColors.border,
              ),
            ),
          ),
        ActionChip(
          avatar: const Icon(Icons.add_rounded, size: 18, color: _accent),
          label: const Text('Yeni'),
          backgroundColor: AppColors.infoLight,
          labelStyle: AppTextStyles.chip.copyWith(
            fontWeight: FontWeight.w800,
            color: _accent,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            side: const BorderSide(color: _accent),
          ),
          onPressed: () => setState(() {
            _addingNew = true;
            _selectedName = null;
            _newNameController.clear();
          }),
        ),
      ],
    );
  }
}
