// Reporte a medida — pestaña «Gráficos»: la medida elegida en TODAS sus formas a la vez
// (port de resultado/GraficosVista.tsx + GraficoResultado.tsx, pedido 2026-10-19).
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'rm_formato.dart';
import 'rm_modelos.dart';
import 'rm_resultado_vista.dart';
import 'rm_widgets.dart';

const _paleta = [Color(0xFFF5A623), Color(0xFF60A5FA), Color(0xFF4ADE80), Color(0xFFF472B6), Color(0xFFA78BFA)];
const _paletaTorta = [
  Color(0xFFF5A623), Color(0xFF60A5FA), Color(0xFF4ADE80), Color(0xFFF472B6), Color(0xFFA78BFA),
  Color(0xFF22D3EE), Color(0xFFFB923C), Color(0xFFA3E635), Color(0xFFE879F9),
];
const _gris = Color(0xFFA3A3BD);

// Color de cada serie: la comparación siempre en gris, el resto con la paleta en orden.
List<Color> _coloresSeries(GraficoVista v) {
  var i = 0;

  return [for (final s in v.series) s.comparacion ? _gris : _paleta[i++ % _paleta.length]];
}

class RmGraficosTab extends StatefulWidget {
  final ResultadoReporte resultado;
  final Pedido pedido;
  const RmGraficosTab({super.key, required this.resultado, required this.pedido});

  @override
  State<RmGraficosTab> createState() => _RmGraficosTabState();
}

class _RmGraficosTabState extends State<RmGraficosTab> {
  String? _elegida;

  @override
  Widget build(BuildContext context) {
    final r = widget.resultado;
    final p = widget.pedido;
    final metricas = metricasDelGrafico(r, p);
    final col = metricas.where((m) => m.id == _elegida).firstOrNull ?? metricas.firstOrNull;
    final vista = col == null ? null : seriesGrafico(r, p, col.id);
    final formas = vista == null ? const <FormaGrafico>[] : formasDisponibles(vista, col, r);

    if (col == null || vista == null || formas.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Este reporte no tiene gráfico: la lista muestra todo.',
            style: TextStyle(fontSize: 12, color: AppColors.dim)),
      );
    }

    final torta = formas.contains(FormaGrafico.torta) ? datosTorta(r, p, col.id) : null;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (metricas.length > 1) ...[
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final m in metricas)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(m.labelEs, style: const TextStyle(fontSize: 12)),
                  selected: m.id == col.id,
                  showCheckmark: false,
                  selectedColor: AppColors.gold.withValues(alpha: 0.14),
                  side: BorderSide(color: m.id == col.id ? AppColors.gold : AppColors.line),
                  labelStyle: TextStyle(color: m.id == col.id ? AppColors.gold : AppColors.dim),
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => setState(() => _elegida = m.id),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 10),
      ],
      for (final f in formas) ...[
        RmGraficoForma(
          vista: vista,
          forma: f,
          torta: torta,
          // Con comparación la torta/dona es sólo del período actual: el título lo dice.
          titulo: r.comparacion != null && (f == FormaGrafico.torta || f == FormaGrafico.dona)
              ? '${col.labelEs} — ${nombreForma[f]} (período ${fRangoFechas(r.meta.desde, r.meta.hasta)})'
              : '${col.labelEs} — ${nombreForma[f]}',
        ),
        const SizedBox(height: 12),
      ],
    ]);
  }
}

class RmGraficoForma extends StatelessWidget {
  final GraficoVista vista;
  final FormaGrafico forma;
  final TortaVista? torta;
  final String titulo;
  const RmGraficoForma({super.key, required this.vista, required this.forma, required this.titulo, this.torta});

  bool get _esTorta => forma == FormaGrafico.torta || forma == FormaGrafico.dona;

  @override
  Widget build(BuildContext context) {
    final colores = _coloresSeries(vista);
    final Widget cuerpo = switch (forma) {
      FormaGrafico.torta || FormaGrafico.dona => torta == null
          ? const SizedBox.shrink()
          : _Torta(torta: torta!, dona: forma == FormaGrafico.dona),
      FormaGrafico.barrasH => _BarrasH(vista: vista, colores: colores),
      FormaGrafico.barras => SizedBox(height: 200, child: _Barras(vista: vista, colores: colores)),
      FormaGrafico.lineas || FormaGrafico.area =>
        SizedBox(height: 200, child: _Lineas(vista: vista, colores: colores, area: forma == FormaGrafico.area)),
    };
    final leyenda = !_esTorta && vista.series.length > 1;
    final notas = [
      if (!_esTorta && vista.series.any((s) => s.comparacion)) 'Gris = período comparado.',
      if (!_esTorta && vista.parcialesIdx.isNotEmpty && forma != FormaGrafico.barras)
        'Punto hueco = período en curso (parcial), no es una caída ni una suba real.',
      if (!_esTorta && vista.recortado)
        vista.barras ? 'Se muestran los 10 primeros; el resto está en la tabla.' : 'Se muestran las 5 primeras; el resto está en la tabla.',
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
      decoration: BoxDecoration(
          color: AppColors.navy2, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        cuerpo,
        if (leyenda)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 2),
            child: Wrap(spacing: 12, runSpacing: 4, children: [
              for (var i = 0; i < vista.series.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 10, height: vista.series[i].comparacion ? 2 : 4, color: colores[i]),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(vista.series[i].nombre, style: const TextStyle(fontSize: 11, color: AppColors.dim)),
                  ),
                ]),
            ]),
          ),
        if (notas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 2),
            child: Text(notas.join(' '), style: const TextStyle(fontSize: 11, color: AppColors.dim, height: 1.4)),
          ),
      ]),
    );
  }
}

