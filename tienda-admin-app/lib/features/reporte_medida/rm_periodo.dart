// Reporte a medida — período y comparación en el teléfono (port de a-medida/periodo-local.ts,
// que a su vez porta api-ventago period.ts). Funciones puras sobre 'YYYY-MM-DD' en UTC.
// ORIENTATIVO: el rango real viene en la respuesta de ejecutar y prevalece.

DateTime _parse(String s) {
  final r = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (r == null) throw FormatException('Fecha inválida: $s');
  final y = int.parse(r[1]!), m = int.parse(r[2]!), d = int.parse(r[3]!);
  if (m < 1 || m > 12 || d < 1 || d > _diasDelMes(y, m)) {
    throw FormatException('Fecha inválida: $s');
  }

  return DateTime.utc(y, m, d);
}

int _diasDelMes(int y, int m) => DateTime.utc(y, m + 1, 0).day;

String fmtYmd(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

String _sumarDias(String s, int n) => fmtYmd(_parse(s).add(Duration(days: n)));

String _sumarMeses(String s, int n) {
  final t = _parse(s);
  final total = t.year * 12 + (t.month - 1) + n;
  final ny = total ~/ 12;
  final nm = total % 12 + 1;
  final d = t.day < _diasDelMes(ny, nm) ? t.day : _diasDelMes(ny, nm);

  return fmtYmd(DateTime.utc(ny, nm, d));
}

bool _esUltimoDia(String s) {
  final t = _parse(s);

  return t.day == _diasDelMes(t.year, t.month);
}

String _finDeMes(String s) {
  final t = _parse(s);

  return fmtYmd(DateTime.utc(t.year, t.month, _diasDelMes(t.year, t.month)));
}

String _inicioDeMes(String s) {
  final t = _parse(s);

  return fmtYmd(DateTime.utc(t.year, t.month, 1));
}

// Lunes ISO de la semana del día.
String _lunesDe(String s) => _sumarDias(s, -(_parse(s).weekday - 1));

int diasEnRango(String desde, String hasta) =>
    _parse(hasta).difference(_parse(desde)).inDays + 1;

bool incluyeHoy(String desde, String hasta, String hoy) =>
    desde.compareTo(hoy) <= 0 && hoy.compareTo(hasta) <= 0;

// Desfase fijo de las zonas de Argentina (sin horario de verano desde 2009).
// Dart no trae base de zonas; cualquier otra zona usa el reloj del teléfono.
String hoyDeCatalogo(String? zonaHoraria, [DateTime? ahora]) {
  final t = ahora ?? DateTime.now();
  final zona = zonaHoraria ?? 'America/Argentina/Buenos_Aires';
  if (zona.startsWith('America/Argentina/')) {
    return fmtYmd(t.toUtc().subtract(const Duration(hours: 3)));
  }

  return fmtYmd(DateTime.utc(t.year, t.month, t.day));
}

({String desde, String hasta}) resolverPeriodo(Map<String, String> p, String hoy) {
  _parse(hoy);
  if (p.containsKey('from')) {
    final desde = fmtYmd(_parse(p['from']!));
    final hasta = fmtYmd(_parse(p['to'] ?? ''));
    if (desde.compareTo(hasta) > 0) {
      throw const FormatException('La fecha inicial es posterior a la final.');
    }

    return (desde: desde, hasta: hasta);
  }

  switch (p['preset']) {
    case 'hoy':
      return (desde: hoy, hasta: hoy);
    case 'ayer':
      final a = _sumarDias(hoy, -1);

      return (desde: a, hasta: a);
    case 'esta_semana':
      return (desde: _lunesDe(hoy), hasta: hoy);
    case 'semana_pasada':
      final l = _lunesDe(hoy);

      return (desde: _sumarDias(l, -7), hasta: _sumarDias(l, -1));
    case 'este_mes':
      return (desde: _inicioDeMes(hoy), hasta: hoy);
    case 'mes_pasado':
      final ini = _sumarMeses(_inicioDeMes(hoy), -1);

      return (desde: ini, hasta: _finDeMes(ini));
    case 'ultimos_7_dias':
      return (desde: _sumarDias(hoy, -6), hasta: hoy);
    case 'ultimos_30_dias':
      return (desde: _sumarDias(hoy, -29), hasta: hoy);
    case 'ultimos_90_dias':
      return (desde: _sumarDias(hoy, -89), hasta: hoy);
    case 'ultimos_12_meses':
      return (desde: _sumarDias(_sumarMeses(hoy, -12), 1), hasta: hoy);
    default:
      throw const FormatException('Período desconocido.');
  }
}

// D-31/D-31a: calendario (este_mes/mes_pasado, o grano mes) → mismas fechas; el resto → semanal.
String alineacion(Map<String, String> p, List<String> groupBy) {
  final pre = p['preset'];
  if (pre == 'este_mes' || pre == 'mes_pasado') return 'calendario';

  return groupBy.contains('mes') ? 'calendario' : 'semanal';
}

({String desde, String hasta}) comparacionLocal(
    String desde, String hasta, String tipo, String alin) {
  if (alin == 'semanal') {
    final k = tipo == 'anio_anterior' ? 364 : (diasEnRango(desde, hasta) / 7).ceil() * 7;

    return (desde: _sumarDias(desde, -k), hasta: _sumarDias(hasta, -k));
  }

  var m = 12;
  if (tipo == 'periodo_anterior') {
    m = 1;
    while (_sumarMeses(hasta, -m).compareTo(desde) >= 0) {
      m++;
    }
  }
  final nuevoHasta =
      _esUltimoDia(hasta) ? _finDeMes(_sumarMeses(hasta, -m)) : _sumarMeses(hasta, -m);

  return (desde: _sumarMeses(desde, -m), hasta: nuevoHasta);
}
