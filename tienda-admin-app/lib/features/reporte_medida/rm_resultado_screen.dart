// Reporte a medida — resultado: titular de comparación, totales, gráfico, tabla y CSV.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import 'rm_controller.dart';
import 'rm_formato.dart';
import 'rm_guardados.dart';
import 'rm_modelos.dart';
import 'rm_repository.dart';
import 'rm_resultado_vista.dart';
import 'rm_widgets.dart';

const _paleta = [Color(0xFFF5A623), Color(0xFF60A5FA), Color(0xFF4ADE80), Color(0xFFF472B6), Color(0xFFA78BFA)];

class RmResultadoScreen extends ConsumerStatefulWidget {
  const RmResultadoScreen({super.key});

  @override
  ConsumerState<RmResultadoScreen> createState() => _RmResultadoScreenState();
}

class _RmResultadoScreenState extends ConsumerState<RmResultadoScreen> {
  bool _compartiendo = false;

  Future<void> _compartirCsv() async {
    if (_compartiendo) return;
    setState(() => _compartiendo = true);
    try {
      final csv = await ref.read(rmControllerProvider.notifier).csv();
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(csv.bytes, mimeType: 'text/csv', name: csv.nombre)],
        fileNameOverrides: [csv.nombre],
      ));
    } catch (e) {
      final err = clasificarError(e);
      if (!mounted) return;
      final extra = err.fixesCsv.isEmpty ? '' : ' (${err.fixesCsv.join(' · ')})';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${err.mensajeEs}$extra'), backgroundColor: const Color(0xFFE24B4A), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _compartiendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(rmControllerProvider);
    final r = st.resultado;
    final ctrl = ref.read(rmControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado'),
        actions: [
          IconButton(
            tooltip: 'Compartir CSV',
            icon: _compartiendo
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share, color: AppColors.gold),
            onPressed: st.vigente && !st.ejecutando ? _compartirCsv : null,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: ctrl.ejecutar,
        child: ListView(padding: const EdgeInsets.fromLTRB(14, 12, 14, 24), children: [
          if (st.abierto != null) ...[const FranjaGuardado(), const SizedBox(height: 12)],
          if (st.error != null) ...[
            _ErrorResultado(error: st.error!, onReintentar: ctrl.ejecutar, onFix: ctrl.aplicarFix),
            const SizedBox(height: 12),
          ],
          if (st.ejecutando && r == null)
            const _Cargando()
          else if (r == null && st.error == null)
            const _Vacio(
                titulo: 'Todavía no hay resultado', cuerpo: 'Elegí qué ver y tocá Ver reporte. El resultado aparece acá.')
          else if (r != null)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: st.vigente && !st.ejecutando ? 1 : 0.45,
              child: _Contenido(resultado: r, pedido: st.pedido, avisoMargen: st.avisoMargen, obsoleto: !st.vigente),
            ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: const BoxDecoration(color: AppColors.panel, border: Border(top: BorderSide(color: AppColors.line))),
          child: Row(children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    foregroundColor: AppColors.txt,
                    side: const BorderSide(color: AppColors.line)),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cambiar el reporte'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: st.vigente || st.resultado == null
                  ? OutlinedButton(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          foregroundColor: AppColors.gold,
                          side: const BorderSide(color: AppColors.gold)),
                      onPressed: st.vigente && !st.ejecutando ? _compartirCsv : null,
                      child: const Text('Compartir CSV', style: TextStyle(fontWeight: FontWeight.w700)),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: st.puedeEjecutar ? ctrl.ejecutar : null,
                      child: const Text('Ver reporte', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      const SizedBox(height: 24),
      const CircularProgressIndicator(),
      const SizedBox(height: 12),
      const Text('Ejecutando…', style: TextStyle(color: AppColors.dim)),
      const SizedBox(height: 24),
      for (var i = 0; i < 6; i++)
        Container(
          height: 30,
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(color: AppColors.panel, borderRadius: BorderRadius.circular(4)),
        ),
    ]);
  }
}

class _Vacio extends StatelessWidget {
  final String titulo;
  final String cuerpo;
  const _Vacio({required this.titulo, required this.cuerpo});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(children: [
        Text(titulo, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(cuerpo, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.dim)),
      ]),
    );
  }
}