({double min, double max}) _rango(GraficoVista v) {
  final valores = v.series.expand((s) => s.data).whereType<double>();
  if (valores.isEmpty) return (min: 0, max: 1);
  final max = valores.reduce(math.max);
  final min = valores.reduce(math.min);

  return (min: min < 0 ? min * 1.1 : 0, max: max <= 0 ? 1 : max * 1.1);
}

FlTitlesData _titulos(GraficoVista v) {
  final cats = v.categorias;
  final n = cats.length;
  final paso = v.barras ? (n <= 5 ? 1 : 2) : (n <= 6 ? 1 : (n / 5).ceil());

  String rotulo(String s) {
    // Barras por categoría: sólo el primer término (el código del producto) — el nombre está en la tabla.
    final corto = v.barras ? s.split(' ').first : s;
    final max = v.barras ? 6 : 10;

    return corto.length > max ? '${corto.substring(0, max - 1)}…' : corto;
  }

  return FlTitlesData(
    topTitles: const AxisTitles(),
    rightTitles: const AxisTitles(),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 22,
        interval: 1,
        getTitlesWidget: (x, _) {
          final i = x.round();
          if (i < 0 || i >= n || (i % paso != 0 && i != n - 1)) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(rotulo(cats[i]), style: rmMono.copyWith(fontSize: 9, color: AppColors.dim)),
          );
        },
      ),
    ),
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 56,
        getTitlesWidget: (y, meta) {
          if (y == meta.max || y == meta.min && y != 0) return const SizedBox.shrink();

          return Text(fEjeCorto(y, v.formato), style: rmMono.copyWith(fontSize: 9, color: AppColors.dim));
        },
      ),
    ),
  );
}

final _grilla = FlGridData(
  drawVerticalLine: false,
  getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.line, strokeWidth: 1),
);

class _Barras extends StatelessWidget {
  final GraficoVista vista;
  final List<Color> colores;
  const _Barras({required this.vista, required this.colores});

  @override
  Widget build(BuildContext context) {
    final cats = vista.categorias;
    final n = cats.length;
    final k = vista.series.length;
    final rg = _rango(vista);

    return LayoutBuilder(builder: (context, box) {
      // Ancho por barra según el lugar real: con varias series por grupo no se pisan.
      final ancho = ((box.maxWidth - 60) / math.max(1, n * k) * 0.6).clamp(2.0, 14.0);

      return BarChart(BarChartData(
        maxY: rg.max,
        minY: rg.min,
        gridData: _grilla,
        borderData: FlBorderData(show: false),
        titlesData: _titulos(vista),
        alignment: BarChartAlignment.spaceAround,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.navy,
            fitInsideHorizontally: true,
            getTooltipItem: (g, _, rod, ri) => BarTooltipItem(
                '${cats[g.x]}\n${vista.series[ri].nombre}: ${fValor(rod.toY, vista.formato)}',
                rmMono.copyWith(fontSize: 11, color: AppColors.txt)),
          ),
        ),
        barGroups: [
          for (var i = 0; i < n; i++)
            BarChartGroupData(x: i, barsSpace: 2, barRods: [
              for (var s = 0; s < k; s++)
                BarChartRodData(
                  toY: vista.series[s].data[i] ?? 0,
                  color: colores[s],
                  width: ancho,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                ),
            ]),
        ],
      ));
    });
  }
}

class _Lineas extends StatelessWidget {
  final GraficoVista vista;
  final List<Color> colores;
  final bool area;
  const _Lineas({required this.vista, required this.colores, required this.area});

