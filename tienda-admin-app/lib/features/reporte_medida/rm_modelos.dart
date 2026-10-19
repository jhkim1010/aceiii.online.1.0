// Reporte a medida — contrato del servidor (api-ventago/src/app/reporte-medida).
// Port de ventago-app/src/views/reports-v2/a-medida/tipos.ts. Sólo modelos + JSON.
import '../../shared/format.dart';

const tiemposIds = ['dia', 'semana', 'mes', 'dia_semana', 'hora'];

// Pedido v1. El front NUNCA manda la tienda ni permisos (la fuerza el servidor).
class Pedido {
  final List<String> metrics;
  final List<String> groupBy;

  // {preset: 'ultimos_30_dias'} | {from: 'YYYY-MM-DD', to: 'YYYY-MM-DD'}
  final Map<String, String> period;
  final String? compare; // null | periodo_anterior | anio_anterior
  final Map<String, List<int>> filters;
  final ({String by, String dir})? sort;
  final int? top;
  final bool? participacion;

  const Pedido({
    required this.metrics,
    required this.groupBy,
    required this.period,
    this.compare,
    this.filters = const {},
    this.sort,
    this.top,
    this.participacion,
  });

  static const inicial = Pedido(
    metrics: ['venta_neta', 'unidades'],
    groupBy: ['dia'],
    period: {'preset': 'ultimos_30_dias'},
    compare: 'periodo_anterior',
  );

  String? get preset => period['preset'];

  Pedido copyWith({
    List<String>? metrics,
    List<String>? groupBy,
    Map<String, String>? period,
    Object? compare = _sin,
    Map<String, List<int>>? filters,
    Object? sort = _sin,
    Object? top = _sin,
  }) {
    return Pedido(
      metrics: metrics ?? this.metrics,
      groupBy: groupBy ?? this.groupBy,
      period: period ?? this.period,
      compare: identical(compare, _sin) ? this.compare : compare as String?,
      filters: filters ?? this.filters,
      sort: identical(sort, _sin) ? this.sort : sort as ({String by, String dir})?,
      top: identical(top, _sin) ? this.top : top as int?,
      participacion: participacion,
    );
  }

  // Sólo claves del contrato v1, sin filtros vacíos ni nulos (conserva el preset, D-14).
  Map<String, dynamic> toJson() {
    final f = <String, List<int>>{
      for (final e in filters.entries)
        if (e.value.isNotEmpty) e.key: e.value,
    };

    return {
      'v': 1,
      'type': 'ventas',
      'metrics': metrics,
      'groupBy': groupBy,
      'period': period,
      'compare': compare,
      if (f.isNotEmpty) 'filters': f,
      if (sort != null) 'sort': {'by': sort!.by, 'dir': sort!.dir},
      if (top != null) 'top': top,
      if (participacion != null) 'participacion': participacion,
    };
  }

  factory Pedido.fromJson(Map<String, dynamic> j) {
    final per = (j['period'] as Map?) ?? const {'preset': 'ultimos_30_dias'};
    final s = j['sort'] as Map?;
    final filtros = <String, List<int>>{};
    final fj = j['filters'];
    if (fj is Map) {
      for (final e in fj.entries) {
        if (e.value is List) {
          filtros['${e.key}'] = (e.value as List).map(asInt).toList();
        }
      }
    }

    return Pedido(
      metrics: ((j['metrics'] as List?) ?? const []).map((e) => '$e').toList(),
      groupBy: ((j['groupBy'] as List?) ?? const []).map((e) => '$e').toList(),
      period: per.map((k, v) => MapEntry('$k', '$v')),
      compare: j['compare'] as String?,
      filters: filtros,
      sort: s == null ? null : (by: '${s['by']}', dir: '${s['dir'] ?? 'desc'}'),
      top: j['top'] == null ? null : asInt(j['top']),
      participacion: j['participacion'] as bool?,
    );
  }

  // «Arreglo en un clic»: fusiona el patch del servidor sobre el nivel raíz.
  Pedido aplicarPatch(Map<String, dynamic>? patch) {
    if (patch == null || patch.isEmpty) return this;

    return Pedido.fromJson({...toJson(), ...patch});
  }
}

const _sin = Object();

class FixPedido {
  final String labelEs;
  final Map<String, dynamic>? patch;
  FixPedido.fromJson(Map<String, dynamic> j)
      : labelEs = '${j['labelEs'] ?? ''}',
        patch = (j['patch'] as Map?)?.cast<String, dynamic>();
}

