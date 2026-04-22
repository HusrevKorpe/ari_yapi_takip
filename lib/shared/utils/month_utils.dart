DateTime monthStart(DateTime value) => DateTime(value.year, value.month, 1);

DateTime monthEnd(DateTime value) =>
    DateTime(value.year, value.month + 1, 0, 23, 59, 59);

String monthKey(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  return '${value.year}-$month';
}

DateTime normalizeDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);