class _ErrorResultado extends StatelessWidget {
  final ErrorRm error;
  final Future<void> Function() onReintentar;
  final void Function(FixPedido) onFix;
  const _ErrorResultado({required this.error, required this.onReintentar, required this.onFix});

  @override
  Widget build(BuildContext context) {
    final fixes = error.errores.expand((e) => e.fixes).where((f) => f.patch != null).toList();
    final reintentable = error.tipo == TipoErrorRm.timeout || error.tipo == TipoErrorRm.servidor || error.tipo == TipoErrorRm.red;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0x24EF4444), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(error.mensajeEs, style: const TextStyle(color: rmErrorTxt)),
        if (fixes.isNotEmpty || reintentable) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 6, children: [
            for (final f in fixes) OutlinedButton(onPressed: () => onFix(f), child: Text(f.labelEs)),
            if (reintentable) OutlinedButton(onPressed: onReintentar, child: const Text('Reintentar')),
          ]),
        ],
      ]),
    );
  }
}

class _Contenido extends StatefulWidget {
  final ResultadoReporte resultado;
  final Pedido pedido;
  final bool avisoMargen;
  final bool obsoleto;
  const _Contenido({required this.resultado, required this.pedido, required this.avisoMargen, required this.obsoleto});

  @override
  State<_Contenido> createState() => _ContenidoState();
}

class _ContenidoState extends State<_Contenido> {
  String? _metrica;
  int _mostradas = tamPagina;

  @override
  Widget build(BuildContext context) {
    final r = widget.resultado;
    final p = widget.pedido;
    final cols = columnasVista(r, p);
    final dims = r.columnas.where((c) => c.tipo == 'dimension').map((c) => c.id).toList();
    final filas = filasVista(r.filas, dims);
    final metricas = metricasDelGrafico(r, p);
    final activa = metricas.any((m) => m.id == _metrica) ? _metrica! : (metricas.firstOrNull?.id ?? '');
    final grafico = activa.isEmpty ? null : seriesGrafico(r, p, activa);
    final titular = titularComparacion(r);
    final avisos = avisosResultado(r, p, widget.avisoMargen);
    final notas = notasAlPie(r, cols);

    if (r.filas.isEmpty) {
      return const _Vacio(
          titulo: 'No hay ventas en este período con estos filtros', cuerpo: 'Probá con otro período o quitá algún filtro.');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.obsoleto) ...[
        const RmAviso.dorado('El reporte cambió — tocá «Ver reporte» otra vez.'),
        const SizedBox(height: 10),
      ],
      Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
        _Pastilla('${fFechaCorta(r.meta.desde)} – ${fFechaCorta(r.meta.hasta)} · ${fEntero(r.meta.filas)} filas'),
        if (r.comparacion != null)
          Text('vs ${fFechaCorta(r.comparacion!.desde)} – ${fFechaCorta(r.comparacion!.hasta)}',
              style: const TextStyle(fontSize: 11, color: AppColors.dim)),
        if (r.meta.truncado) const _Pastilla('mostrando las primeras 1.000 filas — el CSV trae todas', dorado: true),
      ]),
      if (titular != null) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.navy2, borderRadius: BorderRadius.circular(10)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(
              TextSpan(children: [
                const TextSpan(text: 'Total del período: '),
                for (var i = 0; i < titular.partes.length; i++) ...[
                  if (i > 0) const TextSpan(text: ' · '),
                  TextSpan(text: '${titular.partes[i].label} ', style: TextStyle(fontWeight: i == 0 ? FontWeight.w700 : null)),
                  TextSpan(
                      text: titular.partes[i].texto,
                      style: TextStyle(color: colorSigno(titular.partes[i].signo), fontWeight: FontWeight.w700)),
                ],
                if (titular.sufijoHasta != null) TextSpan(text: ' ${titular.sufijoHasta}'),
              ]),
              style: const TextStyle(fontSize: 14, height: 1.45),
            ),
            Text(titular.notaParcial ?? 'Mirá el total; día por día la variación es más ruidosa.',
                style: const TextStyle(fontSize: 11, color: AppColors.dim)),
          ]),
        ),
      ],
      const SizedBox(height: 10),
      _Totales(resultado: r, cols: cols),
      for (final a in avisos) ...[
        const SizedBox(height: 8),
        a.startsWith('Sólo el') ? RmAviso.dorado(a) : RmAviso(a, icono: Icons.info_outline),
      ],
      if (grafico != null) ...[
        const SizedBox(height: 12),
        _Grafico(
          vista: grafico,
          metricas: metricas,
          activa: activa,
          onMetrica: (id) => setState(() => _metrica = id),
        ),
      ],
      const SizedBox(height: 12),
      _Tabla(cols: cols, filas: filas.take(_mostradas).toList(), total: filaTotal(r, cols)),
      if (filas.length > _mostradas)
        TextButton(
          onPressed: () => setState(() => _mostradas += tamPagina),
          child: Text('Ver más filas (${fEntero(_mostradas)} de ${fEntero(filas.length)})'),
        )
      else if (filas.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('Deslizá la tabla › · ${fEntero(filas.length)} filas',
              style: const TextStyle(fontSize: 11, color: AppColors.dim)),
        ),
      const SizedBox(height: 8),
      for (final n in notas)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(n, style: const TextStyle(fontSize: 11, color: AppColors.dim, height: 1.4)),
        ),
      if (r.meta.definicionVentaEs.isNotEmpty)
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('¿Cómo se calcula la venta?', style: TextStyle(fontSize: 12, color: AppColors.dim)),
            children: [
              Text(r.meta.definicionVentaEs, style: const TextStyle(fontSize: 12, color: AppColors.dim, height: 1.4)),
            ],
          ),
        ),
    ]);
  }
}

