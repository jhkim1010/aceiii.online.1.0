import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'reporte_detalle_screen.dart';

// 리포트 허브 — 연결된 3종(Ventas·Breve Venta·Vendedor)은 상세로, 나머지는 안내.
class ReportesScreen extends ConsumerWidget {
  const ReportesScreen({super.key});

  // (라벨, 아이콘, 설명, 연결된 리포트 종류 or null)
  static const _groups = <(String, List<(String, IconData, String, ReportKind?)>)>[
    (
      'Ventas & caja',
      [
        ('Ventas', Icons.trending_up, 'Detalle por período', ReportKind.ventas),
        ('Breve Venta', Icons.receipt, 'Resumen diario', ReportKind.breveVenta),
        ('Vendedor', Icons.emoji_events_outlined, 'Ranking por vendedor', ReportKind.vendedor),
        ('Gastos', Icons.payments_outlined, 'Listado por período', null),
      ],
    ),
    (
      'Stock & productos',
      [
        ('Stocks', Icons.inventory_2_outlined, 'Existencias actuales', null),
        ('Alertas', Icons.warning_amber_outlined, 'Stock bajo/agotado', null),
        ('Provincia', Icons.map_outlined, 'Ranking por provincia', null),
        ('Cheques', Icons.account_balance_wallet_outlined, 'Estado de pagos', null),
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
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 4),
        const Center(
          child: Text('+ Facturación · Clientes crédito · Fallados …',
              style: TextStyle(color: AppColors.dim, fontSize: 11)),
        ),
      ],
    );
  }
}

class _ReportCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final String desc;
  final ReportKind? kind;
  const _ReportCard(
      {required this.title,
      required this.icon,
      required this.desc,
      required this.kind});

  @override
  Widget build(BuildContext context) {
    final active = kind != null;

    return GestureDetector(
      onTap: () {
        if (active) {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => ReporteDetalleScreen(kind: kind!),
          ));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Reporte "$title" — disponible en la próxima versión.'),
            behavior: SnackBarBehavior.floating,
          ));
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active
                  ? AppColors.gold.withValues(alpha: 0.3)
                  : AppColors.line),
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
                if (active)
                  const Icon(Icons.chevron_right, size: 16, color: AppColors.dim),
              ],
            ),
            const Spacer(),
            Text(title,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700)),
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
