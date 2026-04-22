import '../shared/constants/attendance_status.dart';

class PayrollCalculation {
  const PayrollCalculation({
    required this.workedDayEquivalent,
    required this.locationBonus,
    required this.gross,
    required this.deductions,
    required this.net,
  });

  final double workedDayEquivalent;
  final double locationBonus;
  final double gross;
  final double deductions;
  final double net;
}

class PayrollCalculator {
  static double workedEquivalent(Iterable<AttendanceStatus> statuses) {
    return statuses.fold<double>(0, (acc, status) {
      return acc +
          switch (status) {
            AttendanceStatus.worked => 1.0,
            AttendanceStatus.halfDay => 0.5,
            AttendanceStatus.absent => 0.0,
            AttendanceStatus.leave => 0.0,
          };
    });
  }

  static PayrollCalculation calculate({
    required double workedDayEquivalent,
    required double dailyWage,
    required double deductions,
    double locationBonus = 0,
  }) {
    final gross = (workedDayEquivalent * dailyWage) + locationBonus;
    final net = gross - deductions;
    return PayrollCalculation(
      workedDayEquivalent: workedDayEquivalent,
      locationBonus: locationBonus,
      gross: gross,
      deductions: deductions,
      net: net,
    );
  }
}
