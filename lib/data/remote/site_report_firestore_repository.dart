import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../local/repositories.dart';

class SiteReportFirestoreRepository {
  SiteReportFirestoreRepository();

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  bool get _isAvailable => Firebase.apps.isNotEmpty;

  Future<String> saveReport({
    required String organizationId,
    required String userId,
    required SiteReportData report,
  }) async {
    if (!_isAvailable) {
      throw FirebaseException(
        plugin: 'firebase_core',
        code: 'not-initialized',
        message: 'Firebase initialize edilmedi.',
      );
    }
    if (organizationId.isEmpty) {
      throw StateError('Organizasyon bulunamadi.');
    }

    final now = DateTime.now();
    final reportId =
        '${report.site.id}_${now.millisecondsSinceEpoch}';

    final payload = <String, dynamic>{
      'id': reportId,
      'santiyeId': report.site.id,
      'santiyeAdi': report.site.name,
      'olusturulmaTarihi': now.toIso8601String(),
      'olusturanKullaniciId': userId,
      'ilkCalismaTarihi': report.firstWorkDate?.toIso8601String(),
      'sonCalismaTarihi': report.lastWorkDate?.toIso8601String(),
      'isciSayisi': report.workerRows.length,
      'toplamYevmiye': report.totalWages,
      'toplamGider': report.totalExpenses,
      'genelToplam': report.grandTotal,
      'isciler': report.workerRows
          .map((r) => {
                'isciId': r.workerId,
                'isciAdi': r.workerName,
                'tamGun': r.fullDays,
                'yarimGun': r.halfDays,
                'gunEsdegeri': r.dayEquivalent,
                'gunlukUcret': r.dailyWage,
                'santiyePrim': r.siteBonus,
                'toplamUcret': r.totalWage,
              })
          .toList(),
      'giderKategorileri': report.expenseCategories
          .map((c) => {
                'kategori': c.category,
                'tutar': c.total,
              })
          .toList(),
    };

    await _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('santiye_raporlari')
        .doc(reportId)
        .set(payload);

    return reportId;
  }
}