  @override
  Widget build(BuildContext context) {
    final cats = vista.categorias;
    final n = cats.length;
    final parciales = vista.parcialesIdx.toSet();
    final rg = _rango(vista);

    return LineChart(LineChartData(
      minY: rg.min,
      maxY: rg.max,
      gridData: _grilla,
      borderData: FlBorderData(show: false),
      titlesData: _titulos(vista),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipColor: (_) => AppColors.navy,
          fitInsideHorizontally: true,
          getTooltipItems: (spots) => [
            for (final s in spots)
              LineTooltipItem(
                '${s == spots.first ? '${cats[s.x.round()]}\n' : ''}${vista.series[s.barIndex].nombre}: ${fValor(s.y, vista.formato)}',
                rmMono.copyWith(fontSize: 11, color: s.bar.color ?? AppColors.txt),
              ),
          ],
        ),
      ),
      lineBarsData: [
        for (var si = 0; si < vista.series.length; si++)
          () {
            final s = vista.series[si];
            final c = colores[si];

            return LineChartBarData(
              spots: [
                for (var i = 0; i < s.data.length; i++)
                  if (s.data[i] != null) FlSpot(i.toDouble(), s.data[i]!) else FlSpot.nullSpot,
              ],
              color: c,
              barWidth: s.comparacion ? 1.5 : 2.5,
              dashArray: s.comparacion ? [4, 4] : null,
              isCurved: false,
              belowBarData: BarAreaData(show: area && !s.comparacion, color: c.withValues(alpha: 0.18)),
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
}

// Barras horizontales a mano: en el teléfono el rótulo completo entra arriba de cada barra
// (rotar el BarChart de fl_chart rota también los textos).
class _BarrasH extends StatelessWidget {
  final GraficoVista vista;
  final List<Color> colores;
  const _BarrasH({required this.vista, required this.colores});

  @override
  Widget build(BuildContext context) {
    final valores = vista.series.expand((s) => s.data).whereType<double>().map((v) => v.abs());
    final maxAbs = valores.isEmpty ? 1.0 : math.max(valores.reduce(math.max), 1e-9);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (var i = 0; i < vista.categorias.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(vista.categorias[i], maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 3),
            for (var s = 0; s < vista.series.length; s++)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: ((vista.series[s].data[i] ?? 0).abs() / maxAbs).clamp(0.0, 1.0),
                        child: Container(
                          height: vista.series[s].comparacion ? 6 : 10,
                          decoration: BoxDecoration(
                            // Negativo en rojo: la barra crece igual hacia la derecha.
                            color: (vista.series[s].data[i] ?? 0) < 0 ? const Color(0xFFE24B4A) : colores[s],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 92,
                    child: Text(fValor(vista.series[s].data[i], vista.formato),
                        textAlign: TextAlign.right,
                        style: rmMono.copyWith(
                            fontSize: 11, color: vista.series[s].comparacion ? AppColors.dim : AppColors.txt)),
                  ),
                ]),
              ),
          ]),
        ),
    ]);
  }
}

class _Torta extends StatelessWidget {
  final TortaVista torta;
  final bool dona;
  const _Torta({required this.torta, required this.dona});

  Color _color(int i) => torta.rotulos[i] == 'Otros' ? _gris : _paletaTorta[i % _paletaTorta.length];

  @override
  Widget build(BuildContext context) {
    final total = torta.valores.fold<double>(0, (a, v) => a + v);
    if (total <= 0) {
      return const Text('Sin valores para repartir.', style: TextStyle(fontSize: 12, color: AppColors.dim));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 180,
        child: PieChart(PieChartData(
          centerSpaceRadius: dona ? 44 : 0,
          sectionsSpace: 1,
          startDegreeOffset: -90,
          sections: [
            for (var i = 0; i < torta.valores.length; i++)
              PieChartSectionData(
                value: torta.valores[i],
                color: _color(i),
                radius: dona ? 40 : 84,
                // Las porciones grandes dicen qué son; las chicas, nada (la lista de abajo las nombra).
                title: rotuloPorcion(torta.valores[i] / total * 100, torta.rotulos[i], dona: dona),
                titleStyle: const TextStyle(fontSize: 9, height: 1.2, fontWeight: FontWeight.w700, color: AppColors.navy),
                titlePositionPercentageOffset: dona ? 0.5 : 0.6,
              ),
          ],
        )),
      ),
      const SizedBox(height: 10),
      for (var i = 0; i < torta.valores.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Row(children: [
            Container(
                width: 10, height: 10, decoration: BoxDecoration(color: _color(i), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 6),
            Expanded(
              child: Text(torta.rotulos[i],
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            ),
            Text(fValor(torta.valores[i], torta.formato), style: rmMono.copyWith(fontSize: 11)),
            SizedBox(
              width: 52,
              child: Text(fPorcentaje(torta.valores[i] / total),
                  textAlign: TextAlign.right, style: rmMono.copyWith(fontSize: 11, color: AppColors.dim)),
            ),
          ]),
        ),
    ]);
  }
}
