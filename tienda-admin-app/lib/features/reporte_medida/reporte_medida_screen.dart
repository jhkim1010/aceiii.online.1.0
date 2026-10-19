// Reporte a medida — constructor (tipo, plantillas, 4 pasos, barra «Tu reporte»).
// Mismo flujo que la web (mockup 2026-10-18 aprobado); los pasos se pliegan en vertical.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../reportes/reporte_detalle_screen.dart';
import 'rm_controller.dart';
import 'rm_guardados.dart';
import 'rm_logica.dart';
import 'rm_modelos.dart';
import 'rm_pasos.dart';
import 'rm_periodo.dart';
import 'rm_repository.dart';
import 'rm_resultado_screen.dart';
import 'rm_widgets.dart';

class ReporteMedidaScreen extends ConsumerStatefulWidget {
  // Si viene, se abre y ejecuta ese reporte guardado apenas carga el catálogo.
  final int? abrirId;
  const ReporteMedidaScreen({super.key, this.abrirId});

  @override
  ConsumerState<ReporteMedidaScreen> createState() => _ReporteMedidaScreenState();
}

class _ReporteMedidaScreenState extends ConsumerState<ReporteMedidaScreen> {
  int _paso = 1;
  bool _abrioInicial = false;

  void _verResultado() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RmResultadoScreen()));
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual(rmCatalogoProvider, (_, next) {
      final c = next.valueOrNull;
      if (c == null) return;
      // Después del frame: con fireImmediately esto corre dentro de initState, y cambiar el estado
      // de un provider mientras el árbol se construye lanza — la primera validación nunca salía.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(rmControllerProvider.notifier).iniciar(c);
        if (widget.abrirId != null && !_abrioInicial) {
          _abrioInicial = true;
          _abrirGuardado(widget.abrirId!);
        }
      });
    }, fireImmediately: true);
  }

  Future<void> _abrirGuardado(int id) async {
    _verResultado();
    await ref.read(rmControllerProvider.notifier).abrirGuardado(id);
  }

  @override
  Widget build(BuildContext context) {
    final cat = ref.watch(rmCatalogoProvider);
    final guardados = ref.watch(rmGuardadosProvider).valueOrNull;


    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte a medida'),
        actions: [
          // Ícono con contador: un botón con texto cortaba el título en «Reporte a medi…».
          IconButton(
            tooltip: 'Mis reportes',
            icon: Badge(
              isLabelVisible: (guardados?.length ?? 0) > 0,
              label: Text('${guardados?.length ?? 0}'),
              backgroundColor: AppColors.gold,
              textColor: AppColors.navy,
              child: const Icon(Icons.bookmarks_outlined, color: AppColors.gold),
            ),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MisReportesScreen(onAbrir: (id) {
                      Navigator.of(context).pop();
                      _abrirGuardado(id);
                    }))),
          ),
        ],
      ),
      body: cat.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorCatalogo(error: clasificarError(e), onReintentar: () => ref.invalidate(rmCatalogoProvider)),
        data: (_) => _cuerpo(),
      ),
      bottomNavigationBar: cat.hasValue ? _BarraTuReporte(onVer: _verResultado) : null,
    );
  }

  Widget _cuerpo() {
    final st = ref.watch(rmControllerProvider);
    final c = st.catalogo;
    if (c == null) return const Center(child: CircularProgressIndicator());
    final p = st.pedido;
    final ctrl = ref.read(rmControllerProvider.notifier);

    String resumenPeriodo() {
      final pre = p.preset;
      if (pre != null) return c.presetsPeriodo.where((x) => x.id == pre).firstOrNull?.labelEs ?? pre;

      return 'Rango de fechas';
    }

    String resumenPaso3() {
      final suc = p.filters['sucursales']?.isNotEmpty == true ? 'una sucursal' : 'todas las sucursales';
      final otros = p.filters.entries.where((e) => e.key != 'sucursales' && e.value.isNotEmpty).length;

      return [suc, if (otros > 0) '$otros ${otros == 1 ? 'filtro' : 'filtros'}', p.top == null ? 'todas las filas' : 'Top ${p.top}']
          .join(' · ');
    }

    void toggle(int n) => setState(() => _paso = _paso == n ? 0 : n);

    return ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
      const Text('Armá tu propio reporte eligiendo de una lista, dentro de los límites del local.',
          style: TextStyle(fontSize: 12, color: AppColors.dim)),
      if (st.abierto != null) ...[const SizedBox(height: 12), const FranjaGuardado()],
      if (st.avisoEs != null) ...[const SizedBox(height: 12), RmAviso(st.avisoEs!, icono: Icons.info_outline)],
      const SizedBox(height: 14),
      _TipoDatos(catalogo: c),
      const SizedBox(height: 14),
      _Plantillas(
        catalogo: c,
        onElegir: (t) {
          if (t.enlaceLabelEs != null) {
            Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ReporteDetalleScreen(kind: ReportKind.stocks)));

            return;
          }
          ctrl.aplicarPlantilla(t);
          _verResultado();
        },
      ),
      const SizedBox(height: 14),
      RmPasoCard(
        numero: 1,
        titulo: '¿Qué querés ver?',
        cap: 'Hasta 4 medidas',
        resumen: p.metrics.isEmpty
            ? 'Elegí al menos una medida'
            : '${p.metrics.map(c.labelMetrica).join(', ')} · ${resumenPeriodo()}',
        abierto: _paso == 1,
        onToggle: () => toggle(1),
        child: const PasoMetricas(),
      ),
      const SizedBox(height: 10),
      RmPasoCard(
        numero: 2,
        titulo: '¿Cómo lo separamos?',
        cap: 'Hasta 2 clasificaciones',
        resumen: p.groupBy.isEmpty ? 'Total del local' : 'por ${p.groupBy.map((d) => c.labelDimension(d)).join(' y ')}',
        abierto: _paso == 2,
        onToggle: () => toggle(2),
        child: const PasoAgrupaciones(),
      ),
      const SizedBox(height: 10),
      RmPasoCard(
        numero: 3,
        titulo: 'Filtros y orden',
        cap: 'Sucursal, filtros, orden y filas',
        resumen: resumenPaso3(),
        abierto: _paso == 3,
        onToggle: () => toggle(3),
        child: const PasoPeriodo(),
      ),
      const SizedBox(height: 10),
      RmPasoCard(
        numero: 4,
        titulo: '¿Comparar?',
        cap: 'Contra otro período',
        resumen: switch (p.compare) {
          'periodo_anterior' => 'Período anterior',
          'anio_anterior' => 'Mismo período del año anterior',
          _ => 'Sin comparar',
        },
        abierto: _paso == 4,
        onToggle: () => toggle(4),
        child: const PasoComparacion(),
      ),
    ]);
  }
}

