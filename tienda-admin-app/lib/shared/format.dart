import 'package:intl/intl.dart';

// PG COUNT/SUM/DECIMAL 은 JSON 에서 문자열("12", "34500.00")로 내려올 수 있음.
// 'String is not a subtype of num' 크래시 방지용 관용 파서.
int asInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

num asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

// es_AR 통화 포맷 (기호 $, 소수점 없음 — 프린터 규칙과 동일하게 정수 표시).
final _money = NumberFormat.currency(locale: 'es_AR', symbol: r'$', decimalDigits: 0);

String money(num v) => _money.format(v);

// 퍼센트 변화 표시 (+12% / -4%).
String pct(num v) {
  final s = v >= 0 ? '+' : '';

  return '$s${v.toStringAsFixed(0)}%';
}

// 오늘 날짜 (YYYY-MM-DD, 기기 로컬 = AR).
String todayStr() {
  final n = DateTime.now();

  return '${n.year.toString().padLeft(4, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}
