// es-AR 통화/숫자 포맷 헬퍼 — `$` + 천단위 `.` (18.900). tabular figures 는 위젯에서 적용.
import 'package:intl/intl.dart';

// 정수 우선(가격은 ARS 정수 관례). 소수부 있으면 2자리까지.
final NumberFormat _intFmt = NumberFormat('#,##0', 'es_AR');
final NumberFormat _decFmt = NumberFormat('#,##0.00', 'es_AR');

// 금액 → "$18.900" (es-AR). 소수부가 있으면 소수 2자리.
String formatMoney(num value) {
  final isInt = value == value.roundToDouble();

  return '\$${(isInt ? _intFmt : _decFmt).format(value)}';
}
