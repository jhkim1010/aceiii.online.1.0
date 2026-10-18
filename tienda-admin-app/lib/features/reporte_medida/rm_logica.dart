// Reporte a medida — reglas puras del constructor (port de a-medida/pedido-logica.ts).
// Anticipa en pantalla lo que el servidor rechazaría; POST /validar sigue siendo la fuente.
import 'rm_formato.dart';
import 'rm_modelos.dart';
import 'rm_periodo.dart';

// Espejo de api-ventago catalog.ts / order.validator.ts (igual que el espejo del front web).
const granoPorDimension = {
  'sucursal': 'cabecera',
  'dia': 'cabecera',
  'semana': 'cabecera',
  'mes': 'cabecera',
  'dia_semana': 'cabecera',
  'hora': 'cabecera',
  'vendedor': 'cabecera',
  'medio_pago': 'pago',
  'categoria': 'item',
  'temporada': 'item',
  'color': 'item',
  'talle': 'item',
  'producto': 'item',
};
const altaEstatica = ['vendedor', 'color', 'talle', 'producto'];
const umbralAlta = 30;
const maxMetricasUi = 4;
const _autoIds = ['unidades', 'tickets', 'aur'];

const copyMaxMetricas = 'Ya elegiste 4 medidas (el máximo).';
const copyMaxDimensiones = 'Ya elegiste 2 clasificaciones (máximo). Quitá una para elegir otra.';
const copySegundaAlta =
    'Sólo una clasificación con muchísimos valores (Producto, Color o Talle) a la vez.';
const copyProductoPago =
    'Producto × Medio de pago no está disponible: el pago es del ticket, no de cada producto.';
const copyItemPago =
    'No se puede combinar medio de pago con producto, categoría, temporada, color o talle: el pago no se reparte entre ítems.';
const copyCliente = 'son datos personales: necesita un permiso especial (no está en esta etapa).';
const copyMargenGuardado =
    'Este reporte incluye Margen, que no ves con tu permiso: se muestra sin esa columna.';

enum TipoBloqueo { permiso, combinacion, maximo, sinDatos }

class Bloqueo {
  final TipoBloqueo tipo;
  final String motivoEs;
  const Bloqueo(this.tipo, this.motivoEs);
}

class EstadoOpcion {
  final String id; // métrica, dimensión, 'tiempo' o 'cliente'
  final String labelEs;
  final bool elegida;
  final bool auto;
  final bool estatica;
  final Bloqueo? bloqueo;
  const EstadoOpcion(this.id, this.labelEs,
      {this.elegida = false, this.auto = false, this.estatica = false, this.bloqueo});
}

class ResultadoQuitar {
  final Pedido pedido;
  final String? avisoEs;
  const ResultadoQuitar(this.pedido, [this.avisoEs]);
}

List<String> _filtrosUsados(Pedido p) =>
    p.filters.entries.where((e) => e.value.isNotEmpty).map((e) => e.key).toList();

List<String> _dimensionesDelGrano(Catalogo c, Pedido p) {
  final deFiltros = <String>[];
  for (final f in _filtrosUsados(p)) {
    final d = c.filtros.where((x) => x.id == f).firstOrNull?.dimension;
    if (d != null && d.isNotEmpty) deFiltros.add(d);
  }

  return [...p.groupBy, ...deFiltros];
}

String granoDelPedido(Catalogo c, Pedido p) {
  final dims = _dimensionesDelGrano(c, p);
  if (dims.any((d) => granoPorDimension[d] == 'pago')) return 'pago';
  if (dims.any((d) => granoPorDimension[d] == 'item')) return 'item';

  return 'cabecera';
}

