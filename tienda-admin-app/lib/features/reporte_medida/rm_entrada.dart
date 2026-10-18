// Reporte a medida — entrada en el tab Reportes: tarjeta + los 3 primeros «Mis reportes».
// Sin el permiso `reporte-a-medida` el catálogo responde 403 y la sección no se muestra.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'reporte_medida_screen.dart';
import 'rm_guardados.dart';
import 'rm_logica.dart';
import 'rm_repository.dart';

class RmEntradaHub extends ConsumerWidget {
  const RmEntradaHub({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cat = ref.watch(rmCatalogoProvider);
    final err = cat.error;
    if (err != null && clasificarError(err).tipo == TipoErrorRm.permiso) return const SizedBox.shrink();
    final guardados = ref.watch(rmGuardadosProvider).valueOrNull ?? const [];

    void abrir([int? id]) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ReporteMedidaScreen(abrirId: id)));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(2, 4, 2, 10),
        child: Text('A MEDIDA',
            style: TextStyle(fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.w800, color: AppColors.dim)),
      ),
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: abrir,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.panel,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.gold),
              ),
              child: const Icon(Icons.tune, size: 20, color: AppColors.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Text('Reporte a medida', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(4)),
                    child: const Text('NUEVO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.navy)),
                  ),
                ]),
                const SizedBox(height: 3),
                const Text('Armá tu propio reporte eligiendo de una lista.', style: TextStyle(fontSize: 12, color: AppColors.dim)),
              ]),
            ),
            const Icon(Icons.chevron_right, color: AppColors.dim),
          ]),
        ),
      ),
      if (guardados.isNotEmpty) ...[
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
              color: AppColors.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.line)),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 4, 0),
              child: Row(children: [
                const Expanded(child: Text('Mis reportes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (ctx) => MisReportesScreen(onAbrir: (id) {
                            Navigator.of(ctx).pushReplacement(
                                MaterialPageRoute(builder: (_) => ReporteMedidaScreen(abrirId: id)));
                          }))),
                  child: Text('Ver todos (${guardados.length})', style: const TextStyle(fontSize: 12)),
                ),
              ]),
            ),
            for (final g in guardados.take(3))
              InkWell(
                onTap: () => abrir(g.id),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.line))),
                  child: Row(children: [
                    const Icon(Icons.bookmark_outline, size: 16, color: AppColors.gold),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                        Text(queMuestra(g.order, cat.valueOrNull),
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.dim)),
                      ]),
                    ),
                    const SizedBox(width: 8),
                    g.catalogoCambio
                        ? const Text('definición cambió', style: TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700))
                        : Text(g.shared ? 'con la tienda' : 'sólo yo',
                            style: TextStyle(fontSize: 11, color: g.shared ? AppColors.cyan : AppColors.dim)),
                  ]),
                ),
              ),
          ]),
        ),
      ],
      const SizedBox(height: 14),
    ]);
  }
}