class _Pastilla extends StatelessWidget {
  final String texto;
  final bool dorado;
  const _Pastilla(this.texto, {this.dorado = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: dorado ? AppColors.gold.withValues(alpha: 0.12) : AppColors.navy2,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(texto, style: rmMono.copyWith(fontSize: 11, color: dorado ? AppColors.gold : AppColors.dim)),
    );
  }
}

// Totales en tarjetas (hasta 3 métricas, la fila Total de la tabla trae todas).
class _Totales extends StatelessWidget {
  final ResultadoReporte resultado;
  final List<ColumnaVista> cols;
  const _Totales({required this.resultado, required this.cols});

  @override
  Widget build(BuildContext context) {
    final mets = cols.where((c) => !c.esDimension && !c.esVariacion).take(3).toList();

    return Row(children: [
      for (var i = 0; i < mets.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: AppColors.panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppColors.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(mets[i].header, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.dim)),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(fValor(resultado.totales[mets[i].id], mets[i].formato),
                    style: rmMono.copyWith(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _Grafico extends StatelessWidget {
  final GraficoVista vista;
  final List<ColumnaDef> metricas;
  final String activa;
  final void Function(String) onMetrica;
  const _Grafico({required this.vista, required this.metricas, required this.activa, required this.onMetrica});

  String _rotulo(String s) {
    // Barras: sólo el primer término (el código del producto) — el nombre completo está en la tabla.
    final corto = vista.barras ? s.split(' ').first : s;
    final max = vista.barras ? 6 : 10;

    return corto.length > max ? '${corto.substring(0, max - 1)}…' : corto;
  }

  @override
  Widget build(BuildContext context) {
    final cats = vista.categorias;
    final n = cats.length;
    final paso = vista.barras ? (n <= 5 ? 1 : 2) : (n <= 6 ? 1 : (n / 5).ceil());
    final valores = vista.series.expand((s) => s.data).whereType<double>();
    final maxY = valores.isEmpty ? 1.0 : valores.reduce((a, b) => a > b ? a : b);
    final minY = valores.isEmpty ? 0.0 : valores.reduce((a, b) => a < b ? a : b);

    Widget ejeX(double v, TitleMeta meta) {
      final i = v.round();
      if (i < 0 || i >= n || (i % paso != 0 && i != n - 1)) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(_rotulo(cats[i]), style: rmMono.copyWith(fontSize: 9, color: AppColors.dim)),
      );
    }

    Widget ejeY(double v, TitleMeta meta) {
      if (v == meta.max || v == meta.min && v != 0) return const SizedBox.shrink();

      return Text(fEjeCorto(v, vista.formato), style: rmMono.copyWith(fontSize: 9, color: AppColors.dim));
    }

    final titulos = FlTitlesData(
      topTitles: const AxisTitles(),
      rightTitles: const AxisTitles(),
      bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 22, interval: 1, getTitlesWidget: ejeX)),
      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 56, getTitlesWidget: ejeY)),
    );
    final grilla = FlGridData(
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.line, strokeWidth: 1),
    );

    final Widget chart;
    if (vista.barras) {
      chart = BarChart(BarChartData(
        maxY: maxY * 1.1,
        minY: minY < 0 ? minY * 1.1 : 0,
        gridData: grilla,
        borderData: FlBorderData(show: false),
        titlesData: titulos,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.navy,
            getTooltipItem: (g, _, rod, _) => BarTooltipItem(
                '${cats[g.x]}\n${fValor(rod.toY, vista.formato)}', rmMono.copyWith(fontSize: 11, color: AppColors.txt)),
          ),
        ),
        barGroups: [
          for (var i = 0; i < n; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(
                  toY: vista.series.first.data[i] ?? 0,
                  color: AppColors.gold,
                  width: 14,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
            ]),
        ],
      ));
    } else {
      final parciales = vista.parcialesIdx.toSet();
      var color = 0;
      chart = LineChart(LineChartData(
        minY: minY < 0 ? minY * 1.1 : 0,
        maxY: maxY * 1.1,
        gridData: grilla,
        borderData: FlBorderData(show: false),
        titlesData: titulos,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.navy,
            fitInsideHorizontally: true,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.barIndex == 0 ? '${cats[s.x.round()]}\n' : ''}${vista.series[s.barIndex].nombre}: ${fValor(s.y, vista.formato)}',
                  rmMono.copyWith(fontSize: 11, color: s.bar.color ?? AppColors.txt),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final s in vista.series)
            () {
              final c = s.comparacion ? const Color(0xFFA3A3BD) : _paleta[color++ % _paleta.length];

              return LineChartBarData(
                spots: [
                  for (var i = 0; i < s.data.length; i++)
                    if (s.data[i] != null) FlSpot(i.toDouble(), s.data[i]!) else FlSpot.nullSpot,
                ],
                color: c,
                barWidth: s.comparacion ? 1.5 : 2.5,
                dashArray: s.comparacion ? [4, 4] : null,
                isCurved: false,
                dotData: FlDotData(
                  show: !s.comparacion,
                  checkToShowDot: (spot, _) => parciales.contains(spot.x.round()) || n <= 12,
                  getDotPainter: (spot, _, _, _) => parciales.contains(spot.x.round())
                      ? FlDotCirclePainter(radius: 4, color: AppColors.navy2, strokeColor: c, strokeWidth: 2)
                      : FlDotCirclePainter(radius: 2.5, color: c, strokeWidth: 0),
                ),
              );
            }(),
        ],
      ));
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 12, 8),
      decoration: BoxDecoration(
          color: AppColors.navy2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (metricas.length > 1)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final m in metricas)
                Padding(
                  padding: const EdgeInsets.only(right: 6, left: 2),
                  child: ChoiceChip(
                    label: Text(m.labelEs, style: const TextStyle(fontSize: 12)),
                    selected: m.id == activa,
                    showCheckmark: false,
                    selectedColor: AppColors.gold.withValues(alpha: 0.14),
                    side: BorderSide(color: m.id == activa ? AppColors.gold : AppColors.line),
                    labelStyle: TextStyle(color: m.id == activa ? AppColors.gold : AppColors.dim),
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => onMetrica(m.id),
                  ),
                ),
            ]),
          ),
        const SizedBox(height: 8),
        SizedBox(height: 190, child: chart),
        if (!vista.barras && vista.series.length > 1 && !vista.series.any((s) => s.comparacion))
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Wrap(spacing: 10, runSpacing: 4, children: [
              for (var i = 0; i < vista.series.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: 3, color: _paleta[i % _paleta.length]),
                  const SizedBox(width: 4),
                  Text(vista.series[i].nombre, style: const TextStyle(fontSize: 11, color: AppColors.dim)),
                ]),
            ]),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4),
          child: Text(
            [
              if (vista.series.any((s) => s.comparacion)) 'Línea gris punteada = período comparado.',
              if (vista.parcialesIdx.isNotEmpty) 'Punto hueco = período en curso (parcial), no es una caída ni una suba real.',
              if (vista.recortado) vista.barras ? 'Se muestran los 10 primeros; el resto está en la tabla.' : 'Se muestran las 5 primeras; el resto está en la tabla.',
            ].join(' '),
            style: const TextStyle(fontSize: 11, color: AppColors.dim, height: 1.4),
          ),
        ),
      ]),
    );
  }
}

