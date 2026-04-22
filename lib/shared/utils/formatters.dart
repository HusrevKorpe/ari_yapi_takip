import 'package:intl/intl.dart';

final _currencyFormat = NumberFormat.currency(
  locale: 'tr_TR',
  symbol: '₺',
  decimalDigits: 2,
);

String formatMoney(num value) => _currencyFormat.format(value);

String formatDate(DateTime value) => DateFormat('dd.MM.yyyy').format(value);

String formatMonth(DateTime value) =>
    DateFormat('MMMM yyyy', 'tr_TR').format(value);

String formatDayMonth(DateTime value) =>
    DateFormat('d MMMM yyyy', 'tr_TR').format(value);