String? _motivoBloqueo(MetricaCatalogo m, String grano, List<String> dims, List<String> filtros) {
  for (final b in m.bloqueos) {
    final solo = b.soloConDimensiones;
    if (solo != null) {
      final fuera = dims.any((d) => !solo.contains(d));
      final filtroFuera = filtros.any((f) => f != 'sucursales');
      if (fuera || filtroFuera) return m.definicionEs;
      continue;
    }
    final porGrano = b.granos?.contains(grano) ?? false;
    final porDim = b.dimensiones?.any(dims.contains) ?? false;
    if ((porGrano || porDim) && b.motivoEs != null) return b.motivoEs;
  }

  return null;
}

String? _bloqueoPorPedido(Catalogo c, Pedido p, MetricaCatalogo m) =>
    _motivoBloqueo(m, granoDelPedido(c, p), p.groupBy, _filtrosUsados(p));

List<String> metricasAuto(Catalogo c, Pedido p) {
  if (p.compare == null) return const [];

  return _autoIds.where((id) {
    final m = c.metrica(id);

    return m != null && !p.metrics.contains(id) && !m.bloqueada && _bloqueoPorPedido(c, p, m) == null;
  }).toList();
}

List<EstadoOpcion> estadoMetricas(Catalogo c, Pedido p) {
  final auto = metricasAuto(c, p);
  final llenas = p.metrics.length >= maxMetricasUi;

  return c.metricas.map((m) {
    final elegida = p.metrics.contains(m.id);
    final esAuto = auto.contains(m.id);
    Bloqueo? bloqueo;
    if (m.bloqueada) {
      bloqueo = Bloqueo(TipoBloqueo.permiso, m.motivoEs ?? '');
    } else {
      final motivo = _bloqueoPorPedido(c, p, m);
      if (motivo != null) {
        bloqueo = Bloqueo(TipoBloqueo.combinacion, motivo);
      } else if (!elegida && !esAuto && llenas) {
        bloqueo = const Bloqueo(TipoBloqueo.maximo, copyMaxMetricas);
      }
    }

    return EstadoOpcion(m.id, m.labelEs, elegida: elegida, auto: esAuto, bloqueo: bloqueo);
  }).toList();
}

bool _esAlta(Catalogo c, String id) {
  if (!altaEstatica.contains(id)) return false;
  if (id == 'producto') return true;
  final card = c.dimension(id)?.cardinalidad;

  return card == null || card > umbralAlta;
}

Bloqueo? _bloqueoDeDimension(Catalogo c, Pedido p, String id) {
  final candidatas = id == 'tiempo' ? <String>[] : [id];
  final info = id == 'tiempo' ? null : c.dimension(id);
  if (info != null && !info.disponible) return Bloqueo(TipoBloqueo.sinDatos, info.motivoEs ?? '');
  if (p.groupBy.length >= 2) return const Bloqueo(TipoBloqueo.maximo, copyMaxDimensiones);

  final usadas = [..._dimensionesDelGrano(c, p), ...candidatas];
  final hayPago = usadas.any((d) => granoPorDimension[d] == 'pago');
  final hayItem = usadas.any((d) => granoPorDimension[d] == 'item');
  if (hayPago && hayItem) {
    return Bloqueo(TipoBloqueo.combinacion,
        usadas.contains('producto') ? copyProductoPago : copyItemPago);
  }

  final nuevaAlta = candidatas.any((d) => _esAlta(c, d));
  if (nuevaAlta && p.groupBy.any((d) => _esAlta(c, d))) {
    return const Bloqueo(TipoBloqueo.combinacion, copySegundaAlta);
  }

  return null;
}

List<EstadoOpcion> estadoDimensiones(Catalogo c, Pedido p) {
  final res = <EstadoOpcion>[];
  var tiempoPuesto = false;
  for (final d in c.dimensiones) {
    if (tiemposIds.contains(d.id)) {
      if (tiempoPuesto) continue;
      tiempoPuesto = true;
      final elegida = p.groupBy.any(tiemposIds.contains);
      res.add(EstadoOpcion('tiempo', 'Tiempo',
          elegida: elegida, bloqueo: elegida ? null : _bloqueoDeDimension(c, p, 'tiempo')));
      continue;
    }
    final elegida = p.groupBy.contains(d.id);
    res.add(EstadoOpcion(d.id, d.labelEs,
        elegida: elegida, bloqueo: elegida ? null : _bloqueoDeDimension(c, p, d.id)));
  }
  res.add(const EstadoOpcion('cliente', 'Cliente',
      estatica: true, bloqueo: Bloqueo(TipoBloqueo.permiso, copyCliente)));

  return res;
}

