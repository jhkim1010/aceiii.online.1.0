// Reporte a medida — resultado: titular de comparación, totales, pestañas Lista / Gráficos, CSV y PDF.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_theme.dart';
import 'rm_controller.dart';
import 'rm_formato.dart';
import 'rm_graficos.dart';
import 'rm_guardados.dart';
import 'rm_modelos.dart';
import 'rm_repository.dart';
import 'rm_resultado_vista.dart';
import 'rm_widgets.dart';

class RmResultadoScreen extends ConsumerStatefulWidget {
  const RmResultadoScreen({super.key});

  @override
  ConsumerState<RmResultadoScreen> createState() => _RmResultadoScreenState();
}

class _RmResultadoScreenState extends ConsumerState<RmResultadoScreen> {
  // Cuál se está preparando ('csv' | 'pdf'); uno a la vez.
  String? _compartiendo;

  Future<void> _compartir(String tipo) async {
    if (_compartiendo != null) return;
    setState(() => _compartiendo = tipo);
    try {
      final ctrl = ref.read(rmControllerProvider.notifier);
      final arch = tipo == 'pdf' ? await ctrl.pdf() : await ctrl.csv();
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(arch.bytes, mimeType: tipo == 'pdf' ? 'application/pdf' : 'text/csv', name: arch.nombre)],
        fileNameOverrides: [arch.nombre],
      ));
    } catch (e) {
      final err = clasificarError(e);
      if (!mounted) return;
      final extra = err.fixesCsv.isEmpty ? '' : ' (${err.fixesCsv.join(' · ')})';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${err.mensajeEs}$extra'), backgroundColor: const Color(0xFFE24B4A), behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _compartiendo = null);
    }
  }

  void _elegirCompartir() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.panel,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.gold),
            title: const Text('PDF (todos los gráficos)'),
            subtitle: const Text('Resumen, cada gráfico y la tabla completa', style: TextStyle(fontSize: 12)),
            onTap: () {
              Navigator.of(ctx).pop();
              _compartir('pdf');
            },
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined, color: AppColors.gold),
            title: const Text('CSV (planilla)'),
            subtitle: const Text('Todas las filas, para Excel', style: TextStyle(fontSize: 12)),
            onTap: () {
              Navigator.of(ctx).pop();
              _compartir('csv');
            },
          ),
        ]),
      ),
    );
  }

  Widget _iconoCompartir(String tipo, IconData icono, String tooltip, bool habilitado) => IconButton(
        tooltip: tooltip,
        icon: _compartiendo == tipo
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Icon(icono, color: AppColors.gold),
        onPressed: habilitado && _compartiendo == null ? () => _compartir(tipo) : null,
      );

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(rmControllerProvider);
    final r = st.resultado;
    final ctrl = ref.read(rmControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resultado'),
        actions: [
          _iconoCompartir('pdf', Icons.picture_as_pdf_outlined, 'Compartir PDF', st.vigente && !st.ejecutando),
          _iconoCompartir('csv', Icons.table_chart_outlined, 'Compartir CSV', st.vigente && !st.ejecutando),
        ],
      ),
      body: RefreshIndicator(
        // Mientras se arma un PDF/CSV no se vuelve a ejecutar (CODEX).
        onRefresh: () async {
          if (_compartiendo == null) await ctrl.ejecutar();
        },
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
                      onPressed: st.vigente && !st.ejecutando && _compartiendo == null ? _elegirCompartir : null,
                      child: _compartiendo != null
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Compartir PDF / CSV', style: TextStyle(fontWeight: FontWeight.w700)),
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
  int _mostradas = tamPagina;
  bool _graficos = false;
  final _buscar = TextEditingController();

  @override
  void didUpdateWidget(covariant _Contenido old) {
    super.didUpdateWidget(old);
    // Un reporte nuevo puede no tener la misma dimensión: la búsqueda vieja no aplica.
    if (!identical(old.resultado, widget.resultado)) {
      _buscar.clear();
      _mostradas = tamPagina;
    }
  }

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.resultado;
    final p = widget.pedido;
    final cols = columnasVista(r, p);
    final dims = r.columnas.where((c) => c.tipo == 'dimension').map((c) => c.id).toList();
    final buscable = dimBuscable(cols);
    final q = buscable == null ? '' : _buscar.text.trim();
    final encontradas = filtrarBusqueda(r.filas, dims, q);
    final filas = filasVista(encontradas, dims);
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
        _Pastilla('${fFechaCorta(r.meta.desde)} – ${fFechaCorta(r.meta.hasta)} · ${fEntero(r.meta.filas)} ${r.meta.filas == 1 ? 'fila' : 'filas'}'),
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
                TextSpan(text: titular.intro),
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
      const SizedBox(height: 12),
      // Lista / Gráficos como en la web: la tabla sola y los gráficos todos juntos.
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, icon: Icon(Icons.view_list, size: 18), label: Text('Lista')),
          ButtonSegment(value: true, icon: Icon(Icons.bar_chart, size: 18), label: Text('Gráficos')),
        ],
        selected: {_graficos},
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: AppColors.gold.withValues(alpha: 0.14),
          selectedForegroundColor: AppColors.gold,
          foregroundColor: AppColors.dim,
          side: const BorderSide(color: AppColors.line),
        ),
        onSelectionChanged: (v) => setState(() => _graficos = v.first),
      ),
      const SizedBox(height: 10),
      if (_graficos)
        RmGraficosTab(resultado: r, pedido: p)
      else ...[
      if (buscable != null) ...[
        TextField(
          controller: _buscar,
          onChanged: (_) => setState(() => _mostradas = tamPagina),
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Buscar ${buscable.header.toLowerCase()}…',
            prefixIcon: const Icon(Icons.search, size: 18),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() {
                      _buscar.clear();
                      _mostradas = tamPagina;
                    })),
          ),
        ),
        const SizedBox(height: 8),
      ],
      _Tabla(cols: cols, filas: filas.take(_mostradas).toList(), total: filaTotal(r, cols)),
      if (q.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
              '${fEntero(encontradas.length)} de ${fEntero(r.filas.length)} filas contienen «$q». El total sigue siendo de todo el período.',
              style: const TextStyle(fontSize: 11, color: AppColors.dim)),
        ),
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
      ],
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