class _ErrorCatalogo extends StatelessWidget {
  final ErrorRm error;
  final VoidCallback onReintentar;
  const _ErrorCatalogo({required this.error, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    final permiso = error.tipo == TipoErrorRm.permiso;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(permiso ? Icons.lock_outline : Icons.cloud_off, size: 40, color: AppColors.dim),
          const SizedBox(height: 12),
          Text(error.mensajeEs, textAlign: TextAlign.center),
          if (!permiso) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onReintentar, child: const Text('Reintentar')),
          ],
        ]),
      ),
    );
  }
}

class _TipoDatos extends StatelessWidget {
  final Catalogo catalogo;
  const _TipoDatos({required this.catalogo});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('¿Con qué datos armás el reporte?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in catalogo.tiposReporte)
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: t.disponible
                ? null
                : () => ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(t.motivoEs ?? 'Próximamente.'), behavior: SnackBarBehavior.floating)),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: t.disponible ? AppColors.gold.withValues(alpha: 0.14) : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.disponible ? AppColors.gold : AppColors.line),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(t.disponible ? '✓ ${t.labelEs}' : t.labelEs,
                    style: TextStyle(
                        fontSize: 13,
                        color: t.disponible ? AppColors.gold : rmOff,
                        fontWeight: t.disponible ? FontWeight.w700 : FontWeight.w400)),
                // «pronto» dentro del chip: en la web suelto quedaba como una línea huérfana.
                if (!t.disponible) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(4)),
                    child: const Text('pronto', style: TextStyle(fontSize: 10, color: rmOff)),
                  ),
                ],
              ]),
            ),
          ),
      ]),
    ]);
  }
}

