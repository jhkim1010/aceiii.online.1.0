// Reporte a medida — los 4 pasos del constructor (contenido de cada RmPasoCard).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../auth/auth_controller.dart';
import 'rm_controller.dart';
import 'rm_formato.dart';
import 'rm_logica.dart';
import 'rm_modelos.dart';
import 'rm_periodo.dart';
import 'rm_repository.dart';
import 'rm_widgets.dart';

const _subMetrica = {
  'ticket_promedio': 'cuánto gasta cada cliente',
  'aur': 'cuánto vale cada prenda',
};

// ── Paso 1 ──
class PasoMetricas extends ConsumerStatefulWidget {
  const PasoMetricas({super.key});

  @override
  ConsumerState<PasoMetricas> createState() => _PasoMetricasState();
}

class _PasoMetricasState extends ConsumerState<PasoMetricas> {
  String _definicion = 'venta_neta';

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(rmControllerProvider);
    final c = st.catalogo!;
    final p = st.pedido;
    final estados = estadoMetricas(c, p);
    final def = c.metrica(_definicion);
    final hayAuto = estados.any((e) => e.auto);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in estados)
          RmChip(
            label: e.labelEs,
            sub: _subMetrica[e.id],
            elegida: e.elegida,
            auto: e.auto,
            bloqueo: e.bloqueo,
            onTap: () {
              setState(() => _definicion = e.id);
              ref.read(rmControllerProvider.notifier).alternarMetrica(e.id);
            },
          ),
      ]),
      if (p.metrics.length >= maxMetricasUi)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text(copyMaxMetricas, style: TextStyle(fontSize: 12, color: rmCerca)),
        ),
      if (hayAuto)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Las medidas con «+» se agregan solas porque estás comparando; no cuentan para el máximo de 4.',
              style: TextStyle(fontSize: 11, color: AppColors.dim)),
        ),
      if (def != null) ...[
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: AppColors.navy2, borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.line)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.info_outline, size: 16, color: rmInfo),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: def.labelEs, style: const TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: ' — ${def.definicionEs}'),
                ]),
                style: const TextStyle(fontSize: 12, height: 1.4),
              ),
            ),
          ]),
        ),
      ],
      if (p.metrics.contains('margen')) ...[
        const SizedBox(height: 8),
        const RmAviso.dorado(
            'La ganancia bruta se calcula sólo sobre la parte de la venta con costo cargado; el porcentaje exacto aparece al ver el reporte.'),
      ],
      RmRazones(estados),
    ]);
  }
}

// ── Paso 2 ──
class PasoAgrupaciones extends ConsumerWidget {
  const PasoAgrupaciones({super.key});

  static const _tiempos = [
    ('dia', 'Día'),
    ('semana', 'Semana'),
    ('mes', 'Mes'),
    ('dia_semana', 'Día de la semana'),
    ('hora', 'Hora'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(rmControllerProvider);
    final c = st.catalogo!;
    final p = st.pedido;
    final ctrl = ref.read(rmControllerProvider.notifier);
    final estados = estadoDimensiones(c, p);
    final tiempo = p.groupBy.where(tiemposIds.contains).firstOrNull;
    final usadaAlta = p.groupBy.any((d) => d == 'producto' || d == 'color' || d == 'talle');

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in estados)
          RmChip(
            label: e.labelEs,
            elegida: e.elegida,
            bloqueo: e.bloqueo,
            onTap: e.estatica ? null : () => ctrl.alternarDimension(e.id),
          ),
      ]),
      if (tiempo != null) ...[
        const SizedBox(height: 12),
        const Text('Tiempo por', style: TextStyle(fontSize: 12, color: AppColors.dim)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (id, label) in _tiempos)
            if (c.dimension(id)?.disponible ?? false)
              ChoiceChip(
                label: Text(label),
                selected: tiempo == id,
                selectedColor: AppColors.gold.withValues(alpha: 0.14),
                labelStyle: TextStyle(
                    fontSize: 13,
                    color: tiempo == id ? AppColors.gold : AppColors.txt,
                    fontWeight: tiempo == id ? FontWeight.w700 : FontWeight.w400),
                side: BorderSide(color: tiempo == id ? AppColors.gold : AppColors.line),
                showCheckmark: false,
                onSelected: (_) => ctrl.cambiar(cambiarGranoTiempo(p, id)),
              ),
        ]),
      ],
      const SizedBox(height: 8),
      Text(
        p.groupBy.length >= 2
            ? 'Ya tenés 2 clasificaciones (el máximo).'
            : usadaAlta
                ? 'Producto, Color y Talle: ya usaste la única permitida.'
                : 'Podés agregar una clasificación más.',
        style: TextStyle(fontSize: 11, color: p.groupBy.length >= 2 ? rmCerca : AppColors.dim),
      ),
      RmRazones(estados),
    ]);
  }
}

