// Reporte a medida — piezas visuales compartidas (chip con bloqueo, tarjeta de paso, motivos).
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'rm_formato.dart';
import 'rm_logica.dart';

const rmOk = Color(0xFF4ADE80);
const rmErrorTxt = Color(0xFFFF8A80);
const rmInfo = Color(0xFF60A5FA);
const rmCerca = Color(0xFFFFD28A);
const rmOff = Color(0xFF6E7A99);
const rmMono = TextStyle(fontFamily: 'monospace', fontFeatures: [FontFeature.tabularFigures()]);

Color colorSigno(Signo? s) => switch (s) {
      Signo.pos => rmOk,
      Signo.neg => rmErrorTxt,
      _ => AppColors.dim,
    };

IconData iconoBloqueo(TipoBloqueo t) => switch (t) {
      TipoBloqueo.permiso => Icons.lock_outline,
      TipoBloqueo.combinacion || TipoBloqueo.maximo => Icons.block,
      TipoBloqueo.sinDatos => Icons.storage_outlined,
    };

// Chip seleccionable. Bloqueado: sigue visible, borde punteado simulado, ícono del motivo.
class RmChip extends StatelessWidget {
  final String label;
  final String? sub;
  final bool elegida;
  final bool auto;
  final Bloqueo? bloqueo;
  final VoidCallback? onTap;
  const RmChip(
      {super.key, required this.label, this.sub, this.elegida = false, this.auto = false, this.bloqueo, this.onTap});

  @override
  Widget build(BuildContext context) {
    final off = bloqueo != null && !elegida;
    final fg = off ? rmOff : (elegida || auto ? AppColors.gold : AppColors.txt);
    final borde = off
        ? AppColors.line
        : (elegida || auto ? AppColors.gold : AppColors.line);

    return Semantics(
      button: true,
      selected: elegida,
      enabled: !off,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: off || auto ? null : onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: elegida ? AppColors.gold.withValues(alpha: 0.14) : (off || auto ? Colors.transparent : AppColors.navy2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borde, width: off || auto ? 1 : 1.2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${elegida ? '✓ ' : ''}${auto ? '+ ' : ''}$label',
                    style: TextStyle(
                        fontSize: 13,
                        color: fg,
                        fontWeight: elegida ? FontWeight.w700 : FontWeight.w400,
                        fontStyle: auto ? FontStyle.italic : FontStyle.normal),
                  ),
                  if (sub != null) Text(sub!, style: const TextStyle(fontSize: 10, color: AppColors.dim)),
                ],
              ),
            ),
            if (off) ...[const SizedBox(width: 6), Icon(iconoBloqueo(bloqueo!.tipo), size: 14, color: rmOff)],
          ]),
        ),
      ),
    );
  }
}

// Tarjeta de un paso: cabecera tocable que se pliega mostrando el resumen.
class RmPasoCard extends StatelessWidget {
  final int numero;
  final String titulo;
  final String? cap;
  final String resumen;
  final bool abierto;
  final VoidCallback onToggle;
  final Widget child;
  const RmPasoCard(
      {super.key,
      required this.numero,
      required this.titulo,
      this.cap,
      required this.resumen,
      required this.abierto,
      required this.onToggle,
      required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                child: Text('$numero',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.navy)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(abierto ? (cap ?? '') : resumen,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: abierto ? AppColors.dim : AppColors.gold)),
                ]),
              ),
              Icon(abierto ? Icons.expand_less : Icons.expand_more, color: AppColors.dim),
            ]),
          ),
        ),
        if (abierto) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14), child: child),
      ]),
    );
  }
}

// Motivos de lo bloqueado, escritos (nunca sólo en un tooltip: el teléfono no tiene hover).
class RmRazones extends StatelessWidget {
  final List<EstadoOpcion> opciones;
  final bool incluirMaximo;
  const RmRazones(this.opciones, {super.key, this.incluirMaximo = false});

  @override
  Widget build(BuildContext context) {
    final vistos = <String>{};
    final filas = <EstadoOpcion>[];
    for (final o in opciones) {
      final b = o.bloqueo;
      if (b == null || o.elegida || b.motivoEs.isEmpty) continue;
      if (b.tipo == TipoBloqueo.maximo && !incluirMaximo) continue;
      if (vistos.add('${o.labelEs}|${b.motivoEs}')) filas.add(o);
    }
    if (filas.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AppColors.navy2, borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final o in filas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(iconoBloqueo(o.bloqueo!.tipo), size: 14, color: AppColors.dim),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: o.labelEs, style: const TextStyle(color: AppColors.txt, fontWeight: FontWeight.w700)),
                    TextSpan(text: ' — ${o.bloqueo!.motivoEs}'),
                  ]),
                  style: const TextStyle(fontSize: 12, color: AppColors.dim, height: 1.35),
                ),
              ),
            ]),
          ),
      ]),
    );
  }
}

class RmAviso extends StatelessWidget {
  final String texto;
  final Color fg;
  final Color bg;
  final IconData? icono;
  const RmAviso(this.texto, {super.key, this.fg = const Color(0xFFBCD7FF), this.bg = const Color(0x1F60A5FA), this.icono});

  const RmAviso.dorado(this.texto, {super.key})
      : fg = rmCerca,
        bg = const Color(0x1AF5A623),
        icono = null;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (icono != null) ...[Icon(icono, size: 16, color: fg), const SizedBox(width: 8)],
        Expanded(child: Text(texto, style: TextStyle(fontSize: 12, color: fg, height: 1.4))),
      ]),
    );
  }
}

// Selector en hoja inferior (reemplaza al Select de la web).
Future<T?> rmElegir<T>(BuildContext context, String titulo, List<(T, String)> opciones, T? actual) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: AppColors.panel,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Text(titulo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final o in opciones)
                ListTile(
                  title: Text(o.$2),
                  trailing: o.$1 == actual ? const Icon(Icons.check, color: AppColors.gold) : null,
                  onTap: () => Navigator.pop(ctx, o.$1),
                ),
            ]),
          ),
        ]),
      ),
    ),
  );
}

class RmCampo extends StatelessWidget {
  final String label;
  final String valor;
  final bool error;
  final VoidCallback onTap;
  const RmCampo({super.key, required this.label, required this.valor, required this.onTap, this.error = false});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 12, color: AppColors.dim)),
      const SizedBox(height: 4),
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.navy2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: error ? rmErrorTxt : AppColors.line),
          ),
          child: Row(children: [
            Expanded(child: Text(valor, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14))),
            const Icon(Icons.expand_more, size: 18, color: AppColors.dim),
          ]),
        ),
      ),
    ]);
  }
}
