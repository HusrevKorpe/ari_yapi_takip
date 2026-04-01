enum AttendanceStatus { worked, halfDay, absent, leave }

extension AttendanceStatusX on AttendanceStatus {
  String get code {
    switch (this) {
      case AttendanceStatus.worked:
        return 'worked';
      case AttendanceStatus.halfDay:
        return 'half_day';
      case AttendanceStatus.absent:
        return 'absent';
      case AttendanceStatus.leave:
        return 'leave';
    }
  }

  String get label {
    switch (this) {
      case AttendanceStatus.worked:
        return 'Calisti';
      case AttendanceStatus.halfDay:
        return 'Yarim Gun';
      case AttendanceStatus.absent:
        return 'Gelmedi';
      case AttendanceStatus.leave:
        return 'Izinli';
    }
  }

  bool get requiresSite =>
      this == AttendanceStatus.worked || this == AttendanceStatus.halfDay;

  static AttendanceStatus fromCode(String code) {
    return AttendanceStatus.values.firstWhere(
      (e) => e.code == code,
      orElse: () => AttendanceStatus.absent,
    );
  }
}
