import 'dart:convert';

/// Bir şantiyenin günlük prim (şantiye primi) değişiklik geçmişi.
///
/// Her segment, [BonusSegment.from] tarihinden (dahil) itibaren geçerli olan
/// primi tutar ve bir sonraki segmentin tarihine kadar geçerlidir. İlk (en
/// eski) segmentin primi, o tarihten önceki tüm günler için de geçerlidir.
///
/// Boş/null geçmiş = hiç prim değişikliği kaydı yok → tüm günler şantiyenin
/// güncel `dailyBonus`'u ile fiyatlanır. Bu, tarih bazlı prim eklenmeden önceki
/// davranışın birebir aynısıdır; mevcut şantiyelerin geçmiş hesapları HİÇ
/// değişmez. Geçmiş yalnızca bir şantiyeye yeni bir prim girildiğinde
/// ([withChange]) oluşmaya başlar ve o andan sonraki değişiklikler ileriye
/// dönük uygulanır — yevmiyedeki [WageHistory] ile aynı mantık.
class BonusHistory {
  const BonusHistory(this.segments);

  /// Tarihe göre ARTAN sıralı segmentler.
  final List<BonusSegment> segments;

  bool get isEmpty => segments.isEmpty;

  /// Geçmişi paylaşılan/senkronize JSON formatından çözer. Null, boş veya
  /// bozuk JSON güvenli biçimde boş geçmişe düşer (eski davranış).
  static BonusHistory decode(String? json) {
    if (json == null || json.isEmpty) return const BonusHistory([]);
    try {
      final list = jsonDecode(json) as List<dynamic>;
      final segs = <BonusSegment>[];
      for (final e in list) {
        final m = e as Map<String, dynamic>;
        segs.add(
          BonusSegment(
            from: DateTime.parse(m['from'] as String),
            bonus: (m['bonus'] as num).toDouble(),
          ),
        );
      }
      segs.sort((a, b) => a.from.compareTo(b.from));
      return BonusHistory(segs);
    } catch (_) {
      return const BonusHistory([]);
    }
  }

  /// Senkronize/saklama için JSON. Boş geçmiş `null` döner ki sütun boş kalsın
  /// ve hiç değişmemiş şantiyeler için gereksiz veri yazılmasın.
  String? encode() {
    if (segments.isEmpty) return null;
    return jsonEncode([
      for (final s in segments)
        {'from': s.from.toIso8601String(), 'bonus': s.bonus},
    ]);
  }

  /// [date] gününde geçerli olan prim.
  ///
  /// Geçmiş boşsa [fallback] (şantiyenin güncel primi) döner — yani hiç
  /// değişiklik kaydı yoksa tüm günler güncel primle fiyatlanır. [date] en eski
  /// segmentten önceyse en eski segmentin primi geçerlidir.
  double bonusForDate(DateTime date, double fallback) {
    if (segments.isEmpty) return fallback;
    var result = segments.first.bonus;
    for (final s in segments) {
      if (!s.from.isAfter(date)) {
        result = s.bonus; // s.from <= date
      } else {
        break;
      }
    }
    return result;
  }

  /// Yeni bir prim girildiğinde çağrılır. [effectiveFrom] gününden (dahil)
  /// itibaren [newBonus] geçerli olur; ondan önceki günler eski primde kalır.
  ///
  /// Geçmiş boşken (ilk değişiklik) [previousBonus] ile bir taban segment
  /// tohumlanır: böylece değişiklikten ÖNCEKİ günler eski primle hesaplanmaya
  /// devam eder. Aynı güne ikinci kez prim girilirse üzerine yazılır.
  BonusHistory withChange({
    required DateTime effectiveFrom,
    required double newBonus,
    required double previousBonus,
  }) {
    final eff = DateTime(
      effectiveFrom.year,
      effectiveFrom.month,
      effectiveFrom.day,
    );
    final segs = [...segments];
    if (segs.isEmpty) {
      // İlk değişiklik: eski prim "başlangıçtan beri" geçerli sayılsın ki eff
      // tarihinden önceki günler yeniden fiyatlanmasın.
      segs.add(BonusSegment(from: DateTime(2000), bonus: previousBonus));
    }
    // Aynı güne yeniden prim girildiyse eskisini at, yenisini koy.
    segs.removeWhere((s) => s.from.isAtSameMomentAs(eff));
    segs.add(BonusSegment(from: eff, bonus: newBonus));
    segs.sort((a, b) => a.from.compareTo(b.from));
    return BonusHistory(segs);
  }
}

class BonusSegment {
  const BonusSegment({required this.from, required this.bonus});

  final DateTime from;
  final double bonus;
}
