// Reporte a medida — reglas puras. Los catálogos de test/fixtures salen del construirCatalogo REAL
// del servidor (api-ventago dist, 2026-10-18), así un desalineo con el servidor rompe estas pruebas.
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tienda_admin_app/features/reporte_medida/rm_formato.dart';
import 'package:tienda_admin_app/features/reporte_medida/rm_logica.dart';
import 'package:tienda_admin_app/features/reporte_medida/rm_modelos.dart';
import 'package:tienda_admin_app/features/reporte_medida/rm_periodo.dart';
import 'package:tienda_admin_app/features/reporte_medida/rm_repository.dart';
import 'package:tienda_admin_app/features/reporte_medida/rm_resultado_vista.dart';

Catalogo _cat(String quien) =>
    Catalogo.fromJson(jsonDecode(File('test/fixtures/rm_catalogo_$quien.json').readAsStringSync()) as Map<String, dynamic>);

void main() {
  final admin = _cat('admin');
  final gerente = _cat('gerente');

  group('formato es-AR', () {
    test('moneda, entero, porcentaje desde fracción', () {
      expect(fMoneda(1234567), '\$ 1.234.567');
      expect(fMoneda(-5000), '−\$ 5.000');
      expect(fEntero(1984), '1.984');
      expect(fPorcentaje(0.255), '25,5 %');
      expect(fValor(null, 'moneda'), '—');
    });
    test('variación con flecha y signo (nunca sólo color)', () {
      expect(fVariacion(0.12).texto, '▲ +12 %');
      expect(fVariacion(-0.04).texto, '▼ −4 %');
      expect(fVariacion(0).signo, Signo.cero);
    });
    test('eje corto y fecha corta del eje (el largo se cortaba en «2026...»)', () {
      expect(fEjeCorto(1200000), '\$ 1,2 M');
      expect(fEjeCorto(380000), '\$ 380 mil');
      expect(fFechaEje('2026-10-18'), '18/10');
      expect(fFechaEje('Lunes'), 'Lunes');
    });
    test('rótulo de tiempo por grano', () {
      expect(fTiempo('mes', '2025-10-01'), 'oct 2025');
      expect(fTiempo('mes', '2025-10-01', eje: true), 'oct 25');
      expect(fTiempo('dia', '2026-09-19'), '19/09/2026');
      expect(fTiempo('dia', '2026-09-19', eje: true), '19/9');
      expect(fTiempo('dia_semana', 'Lunes'), 'Lunes');
    });
    test('rango de fechas', () {
      expect(fRangoFechas('2026-09-19', '2026-10-18'), '19 sep–18 oct 2026');
      expect(fRangoFechas('2025-12-20', '2026-01-05'), '20 dic 2025–5 ene 2026');
    });
  });

  group('período (espejo de period.ts)', () {
    const hoy = '2026-10-18'; // domingo
    test('presets', () {
      expect(resolverPeriodo({'preset': 'ultimos_30_dias'}, hoy), (desde: '2026-09-19', hasta: hoy));
      expect(resolverPeriodo({'preset': 'esta_semana'}, hoy), (desde: '2026-10-12', hasta: hoy));
      expect(resolverPeriodo({'preset': 'mes_pasado'}, hoy), (desde: '2026-09-01', hasta: '2026-09-30'));
      expect(resolverPeriodo({'preset': 'ultimos_12_meses'}, hoy), (desde: '2025-10-19', hasta: hoy));
    });
    test('comparación semanal alinea días de la semana; año anterior = 364 días', () {
      expect(comparacionLocal('2026-09-19', '2026-10-18', 'periodo_anterior', 'semanal'),
          (desde: '2026-08-15', hasta: '2026-09-13'));
      expect(comparacionLocal('2026-10-12', '2026-10-18', 'anio_anterior', 'semanal'),
          (desde: '2025-10-13', hasta: '2025-10-19'));
    });
    test('comparación calendario: mismas fechas del mes anterior', () {
      expect(comparacionLocal('2026-10-01', '2026-10-18', 'periodo_anterior', 'calendario'),
          (desde: '2026-09-01', hasta: '2026-09-18'));
      expect(comparacionLocal('2026-09-01', '2026-09-30', 'periodo_anterior', 'calendario'),
          (desde: '2026-08-01', hasta: '2026-08-31'));
    });
    test('hoy de Argentina por desfase fijo, no por el reloj del teléfono', () {
      // 02:30 UTC del 19 = 23:30 del 18 en Buenos Aires.
      expect(hoyDeCatalogo('America/Argentina/Buenos_Aires', DateTime.utc(2026, 10, 19, 2, 30)), '2026-10-18');
      expect(hoyDeCatalogo(null, DateTime.utc(2026, 10, 19, 3, 30)), '2026-10-19');
    });
  });

  group('constructor', () {
    test('margen bloqueado por permiso sólo para quien no es admin', () {
      final a = estadoMetricas(admin, Pedido.inicial).firstWhere((e) => e.id == 'margen');
      final g = estadoMetricas(gerente, Pedido.inicial).firstWhere((e) => e.id == 'margen');
      expect(a.bloqueo, isNull);
      expect(g.bloqueo?.tipo, TipoBloqueo.permiso);
      expect(g.bloqueo?.motivoEs, isNotEmpty);
    });
    test('Medio de pago quita Tickets y Promedio por ticket con aviso', () {
      final p = Pedido.inicial.copyWith(metrics: ['venta_neta', 'tickets', 'ticket_promedio'], groupBy: []);
      final r = alternarDimension(admin, p, 'medio_pago');
      expect(r.pedido.groupBy, ['medio_pago']);
      expect(r.pedido.metrics, ['venta_neta']);
      expect(r.avisoEs, contains('Quitamos'));
    });
    test('Producto × Medio de pago bloqueado con su motivo', () {
      final p = Pedido.inicial.copyWith(groupBy: ['producto']);
      final e = estadoDimensiones(admin, p).firstWhere((d) => d.id == 'medio_pago');
      expect(e.bloqueo?.motivoEs, copyProductoPago);
    });
    test('máximo 2 clasificaciones y 4 medidas', () {
      final p = Pedido.inicial.copyWith(groupBy: ['dia', 'sucursal']);
      expect(estadoDimensiones(admin, p).firstWhere((d) => d.id == 'vendedor').bloqueo?.tipo, TipoBloqueo.maximo);
      var q = Pedido.inicial.copyWith(metrics: ['venta_neta', 'unidades', 'tickets', 'devoluciones'], compare: null);
      q = alternarMetrica(admin, q, 'margen');
      expect(q.metrics.length, 4);
    });
    test('dimensión sin datos en la tienda queda visible y bloqueada', () {
      final e = estadoDimensiones(admin, Pedido.inicial).firstWhere((d) => d.id == 'categoria');
      expect(e.bloqueo?.tipo, TipoBloqueo.sinDatos);
      expect(estadoDimensiones(admin, Pedido.inicial).last.id, 'cliente');
    });
    test('comparar agrega Unidades/Tickets automáticas que no cuentan para el máximo', () {
      final p = Pedido.inicial.copyWith(metrics: ['venta_neta']);
      expect(metricasAuto(admin, p), containsAll(['unidades', 'tickets']));
      expect(metricasAuto(admin, p.copyWith(compare: null)), isEmpty);
    });
    test('guardado con margen abierto por un gerente: se quita con aviso', () {
      final order = Pedido.inicial.copyWith(metrics: ['venta_neta', 'margen'], sort: (by: 'margen', dir: 'desc'));
      final r = adaptarGuardado(gerente, order);
      expect(r.pedido.metrics, ['venta_neta']);
      expect(r.pedido.sort?.by, 'venta_neta');
      expect(r.avisoEs, contains(copyMargenGuardado));
      expect(adaptarGuardado(admin, order).pedido.metrics, contains('margen'));
    });
    test('cambiar el tiempo conserva la posición y el orden', () {
      final p = Pedido.inicial.copyWith(groupBy: ['sucursal', 'dia'], sort: (by: 'dia', dir: 'asc'));
      final r = cambiarGranoTiempo(p, 'semana');
      expect(r.groupBy, ['sucursal', 'semana']);
      expect(r.sort?.by, 'semana');
    });
  });

  group('pedido JSON', () {
    test('sólo claves del contrato, sin filtros vacíos; conserva el preset', () {
      final p = Pedido.inicial.copyWith(filters: {'vendedores': [], 'sucursales': [3]});
      final j = p.toJson();
      expect(j['filters'], {'sucursales': [3]});
      expect(j['period'], {'preset': 'ultimos_30_dias'});
      expect(j.containsKey('storeId'), isFalse);
      expect(j.keys.toSet().difference({'v', 'type', 'metrics', 'groupBy', 'period', 'compare', 'filters', 'sort', 'top', 'participacion'}),
          isEmpty);
    });
    test('el arreglo en un clic fusiona el patch del servidor', () {
      final p = Pedido.inicial.copyWith(period: {'preset': 'ultimos_12_meses'});
      expect(p.aplicarPatch({'groupBy': ['semana']}).groupBy, ['semana']);
      expect(p.aplicarPatch({'period': {'preset': 'ultimos_90_dias'}}).preset, 'ultimos_90_dias');
      expect(p.aplicarPatch({'compare': null}).compare, isNull);
      expect(p.aplicarPatch({'top': 20}).top, 20);
    });
    test('la firma no depende del orden de las claves', () {
      final a = Pedido.fromJson({'metrics': ['venta_neta'], 'groupBy': ['dia'], 'period': {'preset': 'hoy'}, 'compare': null});
      final b = Pedido.fromJson({'compare': null, 'period': {'preset': 'hoy'}, 'groupBy': ['dia'], 'metrics': ['venta_neta']});
      expect(firmaPedido(a), firmaPedido(b));
      expect(firmaPedido(a), isNot(firmaPedido(a.copyWith(top: 10))));
    });
  });

  group('resultado', () {
    ResultadoReporte res(List<Map<String, dynamic>> filas, {bool comp = true}) => ResultadoReporte.fromJson({
          'columnas': [
            {'id': 'dia', 'labelEs': 'Día', 'tipo': 'dimension'},
            {'id': 'vendedor', 'labelEs': 'Vendedor', 'tipo': 'dimension'},
            {'id': 'venta_neta', 'labelEs': 'Venta neta', 'tipo': 'metrica', 'formato': 'moneda'},
            {'id': 'unidades', 'labelEs': 'Unidades', 'tipo': 'metrica', 'formato': 'entero'},
            if (comp) {'id': 'venta_neta_comp', 'labelEs': 'Venta neta (comp.)', 'tipo': 'metrica'},
            if (comp) {'id': 'venta_neta_var_pct', 'labelEs': 'Var.', 'tipo': 'metrica', 'formato': 'porcentaje'},
          ],
          'filas': filas,
          'totales': {'venta_neta': 300, 'unidades': 3},
          'comparacion': comp
              ? {
                  'desde': '2026-09-01',
                  'hasta': '2026-09-02',
                  'variacionTotal': {
                    'venta_neta': {'varPct': 0.12, 'parcial': true, 'hastaComparable': '2026-10-17'},
                  },
                }
              : null,
          'meta': {'desde': '2026-10-17', 'hasta': '2026-10-18', 'filas': filas.length, 'fuentes': {'pos': 2, 'legacy': 1}},
        });

    test('las series se identifican por <dim>_key: dos vendedores con el mismo nombre no se funden', () {
      final r = res([
        {'dia': '2026-10-17', 'dia_key': '2026-10-17', 'vendedor': 'Ana', 'vendedor_key': 1, 'venta_neta': 100},
        {'dia': '2026-10-17', 'dia_key': '2026-10-17', 'vendedor': 'Ana', 'vendedor_key': 2, 'venta_neta': 50},
        {'dia': '2026-10-18', 'dia_key': '2026-10-18', 'vendedor': 'Ana', 'vendedor_key': 1, 'venta_neta': 150, 'parcial': true},
      ]);
      final p = Pedido.inicial.copyWith(groupBy: ['dia', 'vendedor'], metrics: ['venta_neta']);
      final g = seriesGrafico(r, p, 'venta_neta')!;
      expect(g.series.map((s) => s.nombre), ['Ana', 'Ana (2)']);
      expect(g.categorias, ['17/10', '18/10']);
      expect(g.series[0].data, [100, 150]);
      expect(g.series[1].data, [50, null]);
      expect(g.parcialesIdx, [1]);
    });
    test('desambiguar no pisa un nombre real', () {
      expect(desambiguar(['Ana', 'Ana', 'Ana (2)']), ['Ana', 'Ana (3)', 'Ana (2)']);
    });
    test('columnas: auto marcadas, variaciones al final; fila parcial no se compara', () {
      final r = res([
        {'dia': 'x', 'dia_key': 'x', 'vendedor': 'A', 'vendedor_key': 1, 'venta_neta': 1, 'venta_neta_var_pct': 0.5, 'parcial': true},
      ]);
      final p = Pedido.inicial.copyWith(metrics: ['venta_neta']);
      final cols = columnasVista(r, p);
      expect(cols.map((c) => c.header), ['Día', 'Vendedor', 'Venta neta', 'Unidades ·', 'Var. venta']);
      expect(celdaVariacion(r.filas.first, 'venta_neta_var_pct').texto, 'parcial · sin comparar');
      expect(filaTotal(r, cols)['venta_neta_var_pct'], 0.12);
    });
    test('titular con período en curso', () {
      final t = titularComparacion(res(const []))!;
      expect(t.partes.single.texto, '▲ +12 %');
      expect(t.sufijoHasta, 'hasta 17/10/2026');
    });
    test('notas: origen de ventas cuando hay POS e importadas', () {
      final r = res(const []);
      expect(notasAlPie(r, columnasVista(r, Pedido.inicial)).last, contains('importadas del sistema anterior'));
    });
  });

  group('errores HTTP → estado', () {
    DioException err(int status, Object data) => DioException(
        requestOptions: RequestOptions(path: '/x'),
        response: Response(requestOptions: RequestOptions(path: '/x'), statusCode: status, data: data));

    test('400 con errores = validación con arreglos', () {
      final e = clasificarError(err(400, {
        'errores': [
          {'code': 'DIA_MAX', 'messageEs': 'Por día se puede ver hasta 90 días.', 'fixes': [{'labelEs': 'Últimos 90 días', 'patch': {'period': {'preset': 'ultimos_90_dias'}}}]}
        ]
      }));
      expect(e.tipo, TipoErrorRm.validacion);
      expect(e.errores.single.fixes.single.patch, {'period': {'preset': 'ultimos_90_dias'}});
    });
    test('403 sin errores = permiso; 429 = ocupado; sin respuesta = red', () {
      expect(clasificarError(err(403, {})).tipo, TipoErrorRm.permiso);
      expect(clasificarError(err(429, {})).mensajeEs, copyOcupado);
      expect(clasificarError(DioException(requestOptions: RequestOptions(path: '/x'))).tipo, TipoErrorRm.red);
    });
  });
}