class ErrorPedido {
  final String code;
  final String messageEs;
  final List<FixPedido> fixes;
  ErrorPedido(this.code, this.messageEs, [this.fixes = const []]);
  ErrorPedido.fromJson(Map<String, dynamic> j)
      : code = '${j['code'] ?? ''}',
        messageEs = '${j['messageEs'] ?? ''}',
        fixes = ((j['fixes'] as List?) ?? const [])
            .map((e) => FixPedido.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
}

class BloqueoMetrica {
  final List<String>? dimensiones;
  final List<String>? granos;
  final String? motivoEs;
  final List<String>? soloConDimensiones;
  BloqueoMetrica.fromJson(Map<String, dynamic> j)
      : dimensiones = _strs(j['dimensiones']),
        granos = _strs(j['granos']),
        motivoEs = j['motivoEs'] as String?,
        soloConDimensiones = _strs(j['soloConDimensiones']);
}

List<String>? _strs(dynamic v) => v is List ? v.map((e) => '$e').toList() : null;

class MetricaCatalogo {
  final String id;
  final String labelEs;
  final String definicionEs;
  final String formato;
  final bool bloqueada;
  final String? motivoEs;
  final List<BloqueoMetrica> bloqueos;
  MetricaCatalogo.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        labelEs = '${j['labelEs'] ?? j['id']}',
        definicionEs = '${j['definicionEs'] ?? ''}',
        formato = '${j['formato'] ?? 'entero'}',
        bloqueada = j['bloqueada'] == true,
        motivoEs = j['motivoEs'] as String?,
        bloqueos = ((j['bloqueos'] as List?) ?? const [])
            .map((e) => BloqueoMetrica.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
}

class DimensionCatalogo {
  final String id;
  final String labelEs;
  final String grupo;
  final bool disponible;
  final String? motivoEs;
  final int? cardinalidad;
  DimensionCatalogo.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        labelEs = '${j['labelEs'] ?? j['id']}',
        grupo = '${j['grupo'] ?? 'otra'}',
        disponible = j['disponible'] != false,
        motivoEs = j['motivoEs'] as String?,
        cardinalidad = j['cardinalidad'] == null ? null : asInt(j['cardinalidad']);
}

class FiltroCatalogo {
  final String id;
  final String labelEs;
  final String dimension;
  FiltroCatalogo.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        labelEs = '${j['labelEs'] ?? j['id']}',
        dimension = '${j['dimension'] ?? ''}';
}

class OpcionCatalogo {
  final String id;
  final String labelEs;
  final bool disponible;
  final String? motivoEs;
  OpcionCatalogo.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        labelEs = '${j['labelEs'] ?? j['id']}',
        disponible = j['disponible'] != false,
        motivoEs = j['motivoEs'] as String?;
}

class PlantillaCatalogo {
  final String id;
  final String labelEs;
  final String descripcionEs;
  final bool disponible;
  final String? motivoEs;
  final Pedido? pedido;
  final String? enlaceLabelEs;
  PlantillaCatalogo.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        labelEs = '${j['labelEs'] ?? ''}',
        descripcionEs = '${j['descripcionEs'] ?? ''}',
        disponible = j['disponible'] != false,
        motivoEs = j['motivoEs'] as String?,
        pedido = j['pedido'] is Map
            ? Pedido.fromJson((j['pedido'] as Map).cast<String, dynamic>())
            : null,
        enlaceLabelEs = (j['enlace'] as Map?)?['labelEs'] as String?;
}

class Catalogo {
  final int version;
  final String? zonaHoraria;
  final List<OpcionCatalogo> tiposReporte;
  final List<MetricaCatalogo> metricas;
  final List<DimensionCatalogo> dimensiones;
  final List<FiltroCatalogo> filtros;
  final Map<String, num> limites;
  final List<OpcionCatalogo> presetsPeriodo;
  final List<PlantillaCatalogo> plantillas;

  Catalogo.fromJson(Map<String, dynamic> j)
      : version = asInt(j['version']),
        zonaHoraria = j['zonaHoraria'] as String?,
        tiposReporte = _lista(j['tiposReporte'], OpcionCatalogo.fromJson),
        metricas = _lista(j['metricas'], MetricaCatalogo.fromJson),
        dimensiones = _lista(j['dimensiones'], DimensionCatalogo.fromJson),
        filtros = _lista(j['filtros'], FiltroCatalogo.fromJson),
        limites = ((j['limites'] as Map?) ?? const {})
            .map((k, v) => MapEntry('$k', asNum(v))),
        presetsPeriodo = _lista(j['presetsPeriodo'], OpcionCatalogo.fromJson),
        plantillas = _lista(j['plantillas'], PlantillaCatalogo.fromJson);