// ── Paso 3 ──
class PasoPeriodo extends ConsumerWidget {
  const PasoPeriodo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(rmControllerProvider);
    final c = st.catalogo!;
    final p = st.pedido;
    final ctrl = ref.read(rmControllerProvider.notifier);
    final storeId = ref.watch(currentStoreIdProvider) ?? 0;
    final sucursales = ref.watch(rmValoresFiltroProvider(('sucursales', storeId))).valueOrNull ?? const [];
    final hoy = hoyDeCatalogo(c.zonaHoraria);
    final errPeriodo = st.validacion.errores.any((e) => e.fixes.any((f) => f.patch?.containsKey('period') ?? false));

    String etiquetaPeriodo() {
      final pre = p.preset;
      if (pre != null) return c.presetsPeriodo.where((x) => x.id == pre).firstOrNull?.labelEs ?? pre;
      try {
        final r = resolverPeriodo(p.period, hoy);

        return '${fFechaCorta(r.desde)} – ${fFechaCorta(r.hasta)}';
      } catch (_) {
        return 'Rango de fechas';
      }
    }

    Widget lineaRango() {
      try {
        final r = resolverPeriodo(p.period, hoy);
        final n = diasEnRango(r.desde, r.hasta);

        return Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'Del '),
            TextSpan(text: fRangoFechas(r.desde, r.hasta), style: const TextStyle(color: AppColors.txt)),
            TextSpan(text: ' · $n ${n == 1 ? 'día' : 'días'}'),
            if (incluyeHoy(r.desde, r.hasta, hoy))
              const TextSpan(text: ' · incluye hoy (parcial)', style: TextStyle(color: AppColors.gold)),
          ]),
          style: const TextStyle(fontSize: 12, color: AppColors.dim),
        );
      } catch (_) {
        return const SizedBox.shrink();
      }
    }

    Future<void> elegirPeriodo() async {
      final v = await rmElegir<String>(
          context,
          'Período',
          [for (final o in c.presetsPeriodo) (o.id, o.labelEs), ('__rango', 'Rango de fechas…')],
          p.preset ?? '__rango');
      if (v == null || !context.mounted) return;
      if (v != '__rango') {
        ctrl.cambiar(p.copyWith(period: {'preset': v}));

        return;
      }
      final hoyDt = DateTime.parse(hoy);
      final r = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2015),
        lastDate: hoyDt,
        // Sin `locale`: la app no carga flutter_localizations y pasarlo rompería el selector.
        helpText: 'Rango de fechas',
        saveText: 'Usar',
        cancelText: 'Cancelar',
      );
      if (r != null) ctrl.cambiar(p.copyWith(period: {'from': fmtYmd(r.start), 'to': fmtYmd(r.end)}));
    }

    final sucId = p.filters['sucursales']?.firstOrNull;
    final ordenes = opcionesOrden(c, p);
    // Un Top sin orden elegido el servidor lo ordena por venta (o la 1ª medida): el selector lo muestra.
    final ordenEfectivo = p.sort ?? (p.top != null ? ordenDelTop(p) : null);
    final ordenActual = ordenEfectivo == null ? 'natural' : ordenEfectivo.by;
    final usados = p.filters.entries.where((e) => e.key != 'sucursales' && e.value.isNotEmpty).length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RmCampo(label: 'Período', valor: etiquetaPeriodo(), error: errPeriodo, onTap: elegirPeriodo),
      const SizedBox(height: 6),
      lineaRango(),
      if (sucursales.length >= 2) ...[
        const SizedBox(height: 12),
        RmCampo(
          label: 'Sólo la sucursal',
          valor: sucursales.where((s) => s.$1 == sucId).firstOrNull?.$2 ?? 'Todas',
          onTap: () async {
            final v = await rmElegir<int>(context, 'Sucursal', [(0, 'Todas'), ...sucursales], sucId ?? 0);
            if (v == null) return;
            final f = {...p.filters};
            if (v == 0) {
              f.remove('sucursales');
            } else {
              f['sucursales'] = [v];
            }
            ctrl.cambiar(p.copyWith(filters: f));
          },
        ),
      ],
      const SizedBox(height: 12),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: AppColors.txt,
            side: const BorderSide(color: AppColors.line),
            alignment: Alignment.centerLeft),
        icon: const Icon(Icons.tune, size: 18),
        label: Text(usados == 0 ? 'Más filtros (vendedor, medio de pago, talle…)' : 'Más filtros · $usados en uso'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MasFiltrosScreen())),
      ),
      const SizedBox(height: 12),
      Row(children: [
        if (ordenes.length > 1) ...[
          Expanded(
            child: RmCampo(
              label: 'Ordenar por',
              valor: ordenes.where((o) => o.id == ordenActual).firstOrNull?.labelEs ?? ordenes.first.labelEs,
              onTap: () async {
                final v = await rmElegir<String>(
                    context, 'Ordenar por', [for (final o in ordenes) (o.id, o.labelEs)], ordenActual);
                if (v == null) return;
                ctrl.cambiar(p.copyWith(sort: ordenes.firstWhere((o) => o.id == v).sort));
              },
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: RmCampo(
            label: 'Filas',
            valor: p.top == null ? 'Todas' : 'Top ${p.top}',
            onTap: () async {
              final v = await rmElegir<int>(
                  context,
                  'Filas',
                  [(0, 'Todas (en pantalla hasta 1.000 · CSV hasta 10.000)'), for (final n in [10, 20, 50, 100]) (n, 'Top $n')],
                  p.top ?? 0);
              // El orden del Top no se guarda: el servidor ordena un Top sin orden por venta y el
              // selector lo muestra. Así volver a «Todas» recupera el orden natural (CODEX 8d449ea).
              if (v != null) ctrl.cambiar(p.copyWith(top: v == 0 ? null : v));
            },
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Text(
        'Fechas en hora del local${c.zonaHoraria == null ? '' : ' (${c.zonaHoraria!.split('/').last.replaceAll('_', ' ')})'}. '
        'Ventas anuladas no cuentan. Incluye ventas importadas del sistema anterior.',
        style: const TextStyle(fontSize: 11, color: AppColors.dim, height: 1.4),
      ),
    ]);
  }
}

// «Más filtros»: pantalla propia con un selector múltiple por filtro del catálogo.
class MasFiltrosScreen extends ConsumerWidget {
  const MasFiltrosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(rmControllerProvider);
    final c = st.catalogo!;
    final p = st.pedido;
    final storeId = ref.watch(currentStoreIdProvider) ?? 0;
    final max = (c.limites['maxIdsPorFiltro'] ?? 50).toInt();

    return Scaffold(
      appBar: AppBar(title: const Text('Más filtros')),
      body: ListView(padding: const EdgeInsets.all(14), children: [
        for (final f in c.filtros.where((f) => f.id != 'sucursales'))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _FiltroFila(filtro: f, storeId: storeId, max: max, elegidos: p.filters[f.id] ?? const []),
          ),
        const SizedBox(height: 8),
        const Text('El servidor vuelve a revisar cada valor: sólo cuentan los de tu local.',
            style: TextStyle(fontSize: 11, color: AppColors.dim)),
      ]),
    );
  }
}

