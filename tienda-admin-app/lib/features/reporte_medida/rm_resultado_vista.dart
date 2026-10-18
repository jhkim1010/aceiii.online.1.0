// Reporte a medida — transformaciones puras del resultado (port de resultado/resultado-vista.ts).
// Las etiquetas de métricas salen de columnas[].labelEs (D-32).
import 'rm_formato.dart';
import 'rm_modelos.dart';

const tamPagina = 50;
const maxSeries = 5;
const maxBarras = 10;
const repetido = '〃';
const _metricasAuto = ['unidades', 'tickets', 'aur'];

class ColumnaVista {
  final String id;
  final String header;
  final bool esDimension;
  final String formato;
  final bool auto;
  final bool esVariacion;
  const ColumnaVista(this.id, this.header,
      {this.esDimension = false, this.formato = 'texto', this.auto = false, this.esVariacion = false});
}

bool _oculta(String id) => id.endsWith('_comp') || id.endsWith('_var_pct');

String formatoDe(ColumnaDef c) => c.formato ?? (c.tipo == 'dimension' ? 'texto' : 'entero');

List<ColumnaVista> columnasVista(ResultadoReporte r, Pedido p) {
  final dims = r.columnas.where((c) => c.tipo == 'dimension').toList();
  final out = <ColumnaVista>[
    if (dims.isEmpty) const ColumnaVista('etiqueta', 'Total del local', esDimension: true),
    for (final d in dims) ColumnaVista(d.id, d.labelEs, esDimension: true),
  ];
  for (final c in r.columnas) {
    if (c.tipo != 'metrica' || _oculta(c.id)) continue;
    final auto = p.compare != null && _metricasAuto.contains(c.id) && !p.metrics.contains(c.id);
    out.add(ColumnaVista(c.id, auto ? '${c.labelEs} ·' : c.labelEs,
        formato: formatoDe(c), auto: auto));
  }
  for (final (id, header) in [('venta_neta_var_pct', 'Var. venta'), ('unidades_var_pct', 'Var. unid.')]) {
    if (r.columnas.any((c) => c.id == id)) {
      out.add(ColumnaVista(id, header, formato: 'porcentaje', esVariacion: true));
    }
  }

  return out;
}

// Con 2 dimensiones, la 1ª repite «〃» en filas consecutivas iguales (sin subtotales).
List<Fila> filasVista(List<Fila> filas, List<String> dims) {
  // Sin clasificación la única fila es el total: se muestra sólo la fila «Total».
  if (dims.isEmpty) return const [];
  final tiempos = dims.where(tiemposIds.contains).toList();
  if (tiempos.isNotEmpty) {
    filas = [
      for (final f in filas) {...f, for (final t in tiempos) t: fTiempo(t, f[t])},
    ];
  }
  final primera = dims.first;

  return [
    for (var i = 0; i < filas.length; i++)
      if (dims.length >= 2 &&
          i > 0 &&
          filas[i - 1]['${primera}_key'] == filas[i]['${primera}_key'] &&
          filas[i - 1][primera] == filas[i][primera])
        {...filas[i], primera: repetido}
      else
        filas[i],
  ];
}

Fila filaTotal(ResultadoReporte r, List<ColumnaVista> cols) {
  final fila = <String, dynamic>{'__total': true};
  final primera = cols.where((c) => c.esDimension).firstOrNull;
  if (primera != null) fila[primera.id] = 'Total';
  for (final c in cols) {
    if (c.esDimension) continue;
    if (c.esVariacion) {
      final vt = r.comparacion?.variacionTotal[c.id.replaceAll('_var_pct', '')];
      fila[c.id] = vt?.varPct;
      continue;
    }
    fila[c.id] = r.totales[c.id];
  }

  return fila;
}

({String texto, Signo? signo}) celdaVariacion(Fila f, String colId) {
  if (f['parcial'] == true) return (texto: 'parcial · sin comparar', signo: null);
  final v = f[colId];
  if (v == null) return (texto: raya, signo: null);

  return fVariacion(v);
}

class Titular {
  final List<({String label, String texto, Signo? signo})> partes;
  final String? sufijoHasta;
  final String? notaParcial;
  const Titular(this.partes, this.sufijoHasta, this.notaParcial);
}

Titular? titularComparacion(ResultadoReporte r) {
  final vt = r.comparacion?.variacionTotal;
  if (vt == null) return null;
  final partes = <({String label, String texto, Signo? signo})>[];
  var parcial = false;
  String? hasta;
  for (final m in ['venta_neta', 'unidades']) {
    final v = vt[m];
    if (v == null || v.varPct == null) continue;
    final f = fVariacion(v.varPct);
    final label = r.columnas.where((c) => c.id == m).firstOrNull?.labelEs ?? m;
    partes.add((label: label, texto: f.texto, signo: f.signo));
    if (v.parcial) {
      parcial = true;
      hasta ??= v.hastaComparable;
    }
  }
  if (partes.isEmpty) return null;

  return Titular(
    partes,
    parcial && hasta != null ? 'hasta ${fFechaCorta(hasta)}' : null,
    parcial ? 'período en curso: se compara sólo hasta ayer' : null,
  );
}

class SerieGrafico {
  final String nombre;
  final List<double?> data;
  final bool comparacion;
  const SerieGrafico(this.nombre, this.data, {this.comparacion = false});
}

class GraficoVista {
  final bool barras;
  final List<String> categorias;
  final List<SerieGrafico> series;
  final List<int> parcialesIdx;
  final bool recortado;
  final String formato;
  const GraficoVista(this.barras, this.categorias, this.series, this.parcialesIdx, this.recortado,
      this.formato);
}

double? _d(dynamic v) => aNum(v)?.toDouble();

