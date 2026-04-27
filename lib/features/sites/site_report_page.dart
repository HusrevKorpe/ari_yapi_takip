import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/local/repositories.dart';
import 'widgets/site_report/report_body.dart';

class SiteReportPage extends ConsumerStatefulWidget {
  const SiteReportPage({
    super.key,
    required this.siteId,
    required this.siteName,
  });

  final String siteId;
  final String siteName;

  static const _bg = Color(0xFFF7F9F8);

  @override
  ConsumerState<SiteReportPage> createState() => _SiteReportPageState();
}

class _SiteReportPageState extends ConsumerState<SiteReportPage> {
  bool _saving = false;

  Future<void> _saveToFirestore(SiteReportData report) async {
    if (_saving) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ctx = ref.read(syncContextProvider);
      if (ctx.organizationId.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Organizasyon bulunamadi.')),
        );
        return;
      }
      await ref.read(siteReportFirestoreRepositoryProvider).saveReport(
            organizationId: ctx.organizationId,
            userId: ctx.userId,
            report: report,
          );
      messenger.showSnackBar(
        const SnackBar(content: Text('Rapor Firestore\'a kaydedildi.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reportAsync = ref.watch(siteReportProvider(widget.siteId));
    final report = reportAsync.asData?.value;

    return Scaffold(
      backgroundColor: SiteReportPage._bg,
      appBar: AppBar(
        backgroundColor: SiteReportPage._bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_rounded),
            tooltip: 'Firestore\'a kaydet',
            onPressed: (report == null || _saving)
                ? null
                : () => _saveToFirestore(report),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Yenile',
            onPressed: () =>
                ref.invalidate(siteReportProvider(widget.siteId)),
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.siteName,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF161616),
              ),
            ),
            const Text(
              'Santiye Raporu',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7B75),
              ),
            ),
          ],
        ),
      ),
      body: reportAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Hata: $e')),
        data: (report) => ReportBody(report: report),
      ),
    );
  }
}