class _FiltroFila extends ConsumerWidget {
  final FiltroCatalogo filtro;
  final int storeId;
  final int max;
  final List<int> elegidos;
  const _FiltroFila({required this.filtro, required this.storeId, required this.max, required this.elegidos});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valores = ref.watch(rmValoresFiltroProvider((filtro.id, storeId)));
    final lista = valores.valueOrNull ?? const <(int, String)>[];
    final nombres = lista.where((v) => elegidos.contains(v.$1)).map((v) => v.$2).toList();

    return RmCampo(
      label: filtro.labelEs,
      valor: valores.isLoading
          ? 'Cargando…'
          : (elegidos.isEmpty ? 'Todos' : (nombres.isEmpty ? '${elegidos.length} elegidos' : nombres.join(', '))),
      onTap: () async {
        if (lista.isEmpty) return;
        final res = await showModalBottomSheet<List<int>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: AppColors.panel,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
          builder: (_) => _MultiSelect(titulo: filtro.labelEs, opciones: lista, iniciales: elegidos, max: max),
        );
        if (res == null) return;
        final st = ref.read(rmControllerProvider);
        final f = {...st.pedido.filters};
        if (res.isEmpty) {
          f.remove(filtro.id);
        } else {
          f[filtro.id] = res;
        }
        ref.read(rmControllerProvider.notifier).cambiar(st.pedido.copyWith(filters: f));
      },
    );
  }
}