Pedido _sinSort(Pedido p) => p.copyWith(sort: null);

ResultadoQuitar quitarBloqueadas(Catalogo c, Pedido p) {
  final quitadas = <({String id, String label, String motivo})>[];
  for (final id in p.metrics) {
    final m = c.metrica(id);
    final motivo = m == null ? null : _bloqueoPorPedido(c, p, m);
    if (m != null && motivo != null) quitadas.add((id: id, label: m.labelEs, motivo: motivo));
  }
  if (quitadas.isEmpty) return ResultadoQuitar(p);

  final ids = quitadas.map((q) => q.id).toSet();
  var nuevo = p.copyWith(metrics: p.metrics.where((x) => !ids.contains(x)).toList());
  if (nuevo.sort != null && ids.contains(nuevo.sort!.by)) nuevo = _sinSort(nuevo);

  return ResultadoQuitar(
      nuevo, quitadas.map((q) => 'Quitamos ${q.label}: ${q.motivo}').join(' · '));
}

Pedido alternarMetrica(Catalogo c, Pedido p, String id) {
  if (p.metrics.contains(id)) {
    final nuevo = p.copyWith(metrics: p.metrics.where((x) => x != id).toList());

    return nuevo.sort?.by == id ? _sinSort(nuevo) : nuevo;
  }
  final e = estadoMetricas(c, p).where((x) => x.id == id).firstOrNull;
  if (e == null || e.bloqueo != null || p.metrics.length >= maxMetricasUi) return p;

  return p.copyWith(metrics: [...p.metrics, id]);
}

ResultadoQuitar alternarDimension(Catalogo c, Pedido p, String id) {
  final tiempoActual = p.groupBy.where(tiemposIds.contains).firstOrNull;
  final quitar = id == 'tiempo' ? tiempoActual : (p.groupBy.contains(id) ? id : null);
  Pedido nuevo;
  if (quitar != null) {
    nuevo = p.copyWith(groupBy: p.groupBy.where((d) => d != quitar).toList());
    if (nuevo.sort?.by == quitar) nuevo = _sinSort(nuevo);
  } else {
    if (_bloqueoDeDimension(c, p, id) != null) return ResultadoQuitar(p);
    nuevo = p.copyWith(groupBy: [...p.groupBy, id == 'tiempo' ? 'dia' : id]);
  }

  return quitarBloqueadas(c, nuevo);
}

Pedido cambiarGranoTiempo(Pedido p, String nuevo) {
  final actual = p.groupBy.where(tiemposIds.contains).firstOrNull;
  if (actual == null) return p.copyWith(groupBy: [...p.groupBy, nuevo]);
  var res = p.copyWith(groupBy: p.groupBy.map((d) => d == actual ? nuevo : d).toList());
  if (res.sort?.by == actual) res = res.copyWith(sort: (by: nuevo, dir: res.sort!.dir));

  return res;
}

// Abrir un guardado (D-12): sin permiso de margen se quita en memoria, con aviso.
ResultadoQuitar adaptarGuardado(Catalogo c, Pedido order) {
  final margenBloqueado = c.metrica('margen')?.bloqueada == true;
  var p = order;
  String? aviso;
  if (margenBloqueado && order.metrics.contains('margen')) {
    p = order.copyWith(metrics: order.metrics.where((x) => x != 'margen').toList());
    if (order.sort?.by == 'margen') {
      p = _sinSort(p);
      if (p.metrics.isNotEmpty) p = p.copyWith(sort: (by: p.metrics.first, dir: 'desc'));
    }
    aviso = copyMargenGuardado;
  }
  final q = quitarBloqueadas(c, p);
  final partes = [?aviso, ?q.avisoEs];

  return ResultadoQuitar(q.pedido, partes.isEmpty ? null : partes.join(' · '));
}