// Métricas elegidas que el servidor devolvió (margen omitido por permiso no aparece).
List<ColumnaDef> metricasDelGrafico(ResultadoReporte r, Pedido p) =>
    r.columnas.where((c) => c.tipo == 'metrica' && p.metrics.contains(c.id)).toList();

// Rótulos repetidos reciben « (2)», « (3)»; un sufijo nunca pisa un nombre real.
List<String> desambiguar(List<String> rotulos) {
  final ocupados = rotulos.toSet();
  final vistos = <String>{};

  return rotulos.map((r) {
    if (vistos.add(r)) return r;
    var n = 2;
    while (ocupados.contains('$r ($n)')) {
      n++;
    }
    final nombre = '$r ($n)';
    ocupados.add(nombre);

    return nombre;
  }).toList();
}

GraficoVista? seriesGrafico(ResultadoReporte r, Pedido p, String metrica) {
  final col = r.columnas.where((c) => c.id == metrica && c.tipo == 'metrica').firstOrNull;
  if (col == null || p.groupBy.isEmpty || r.filas.isEmpty) return null;
  final formato = formatoDe(col);
  final dimTiempo = p.groupBy.where(tiemposIds.contains).firstOrNull;
  final otras = p.groupBy.where((d) => d != dimTiempo).toList();
  final filas = r.filas;
  final comp = r.comparacion != null && r.columnas.any((c) => c.id == '${metrica}_comp');

  if (dimTiempo == null) {
    final primeras = filas.take(maxBarras).toList();

    return GraficoVista(
      true,
      primeras.map((f) => p.groupBy.map((d) => '${f[d] ?? ''}').join(' · ')).toList(),
      [SerieGrafico(col.labelEs, primeras.map((f) => _d(f[metrica])).toList())],
      const [],
      filas.length > maxBarras,
      formato,
    );
  }

  final parciales = [
    for (var i = 0; i < filas.length; i++)
      if (filas[i]['parcial'] == true) i,
  ];

  if (otras.isEmpty) {
    return GraficoVista(
      false,
      filas.map((f) => fTiempo(dimTiempo, f[dimTiempo], eje: true)).toList(),
      [
        SerieGrafico(col.labelEs, filas.map((f) => _d(f[metrica])).toList()),
        if (comp)
          SerieGrafico('${col.labelEs} (comparación)',
              filas.map((f) => _d(f['${metrica}_comp'])).toList(),
              comparacion: true),
      ],
      parciales,
      false,
      formato,
    );
  }

  // Identidad por valor estable (<dim>_key), no por el rótulo.
  String clave(Fila f, String d) => '${f['${d}_key'] ?? f[d] ?? ''}';
  final catClaves = <String>[], categorias = <String>[], serieClaves = <String>[], rotulos = <String>[];
  for (final f in filas) {
    final ck = clave(f, dimTiempo);
    final sk = otras.map((d) => clave(f, d)).join('\u0001');
    if (!catClaves.contains(ck)) {
      catClaves.add(ck);
      categorias.add(fTiempo(dimTiempo, f[dimTiempo], eje: true));
    }
    if (!serieClaves.contains(sk)) {
      serieClaves.add(sk);
      rotulos.add(otras.map((d) => '${f[d] ?? ''}').join(' · '));
    }
  }
  final nombres = desambiguar(rotulos);
  final usados = serieClaves.take(maxSeries).toList();
  final datos = [for (var i = 0; i < usados.length; i++) List<double?>.filled(categorias.length, null)];
  final parcialesCat = <int>{};
  for (final f in filas) {
    final ci = catClaves.indexOf(clave(f, dimTiempo));
    final si = usados.indexOf(otras.map((d) => clave(f, d)).join('\u0001'));
    if (f['parcial'] == true) parcialesCat.add(ci);
    if (si >= 0) datos[si][ci] = _d(f[metrica]);
  }

  return GraficoVista(
    false,
    categorias,
    [for (var i = 0; i < usados.length; i++) SerieGrafico(nombres[i], datos[i])],
    parcialesCat.toList()..sort(),
    serieClaves.length > maxSeries,
    formato,
  );
}

List<String> avisosResultado(ResultadoReporte r, Pedido p, bool avisoMargen) {
  final avisos = <String>[
    if (avisoMargen)
      'Este reporte incluye Margen, que no ves con tu permiso: se muestra sin esa columna.',
    for (final o in r.meta.omitidas)
      if (o.id != 'margen') o.motivoEs,
  ];
  final cob = aNum(r.totales['cobertura_costo']);
  if (p.metrics.contains('margen') && r.columnas.any((c) => c.id == 'margen') && cob != null) {
    avisos.add(
        'Sólo el ${fEntero((cob * 100).round())} % de la venta tiene costo cargado: el margen se calcula sobre esa parte.');
  }

  return avisos;
}

List<String> notasAlPie(ResultadoReporte r, List<ColumnaVista> cols) {
  final notas = <String>[
    if (cols.any((c) => c.id == 'ticket_promedio' || c.id == 'aur'))
      'Promedio por ticket = venta ÷ tickets de cada fila; Precio por unidad = venta ÷ unidades.',
    if (cols.any((c) => c.auto)) 'Las columnas con « ·» se agregan solas al comparar.',
    if (r.filas.any((f) => f['parcial'] == true))
      '«parcial» = período todavía en curso: no se compara con uno completo.',
    ...r.meta.notasEs,
  ];
  final legacy = r.meta.fuentes['legacy'] ?? 0;
  final pos = r.meta.fuentes['pos'] ?? 0;
  if (legacy > 0 && pos > 0) {
    notas.add(
        'Origen de las ventas: ${fEntero(pos)} del POS · ${fEntero(legacy)} importadas del sistema anterior');
  }

  return notas;
}