class _MultiSelect extends StatefulWidget {
  final String titulo;
  final List<(int, String)> opciones;
  final List<int> iniciales;
  final int max;
  const _MultiSelect({required this.titulo, required this.opciones, required this.iniciales, required this.max});

  @override
  State<_MultiSelect> createState() => _MultiSelectState();
}

class _MultiSelectState extends State<_MultiSelect> {
  late final Set<int> _sel = widget.iniciales.toSet();
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final vis = widget.opciones.where((o) => o.$2.toLowerCase().contains(_q.toLowerCase())).toList();

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
            child: Row(children: [
              Expanded(child: Text(widget.titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
              TextButton(onPressed: () => setState(_sel.clear), child: const Text('Limpiar')),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          if (_sel.length >= widget.max)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Máximo ${widget.max} valores.', style: const TextStyle(fontSize: 12, color: rmCerca)),
            ),
          Expanded(
            child: ListView(children: [
              for (final o in vis)
                CheckboxListTile(
                  value: _sel.contains(o.$1),
                  title: Text(o.$2),
                  activeColor: AppColors.gold,
                  onChanged: (v) => setState(() {
                    if (v == true && _sel.length < widget.max) _sel.add(o.$1);
                    if (v == false) _sel.remove(o.$1);
                  }),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(context, _sel.toList()),
              child: Text(_sel.isEmpty ? 'Usar todos' : 'Aplicar (${_sel.length})'),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Paso 4 ──
class PasoComparacion extends ConsumerWidget {
  const PasoComparacion({super.key});

  static const _opciones = [
    (null, 'Sin comparar'),
    ('periodo_anterior', 'Período anterior'),
    ('anio_anterior', 'Mismo período del año anterior'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(rmControllerProvider);
    final c = st.catalogo!;
    final p = st.pedido;
    final ctrl = ref.read(rmControllerProvider.notifier);

    String? explicacion() {
      if (p.compare == null) return null;
      try {
        final hoy = hoyDeCatalogo(c.zonaHoraria);
        final r = resolverPeriodo(p.period, hoy);
        final alin = alineacion(p.period, p.groupBy);
        final comp = comparacionLocal(r.desde, r.hasta, p.compare!, alin);
        final como = alin == 'semanal'
            ? (p.compare == 'anio_anterior'
                ? '52 semanas antes, mismos días de la semana'
                : 'mismos días de la semana, para que un sábado se compare con un sábado')
            : (p.compare == 'anio_anterior' ? 'mismas fechas del año anterior' : 'mismas fechas del mes');

        return 'Contra el ${fRangoFechas(comp.desde, comp.hasta)} ($como). '
            'Con inflación los pesos solos engañan: se agregan Unidades, Tickets y Precio por unidad (marcados con «+» en el paso 1).';
      } catch (_) {
        return null;
      }
    }

    final exp = explicacion();

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (id, label) in _opciones)
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => ctrl.cambiar(p.copyWith(compare: id)),
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: p.compare == id ? AppColors.gold.withValues(alpha: 0.14) : AppColors.navy2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: p.compare == id ? AppColors.gold : AppColors.line),
              ),
              child: Text('${p.compare == id ? '✓ ' : ''}$label',
                  style: TextStyle(
                      fontSize: 14,
                      color: p.compare == id ? AppColors.gold : AppColors.txt,
                      fontWeight: p.compare == id ? FontWeight.w700 : FontWeight.w400)),
            ),
          ),
        ),
      if (exp != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(exp, style: const TextStyle(fontSize: 12, color: AppColors.dim, height: 1.45)),
        ),
    ]);
  }
}