  MetricaCatalogo? metrica(String id) =>
      metricas.where((m) => m.id == id).firstOrNull;
  DimensionCatalogo? dimension(String id) =>
      dimensiones.where((d) => d.id == id).firstOrNull;
  String labelMetrica(String id) => metrica(id)?.labelEs ?? id;
  String labelDimension(String id) => dimension(id)?.labelEs ?? id;
}

List<T> _lista<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    ((v as List?) ?? const []).map((e) => f((e as Map).cast<String, dynamic>())).toList();

class ValidarRespuesta {
  final bool ok;
  final String? resumenEs;
  final int? filasEstimadas;
  final List<ErrorPedido> errores;
  ValidarRespuesta.fromJson(Map<String, dynamic> j)
      : ok = j['ok'] == true,
        resumenEs = j['resumenEs'] as String?,
        filasEstimadas =
            j['filasEstimadas'] == null ? null : asInt(j['filasEstimadas']),
        errores = _lista(j['errores'], ErrorPedido.fromJson);
}

class ColumnaDef {
  final String id;
  final String labelEs;
  final String tipo; // dimension | metrica
  final String? formato;
  // Las partes suman el total (habilita la torta). Servidores viejos no lo mandan → sin torta.
  final bool aditiva;
  ColumnaDef.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        labelEs = '${j['labelEs'] ?? j['id']}',
        tipo = '${j['tipo'] ?? 'metrica'}',
        formato = j['formato'] as String?,
        aditiva = j['aditiva'] == true;
}

typedef Fila = Map<String, dynamic>;

class VariacionTotal {
  final num? varPct;
  final num? anterior;
  final bool parcial;
  final String? hastaComparable;
  VariacionTotal.fromJson(Map<String, dynamic> j)
      : varPct = j['varPct'] == null ? null : asNum(j['varPct']),
        anterior = j['anterior'] == null ? null : asNum(j['anterior']),
        parcial = j['parcial'] == true,
        hastaComparable = j['hastaComparable'] as String?;
}

class Comparacion {
  final String desde;
  final String hasta;
  final Map<String, VariacionTotal> variacionTotal;
  Comparacion.fromJson(Map<String, dynamic> j)
      : desde = '${j['desde'] ?? ''}',
        hasta = '${j['hasta'] ?? ''}',
        variacionTotal = ((j['variacionTotal'] as Map?) ?? const {}).map(
            (k, v) => MapEntry('$k', VariacionTotal.fromJson((v as Map).cast<String, dynamic>())));
}

class Omitida {
  final String id;
  final String motivoEs;
  Omitida.fromJson(Map<String, dynamic> j)
      : id = '${j['id']}',
        motivoEs = '${j['motivoEs'] ?? ''}';
}

class MetaResultado {
  final String desde;
  final String hasta;
  final bool truncado;
  final int filas;
  final Map<String, num> fuentes;
  final List<Omitida> omitidas;
  final String definicionVentaEs;
  final List<String> notasEs;
  final bool catalogoCambio;
  // Top N aplicado (el total sigue siendo del período) y si la venta neta resta devoluciones.
  // Un servidor viejo no los manda: null = sin dato.
  final int? top;
  final bool? devolucionesRestadas;
  MetaResultado.fromJson(Map<String, dynamic> j)
      : desde = '${j['desde'] ?? ''}',
        hasta = '${j['hasta'] ?? ''}',
        truncado = j['truncado'] == true,
        filas = asInt(j['filas']),
        fuentes = ((j['fuentes'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', asNum(v))),
        omitidas = _lista(j['omitidas'], Omitida.fromJson),
        definicionVentaEs = '${j['definicionVentaEs'] ?? ''}',
        notasEs = _strs(j['notasEs']) ?? const [],
        catalogoCambio = j['catalogoCambio'] == true,
        top = j['top'] == null ? null : asInt(j['top']),
        devolucionesRestadas = j['devolucionesRestadas'] is bool ? j['devolucionesRestadas'] as bool : null;
}

class ResultadoReporte {
  final List<ColumnaDef> columnas;
  final List<Fila> filas;
  final Fila totales;
  final Comparacion? comparacion;
  final MetaResultado meta;
  ResultadoReporte.fromJson(Map<String, dynamic> j)
      : columnas = _lista(j['columnas'], ColumnaDef.fromJson),
        filas = ((j['filas'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList(),
        totales = ((j['totales'] as Map?) ?? const {}).cast<String, dynamic>(),
        comparacion = j['comparacion'] is Map
            ? Comparacion.fromJson((j['comparacion'] as Map).cast<String, dynamic>())
            : null,
        meta = MetaResultado.fromJson(((j['meta'] as Map?) ?? const {}).cast<String, dynamic>());
}

class GuardadoListado {
  final int id;
  final String name;
  final bool shared;
  final int position;
  final bool esMio;
  final String? autorNombre;
  final Pedido? order;
  final bool catalogoCambio;
  GuardadoListado.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        name = '${j['name'] ?? ''}',
        shared = j['shared'] == true,
        position = asInt(j['position']),
        esMio = j['esMio'] == true,
        autorNombre = j['autorNombre'] as String?,
        order = j['order'] is Map
            ? Pedido.fromJson((j['order'] as Map).cast<String, dynamic>())
            : null,
        catalogoCambio = j['catalogoCambio'] == true;
}

class GuardadoDetalle {
  final int id;
  final String name;
  final bool shared;
  final bool esMio;
  final Pedido order;
  final bool catalogoCambio;
  GuardadoDetalle.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        name = '${j['name'] ?? ''}',
        shared = j['shared'] == true,
        esMio = j['esMio'] == true,
        order = Pedido.fromJson(((j['order'] as Map?) ?? const {}).cast<String, dynamic>()),
        catalogoCambio = j['catalogoCambio'] == true;
}