class _Plantillas extends StatelessWidget {
  final Catalogo catalogo;
  final void Function(PlantillaCatalogo) onElegir;
  const _Plantillas({required this.catalogo, required this.onElegir});

  @override
  Widget build(BuildContext context) {
    final ts = catalogo.plantillas;
    if (ts.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Row(children: [
        Expanded(child: Text('Empezar desde una plantilla', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
        Text('deslizá ›', style: TextStyle(fontSize: 11, color: AppColors.dim)),
      ]),
      const SizedBox(height: 8),
      SizedBox(
        height: 96,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: ts.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final t = ts[i];

            return Opacity(
              opacity: t.disponible ? 1 : 0.45,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: t.disponible
                    ? () => onElegir(t)
                    : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(t.motivoEs ?? 'No disponible en esta tienda'), behavior: SnackBarBehavior.floating)),
                child: Container(
                  width: 156,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.panel,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.enlaceLabelEs != null ? AppColors.dim : AppColors.line),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t.enlaceLabelEs != null ? '${t.labelEs} ↗' : t.labelEs,
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(t.disponible ? t.descripcionEs : 'No disponible en esta tienda',
                        maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.dim)),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

// Barra fija «Tu reporte»: resumen, validación con arreglos, Guardar… y Ver reporte.
class _BarraTuReporte extends ConsumerWidget {
  final VoidCallback onVer;
  const _BarraTuReporte({required this.onVer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(rmControllerProvider);
    final c = st.catalogo;
    if (c == null) return const SizedBox.shrink();
    final v = st.validacion;
    final ctrl = ref.read(rmControllerProvider.notifier);
    final segs = resumenLocal(c, st.pedido, hoyDeCatalogo(c.zonaHoraria));

    final (String meta, Color colorMeta) = st.hayErrores
        ? ('Corregí lo marcado para poder ejecutar', rmErrorTxt)
        : v.pendiente
            ? ('Revisando…', AppColors.dim)
            : ('Filas: ${v.filasEstimadas ?? '—'} · listo para ejecutar', rmOk);

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: Color(0x59F5A623))),
        boxShadow: [BoxShadow(color: Color(0x73000000), blurRadius: 20, offset: Offset(0, -8))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text.rich(
              TextSpan(children: [
                for (final (t, b) in segs) TextSpan(text: t, style: TextStyle(fontWeight: b ? FontWeight.w700 : FontWeight.w400)),
              ]),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            if (v.errores.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 180),
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    for (final e in v.errores)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: const Color(0x24EF4444), borderRadius: BorderRadius.circular(8)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.messageEs, style: const TextStyle(fontSize: 13, color: rmErrorTxt)),
                          if (e.fixes.any((f) => f.patch != null)) ...[
                            const SizedBox(height: 8),
                            Wrap(spacing: 8, runSpacing: 6, children: [
                              for (final f in e.fixes.where((f) => f.patch != null))
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFFFD0CC),
                                      side: const BorderSide(color: rmErrorTxt),
                                      visualDensity: VisualDensity.compact),
                                  onPressed: () => ctrl.aplicarFix(f),
                                  child: Text(f.labelEs, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                ),
                            ]),
                          ],
                        ]),
                      ),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Text(meta, style: rmMono.copyWith(fontSize: 12, color: colorMeta)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      foregroundColor: AppColors.gold,
                      side: BorderSide(color: st.hayErrores ? AppColors.line : AppColors.gold)),
                  onPressed: st.hayErrores || st.pedido.metrics.isEmpty ? null : () => mostrarGuardar(context, ref),
                  child: const Text('Guardar…', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: st.puedeEjecutar
                      ? () {
                          ctrl.ejecutar();
                          onVer();
                        }
                      : null,
                  child: st.ejecutando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Ver reporte', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            const Text('Se ejecuta con tus permisos y sólo con datos de tu local. Tiempo máximo 5 s.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: AppColors.dim)),
          ]),
        ),
      ),
    );
  }
}
