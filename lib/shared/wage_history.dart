import 'dart:convert';

/// Bir çalışanın yevmiye (günlük ücret) değişiklik geçmişi.
///
/// Her segment, [WageSegment.from] tarihinden (dahil) itibaren geçerli olan
/// yevmiyeyi tutar ve bir sonraki segmentin tarihine kadar geçerlidir. İlk
/// (en eski) segmentin yevmiyesi, o tarihten önceki tüm günler için de
/// geçerlidir.
///
/// Boş/null geçmiş = hiç zam kaydı yok → tüm günler güncel `dailyWage` ile
/// fiyatlanır. Bu, tarih bazlı yevmiye eklenmeden önceki davranışın birebir
/// aynısıdır; mevcut çalışanların geçmiş hesapları HİÇ değişmez. Geçmiş
/// yalnızca bir çalışana yeni bir yevmiye girildiğinde ([withChange])
/// oluşmaya başlar ve o andan sonraki zamlar ileriye dönük uygulanır.
class WageHistory {
  const WageHistory(this.segments);

  /// Tarihe göre ARTAN sıralı segmentler.
  final List<WageSegment> segments;

  bool get isEmpty => segments.isEmpty;

  /// Geçmişi paylaşılan/senkronize JSON formatından çözer. Null, boş veya
  /// bozuk JSON güvenli biçimde boş geçmişe düşer (eski davranış).
  static WageHistory decode(String? json) {
    if (json == null || json.isEmpty) return const WageHistory([]);
    try {
      final list = jsonDecode(json) as List<dynamic>;
      final segs = <WageSegment>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        segs.add(
          WageSegment(
            from: DateTime.parse(m['from'] as String),
            wage: (m['wage'] as num).toDouble(),
          ),
        );
      }
      segs.sort((a, b) => a.from.compareTo(b.from));
      return WageHistory(segs);
    } catch (_) {
      return const WageHistory([]);
    }
  }

  /// Senkronize/saklama için JSON. Boş geçmiş `null` döner ki sütun boş kalsın
  /// ve hiç zam almamış çalışanlar için gereksiz veri yazılmasın.
  String? encode() {
    if (segments.isEmpty) return null;
    return jsonEncode([
      for (final s in segments)
        {'from': s.from.toIso8601String(), 'wage': s.wage},
    ]);
  }

  /// [date] gününde geçerli olan yevmiye.
  ///
  /// Geçmiş boşsa [fallback] (çalışanın güncel yevmiyesi) döner — yani hiç zam
  /// kaydı yoksa tüm günler güncel yevmiyeyle fiyatlanır. [date] en eski
  /// segmentten önceyse en eski segmentin yevmiyesi geçerlidir.
  double wageForDate(DateTime date, double fallback) {
    if (segments.isEmpty) return fallback;
    var result = segments.first.wage;
    for (final s in segments) {
      if (!s.from.isAfter(date)) {
        result = s.wage; // s.from <= date
      } else {
        break;
      }
    }
    return result;
  }

  /// Yeni bir yevmiye girildiğinde çağrılır. [effectiveFrom] gününden (dahil)
  /// itibaren [newWage] geçerli olur; ondan önceki günler eski yevmiyede kalır.
  ///
  /// Geçmiş boşken (ilk değişiklik) [previousWage] ile bir taban segment
  /// tohumlanır: böylece değişiklikten ÖNCEKİ günler eski yevmiyeyle
  /// hesaplanmaya devam eder. Aynı güne ikinci kez yevmiye girilirse üzerine
  /// yazılır.
  WageHistory withChange({
    required DateTime effectiveFrom,
    required double newWage,
    required double previousWage,
  }) {
    final eff = DateTime(
      effectiveFrom.year,
      effectiveFrom.month,
      effectiveFrom.day,
    );
    final segs = [...segments];
    if (segs.isEmpty) {
      // İlk değişiklik: eski yevmiye "başlangıçtan beri" geçerli sayılsın ki
      // eff tarihinden önceki günler yeniden fiyatlanmasın.
      segs.add(WageSegment(from: DateTime(2000), wage: previousWage));
    }
    // Aynı güne yeniden yevmiye girildiyse eskisini at, yenisini koy.
    segs.removeWhere((s) => s.from.isAtSameMomentAs(eff));
    segs.add(WageSegment(from: eff, wage: newWage));
    segs.sort((a, b) => a.from.compareTo(b.from));
    return WageHistory(segs);
  }
}

class WageSegment {
  const WageSegment({required this.from, required this.wage});

  final DateTime from;
  final double wage;
}