// Firma estable para saber si hay cambios sin guardar.
String firmaPedido(Pedido p) => _canonico(p.toJson());

String _canonico(dynamic x) {
  if (x is Map) {
    final ks = x.keys.map((k) => '$k').toList()..sort();

    return '{${ks.map((k) => '"$k":${_canonico(x[k])}').join(',')}}';
  }
  if (x is List) return '[${x.map(_canonico).join(',')}]';
  if (x is String) return '"$x"';

  return '$x';
}

class OpcionOrden {
  final String id;
  final String labelEs;
  final ({String by, String dir})? sort;
  const OpcionOrden(this.id, this.labelEs, this.sort);
}

List<OpcionOrden> opcionesOrden(Catalogo c, Pedido p) {
  final ops = <OpcionOrden>[];
  if (p.groupBy.any(tiemposIds.contains)) {
    ops.add(const OpcionOrden('natural', 'Fecha (orden natural)', null));
  } else if (p.groupBy.contains('talle')) {
    ops.add(const OpcionOrden('natural', 'Talle (orden natural)', null));
  } else if (p.groupBy.isEmpty) {
    return const [OpcionOrden('natural', 'Orden natural', null)];
  }
  for (final id in p.metrics) {
    final m = c.metrica(id);
    if (m != null) ops.add(OpcionOrden(id, '${m.labelEs} (mayor a menor)', (by: id, dir: 'desc')));
  }

  return ops;
}

// Resumen en una frase: segmentos (texto, negrita).
List<(String, bool)> resumenLocal(Catalogo c, Pedido p, String hoy) {
  final mets = p.metrics.map(c.labelMetrica).toList();
  final dims = p.groupBy.map((d) => c.labelDimension(d).toLowerCase()).toList();
  final segs = <(String, bool)>[(mets.isEmpty ? 'Sin medidas' : mets.join(', '), true)];
  if (dims.isNotEmpty) {
    segs
      ..add((' por ', false))
      ..add((dims.join(' y '), true));
  } else {
    segs.add((' por total del local', false));
  }
  var cola = '';
  try {
    final r = resolverPeriodo(p.period, hoy);
    cola += ', del ${fRangoFechas(r.desde, r.hasta)}';
  } catch (_) {
    // período inválido: se omite el rango
  }
  if (p.compare == 'periodo_anterior') cola += ', comparado con el período anterior';
  if (p.compare == 'anio_anterior') cola += ', comparado con el año anterior';
  if (p.top != null) cola += ', sólo los ${p.top} primeros';
  if (cola.isNotEmpty) segs.add((cola, false));

  return segs;
}

// Resumen corto para el encabezado de un paso plegado y para «Qué muestra».
String queMuestra(Pedido? p, Catalogo? c) {
  if (p == null || c == null) return raya;
  final mets = p.metrics.map(c.labelMetrica).join(', ');
  final dims = p.groupBy.map((d) => c.labelDimension(d).toLowerCase()).toList();

  return dims.isEmpty ? '$mets · total del local' : '$mets · por ${dims.join(' y ')}';
}

String nombreSugerido(Pedido p, Catalogo? c) {
  final met = p.metrics.isEmpty ? 'Reporte' : (c?.labelMetrica(p.metrics.first) ?? p.metrics.first);
  final dim = p.groupBy.firstOrNull;
  final base = dim == null
      ? '$met del local'
      : '$met por ${(c?.labelDimension(dim) ?? dim).toLowerCase()}';

  return base.length > 120 ? base.substring(0, 120) : base;
}

String nombreCopia(String nombre) {
  const suf = ' (copia)';
  final max = 120 - suf.length;

  return (nombre.length > max ? nombre.substring(0, max) : nombre) + suf;
}
