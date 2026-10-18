// Reporte a medida — cifras es-AR (port de a-medida/formato.ts).
// Miles «.», decimales «,», moneda «$ 1.234», menos tipográfico «−». Porcentajes llegan como FRACCIÓN.

const raya = '—';
const _menos = '−';
const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

enum Signo { pos, neg, cero }

num? aNum(dynamic v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is String) return num.tryParse(v);

  return null;
}

String _agrupar(String digitos) =>
    digitos.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

String _numeroAbs(num abs, int max) {
  final s = abs.toStringAsFixed(max);
  final partes = s.split('.');
  final dec = partes.length > 1 ? partes[1].replaceAll(RegExp(r'0+$'), '') : '';

  return _agrupar(partes[0]) + (dec.isNotEmpty ? ',$dec' : '');
}

String _conSigno(num v, String cuerpo) => v < 0 && cuerpo != '0' ? '$_menos$cuerpo' : cuerpo;

String fEntero(dynamic v) {
  final n = aNum(v);
  if (n == null) return raya;

  return _conSigno(n, _numeroAbs(n.abs(), 0));
}

String fDecimal(dynamic v) {
  final n = aNum(v);
  if (n == null) return raya;

  return _conSigno(n, _numeroAbs(n.abs(), 2));
}

String fMoneda(dynamic v) {
  final n = aNum(v);
  if (n == null) return raya;
  final cuerpo = _numeroAbs(n.abs(), 0);

  return '${n < 0 && cuerpo != '0' ? _menos : ''}\$ $cuerpo';
}

String fPorcentaje(dynamic fraccion) {
  final n = aNum(fraccion);
  if (n == null) return raya;

  return '${_conSigno(n, _numeroAbs(n.abs() * 100, 1))} %';
}

({String texto, Signo? signo}) fVariacion(dynamic fraccion) {
  final n = aNum(fraccion);
  if (n == null) return (texto: raya, signo: null);
  final cuerpo = _numeroAbs(n.abs() * 100, 1);
  if (cuerpo == '0') return (texto: '= 0 %', signo: Signo.cero);

  return n > 0
      ? (texto: '▲ +$cuerpo %', signo: Signo.pos)
      : (texto: '▼ $_menos$cuerpo %', signo: Signo.neg);
}

String fValor(dynamic v, String formato) {
  if (v == null || v == '') return raya;
  if (formato == 'texto') return '$v';

  switch (formato) {
    case 'moneda':
      return fMoneda(v);
    case 'entero':
      return fEntero(v);
    case 'decimal':
      return fDecimal(v);
    case 'porcentaje':
      return fPorcentaje(v);
    default:
      return '$v';
  }
}

// Eje corto: «$ 1,2 M», «$ 380 mil», «$ 950».
String fEjeCorto(num? v, [String formato = 'moneda']) {
  if (v == null || !v.isFinite) return raya;
  final prefijo = formato == 'moneda' ? '\$ ' : '';
  final abs = v.abs();
  final signo = v < 0 ? _menos : '';
  final String cuerpo;
  if (abs >= 1000000) {
    cuerpo = '${_numeroAbs(abs / 1000000, 1)} M';
  } else if (abs >= 1000) {
    cuerpo = '${_numeroAbs(abs / 1000, 0)} mil';
  } else {
    cuerpo = _numeroAbs(abs, 0);
  }

  return '$signo$prefijo$cuerpo';
}

({int y, int m, int d}) _partes(String s) {
  final p = s.split('-').map(int.parse).toList();

  return (y: p[0], m: p[1], d: p[2]);
}

// «19 sep–18 oct 2026» · «1–17 oct 2026» · «20 dic 2025–5 ene 2026».
String fRangoFechas(String desde, String hasta) {
  final a = _partes(desde);
  final b = _partes(hasta);
  if (a == b) return '${b.d} ${_meses[b.m - 1]} ${b.y}';
  if (a.y == b.y && a.m == b.m) return '${a.d}–${b.d} ${_meses[b.m - 1]} ${b.y}';
  if (a.y == b.y) return '${a.d} ${_meses[a.m - 1]}–${b.d} ${_meses[b.m - 1]} ${b.y}';

  return '${a.d} ${_meses[a.m - 1]} ${a.y}–${b.d} ${_meses[b.m - 1]} ${b.y}';
}

// 'YYYY-MM-DD' → «18/10»: rótulo corto de eje (el largo se cortaba en «2026...»).
String fFechaEje(String s) {
  final r = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (r == null) return s;

  return '${int.parse(r[3]!)}/${int.parse(r[2]!)}';
}

String fFechaCorta(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;

  return '${p[2]}/${p[1]}/${p[0]}';
}

// Rótulo de tiempo según el grano: el servidor manda la fecha ISO del inicio del bucket.
// tabla: «19/09/2026» · «sem. 13/10/2025» · «oct 2025»; eje: «19/9» · «13/10» · «oct 25».
String fTiempo(String dim, dynamic v, {bool eje = false}) {
  final s = '${v ?? ''}';
  final r = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (r == null) return s;
  final y = r[1]!, m = int.parse(r[2]!), d = int.parse(r[3]!);
  switch (dim) {
    case 'mes':
      return eje ? '${_meses[m - 1]} ${y.substring(2)}' : '${_meses[m - 1]} $y';
    case 'semana':
      return eje ? '$d/$m' : 'sem. ${r[3]}/${r[2]}/${y.substring(2)}';
    case 'dia':
      return eje ? '$d/$m' : '${r[3]}/${r[2]}/$y';
    default:
      return s;
  }
}
