enum PayFrequency { weekly, biweekly, monthly }

extension PayFrequencyX on PayFrequency {
  String get code {
    switch (this) {
      case PayFrequency.weekly:
        return 'weekly';
      case PayFrequency.biweekly:
        return 'biweekly';
      case PayFrequency.monthly:
        return 'monthly';
    }
  }

  String get label {
    switch (this) {
      case PayFrequency.weekly:
        return 'Haftalik';
      case PayFrequency.biweekly:
        return '2 Hafta';
      case PayFrequency.monthly:
        return 'Aylik';
    }
  }

  int get days {
    switch (this) {
      case PayFrequency.weekly:
        return 7;
      case PayFrequency.biweekly:
        return 14;
      case PayFrequency.monthly:
        return 30;
    }
  }

  static PayFrequency fromCode(String code) {
    return PayFrequency.values.firstWhere(
      (e) => e.code == code,
      orElse: () => PayFrequency.weekly,
    );
  }
}
