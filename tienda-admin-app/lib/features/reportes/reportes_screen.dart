import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'reporte_detalle_screen.dart';

// 리포트 허브 — 16종 전부 상세로 연결.
class ReportesScreen extends ConsumerWidget {
  const ReportesScreen({super.key});

  static const _groups = <(String, List<(String, IconData, String, ReportKind)>)>[
    (
      'Ventas',
      [
        ('Ventas', Icons.trending_up, 'Detalle por período', ReportKind.ventas),
        ('Breve Venta', Icons.receipt, 'Resumen diario', ReportKind.breveVenta),
        ('Vendedor', Icons.emoji_events_outlined, 'Ranking por vendedor', ReportKind.vendedor),
        ('Reservado', Icons.bookmark_border, 'Ventas reservadas', ReportKind.reservado),
        ('Fallados', Icons.cancel_outlined, 'Ventas anuladas', ReportKind.fallados),
        ('Corregido', Icons.edit_note, 'Ventas corregidas', ReportKind.corregido),
      ],
    ),
    (
      'Facturación & pagos',
      [
        ('Facturación', Icons.description_outlined, 'Comprobantes emitidos', ReportKind.facturacion),
        ('Cheques', Icons.account_balance_wallet_outlined, 'Estado de pagos', ReportKind.cheques),
        ('Clientes Crédito', Icons.credit_score, 'Saldos a crédito', ReportKind.clientesCredito),
        ('Gastos', Icons.payments_outlined, 'Listado por período', ReportKind.gastos),
      ],
    ),
    (
      'Stock & productos',
      [
        ('Stocks', Icons.inventory_2_outlined, 'Existencias actuales', ReportKind.stocks),
        ('Productos', Icons.category_outlined, 'Más vendidos', ReportKind.productos),
        ('Ingreso', Icons.login, 'Ingresos de stock', ReportKind.ingreso),
        ('Movidos', Icons.swap_vert, 'Movimientos de stock', ReportKind.movidos),
        ('Alertas', Icons.warning_amber_outlined, 'Stock bajo/agotado', ReportKind.alertas),
        ('Provincia', Icons.map_outlined, 'Ranking por provincia', ReportKind.provincia),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        for (final g in _groups) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
            child: Text(g.$1.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dim)),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              for (final r in g.$2)
                _ReportCard(title: r.$1, icon: r.$2, desc: r.$3, kind: r.$4),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String desc;
  final ReportKind kind;
  const _ReportCard(
      {required this.title,
      required this.icon,
      required this.desc,
      required this.kind});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ReporteDetalleScreen(kind: kind),
      )),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.navy2,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Icon(icon, size: 16, color: AppColors.gold),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right, size: 16, color: AppColors.dim),
              ],
            ),
            const Spacer(),
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(desc,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 9.5, color: AppColors.dim)),
          ],
        ),
      ),
    );
  }
}