// Tabla: primera columna fija, el resto se desliza en horizontal. Filas de 30 px como la web.
class _Tabla extends StatelessWidget {
  final List<ColumnaVista> cols;
  final List<Fila> filas;
  final Fila total;
  const _Tabla({required this.cols, required this.filas, required this.total});

  static const _alto = 30.0;

  Widget _celda(Fila f, ColumnaVista c, {bool negrita = false}) {
    String texto;
    Color color = AppColors.txt;
    if (c.esVariacion) {
      final v = f['__total'] == true ? (texto: fVariacion(f[c.id]).texto, signo: fVariacion(f[c.id]).signo) : celdaVariacion(f, c.id);
      texto = v.texto;
      color = v.signo == null ? AppColors.dim : colorSigno(v.signo);
    } else {
      texto = fValor(f[c.id], c.formato);
    }

    return Container(
      height: _alto,
      alignment: c.esDimension ? Alignment.centerLeft : Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Text(texto,
          maxLines: 1,
          style: (c.esDimension ? const TextStyle() : rmMono)
              .copyWith(fontSize: 12, color: color, fontWeight: negrita ? FontWeight.w700 : FontWeight.w400)),
    );
  }

  Widget _celdaDim(Fila f, ColumnaVista c, {bool negrita = false}) {
    final parcial = f['parcial'] == true && f['__total'] != true;

    return Container(
      height: _alto,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text(fValor(f[c.id], 'texto'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, fontWeight: negrita ? FontWeight.w700 : FontWeight.w400)),
        ),
        if (parcial) ...[
          const SizedBox(width: 4),
          const Text('parcial', style: TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fija = cols.first;
    final resto = cols.skip(1).toList();
    final todas = [...filas, total];

    // Ancho fijo por columna (las filas son Rows independientes: sin esto no alinean).
    final anchos = {
      for (final c in resto)
        c.id: () {
          var largo = c.header.length;
          for (final f in todas) {
            final t = c.esVariacion ? 12 : fValor(f[c.id], c.formato).length;
            if (t > largo) largo = t;
          }

          return (largo * 7.4 + 22).clamp(80.0, 220.0);
        }(),
    };

    BoxDecoration deco(int i) {
      final esTotal = i == todas.length - 1;

      return BoxDecoration(
        color: esTotal ? AppColors.navy2 : null,
        border: Border(top: BorderSide(color: esTotal ? AppColors.gold : AppColors.line, width: esTotal ? 2 : 1)),
      );
    }

    Widget encabezado(ColumnaVista c) => Container(
          height: _alto,
          alignment: c.esDimension ? Alignment.centerLeft : Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text(c.header,
              style: TextStyle(
                  fontSize: 12,
                  color: AppColors.dim,
                  fontWeight: FontWeight.w700,
                  fontStyle: c.auto ? FontStyle.italic : FontStyle.normal)),
        );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 140, minWidth: 90),
          child: IntrinsicWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(color: AppColors.navy2, child: encabezado(fija)),
              for (var i = 0; i < todas.length; i++)
                Container(
                    decoration: deco(i),
                    child: _celdaDim(todas[i], fija, negrita: i == todas.length - 1)),
            ]),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: IntrinsicWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(
                  color: AppColors.navy2,
                  child: Row(children: [for (final c in resto) SizedBox(width: anchos[c.id], child: encabezado(c))]),
                ),
                for (var i = 0; i < todas.length; i++)
                  Container(
                    decoration: deco(i),
                    child: Row(children: [
                      for (final c in resto)
                        SizedBox(
                          width: anchos[c.id],
                          child: c.esDimension
                              ? _celdaDim(todas[i], c, negrita: i == todas.length - 1)
                              : _celda(todas[i], c, negrita: i == todas.length - 1),
                        ),
                    ]),
                  ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
