import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';
import 'reportes_repository.dart';

enum ReportKind { breveVenta, ventas, vendedor }

extension on ReportKind {
  String get title => switch (this) {
        ReportKind.breveVenta => 'Breve Venta',
        ReportKind.ventas => 'Ventas',
        ReportKind.vendedor => 'Vendedor',
      };
}

class ReporteDetalleScreen extends ConsumerStatefulWidget {
  final ReportKind kind;
  const ReporteDetalleScreen({super.key, required this.kind});

  @override
  ConsumerState<ReporteDetalleScreen> createState() =>
      _ReporteDetalleScreenState();
}

class _ReporteDetalleScreenState extends ConsumerState<ReporteDetalleScreen> {
  int _period = 0; // 0=Hoy 1=7 días 2=Mes

  // 선택 기간 → ReportRange (하루 끝까지 포함하도록 end 는 23:59:59)
  ReportRange get _range {
    final now = DateTime.now();
    final endDay = DateTime(now.year, now.month, now.day);
    DateTime startDay;
    switch (_period) {
      case 1:
        startDay = endDay.subtract(const Duration(days: 6));
        break;
      case 2:
        startDay = DateTime(now.year, now.month, 1);
        break;
      default:
        startDay = endDay;
    }

    return (start: '${_ymd(startDay)} 00:00:00', end: '${_ymd(endDay)} 23:59:59');
  }

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: Text(widget.kind.title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: _Segment(
              value: _period,
              labels: const ['Hoy', '7 días', 'Mes'],
              onChanged: (i) => setState(() => _period = i),
            ),
          ),
          Expanded(child: _body(_range)),
        ],
      ),
    );
  }

  Widget _body(ReportRange r) {
    switch (widget.kind) {
      case ReportKind.breveVenta:
        return _wrap(ref.watch(breveVentaProvider(r)),
            (rows) => _breve(rows), () => ref.invalidate(breveVentaProvider(r)));
      case ReportKind.ventas:
        return _wrap(ref.watch(salesReportProvider(r)),
            (rows) => _ventas(rows), () => ref.invalidate(salesReportProvider(r)));
      case ReportKind.vendedor:
        return _wrap(ref.watch(vendedorReportProvider(r)),
            (rows) => _vendedor(rows), () => ref.invalidate(vendedorReportProvider(r)));
    }
  }

  Widget _wrap<T>(AsyncValue<List<T>> async, Widget Function(List<T>) build,
      VoidCallback refresh) {
    return RefreshIndicator(
      onRefresh: () async => refresh(),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No se pudo cargar el reporte.\n$e',
                style: const TextStyle(color: AppColors.red, fontSize: 12)),
          )
        ]),
        data: (rows) => rows.isEmpty
            ? ListView(children: const [
                Padding(
                  padding: EdgeInsets.only(top: 60),
                  child: Center(
                      child: Text('Sin datos en el período',
                          style: TextStyle(color: AppColors.dim))),
                )
              ])
            : build(rows),
      ),
    );
  }

  // ── Breve Venta ──
  Widget _breve(List<BreveVentaRow> rows) {
    final totalMonto = rows.fold<num>(0, (a, b) => a + b.totalMonto);
    final totalVentas = rows.fold<int>(0, (a, b) => a + b.cantidadVentas);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        Row(children: [
          Expanded(child: _Kpi('Total', money(totalMonto), AppColors.gold)),
          const SizedBox(width: 11),
          Expanded(child: _Kpi('Ventas', '$totalVentas', AppColors.cyan)),
        ]),
        const SizedBox(height: 12),
        for (final d in rows)
          _RowCard(
            left: d.fecha,
            sub: '${d.cantidadVentas} venta${d.cantidadVentas == 1 ? '' : 's'}',
            right: money(d.totalMonto),
            rightColor: AppColors.gold,
          ),
      ],
    );
  }

  // ── Ventas ──
  Widget _ventas(List<SalesRow> rows) {
    final total = rows.fold<num>(0, (a, b) => a + b.totalAmount);

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        Row(children: [
          Expanded(child: _Kpi('Total', money(total), AppColors.gold)),
          const SizedBox(width: 11),
          Expanded(child: _Kpi('Comprobantes', '${rows.length}', AppColors.cyan)),
        ]),
        const SizedBox(height: 12),
        for (final s in rows)
          _RowCard(
            left: s.client.isEmpty ? 'Venta #${s.id}' : s.client,
            sub: [
              _short(s.saleDate),
              if (s.paymentMethods.isNotEmpty) s.paymentMethods,
              if (s.status.isNotEmpty) s.status,
            ].join(' · '),
            right: money(s.totalAmount),
            rightColor: AppColors.green,
          ),
      ],
    );
  }

  // ── Vendedor ──
  Widget _vendedor(List<VendedorRow> rows) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        for (var i = 0; i < rows.length; i++)
          _RowCard(
            rank: i + 1,
            left: rows[i].sellerName,
            sub: '${rows[i].totalSales} venta${rows[i].totalSales == 1 ? '' : 's'}',
            right: money(rows[i].totalAmount),
            rightColor: AppColors.gold,
          ),
      ],
    );
  }

  String _short(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final l = d.toLocal();

    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  }
}

// ── 공용 위젯 ──

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _Kpi(this.label, this.value, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  fontSize: 9.5,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: AppColors.dim)),
          const SizedBox(height: 5),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  final int? rank;
  final String left;
  final String sub;
  final String right;
  final Color rightColor;
  const _RowCard({
    this.rank,
    required this.left,
    required this.sub,
    required this.right,
    required this.rightColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          if (rank != null) ...[
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: rank! <= 3
                    ? AppColors.gold.withValues(alpha: 0.16)
                    : AppColors.navy2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: Text('$rank',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: rank! <= 3 ? AppColors.gold : AppColors.dim)),
            ),
            const SizedBox(width: 11),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(left,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.dim)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(right,
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w800, color: rightColor)),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final int value;
  final List<String> labels;
  final ValueChanged<int> onChanged;
  const _Segment(
      {required this.value, required this.labels, required this.onChanged});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF0E1428),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == i ? AppColors.gold : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(labels[i],
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: value == i ? AppColors.navy : AppColors.dim)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
