import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';
import 'reportes_repository.dart';

enum ReportKind {
  breveVenta,
  ventas,
  vendedor,
  gastos,
  stocks,
  alertas,
  provincia,
  cheques,
  productos,
  fallados,
  corregido,
  facturacion,
  clientesCredito,
  ingreso,
  movidos,
  reservado,
}

extension ReportKindX on ReportKind {
  String get title => switch (this) {
        ReportKind.breveVenta => 'Breve Venta',
        ReportKind.ventas => 'Ventas',
        ReportKind.vendedor => 'Vendedor',
        ReportKind.gastos => 'Gastos',
        ReportKind.stocks => 'Stocks',
        ReportKind.alertas => 'Alertas',
        ReportKind.provincia => 'Provincia',
        ReportKind.cheques => 'Cheques',
        ReportKind.productos => 'Productos',
        ReportKind.fallados => 'Fallados',
        ReportKind.corregido => 'Corregido',
        ReportKind.facturacion => 'Facturación',
        ReportKind.clientesCredito => 'Clientes Crédito',
        ReportKind.ingreso => 'Ingreso',
        ReportKind.movidos => 'Movidos',
        ReportKind.reservado => 'Reservado',
      };

  // 스냅샷(재고/잔액) 리포트는 기간 필터 없음.
  bool get hasPeriod =>
      this != ReportKind.stocks &&
      this != ReportKind.alertas &&
      this != ReportKind.clientesCredito;
}

class ReporteDetalleScreen extends ConsumerStatefulWidget {
  final ReportKind kind;
  const ReporteDetalleScreen({super.key, required this.kind});

  @override
  ConsumerState<ReporteDetalleScreen> createState() =>
      _ReporteDetalleScreenState();
}

class _ReporteDetalleScreenState extends ConsumerState<ReporteDetalleScreen> {
  int _period = 0;

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
          if (widget.kind.hasPeriod)
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
        return _w(ref.watch(breveVentaProvider(r)), _breve,
            () => ref.invalidate(breveVentaProvider(r)));
      case ReportKind.ventas:
        return _w(ref.watch(salesReportProvider(r)), _ventas,
            () => ref.invalidate(salesReportProvider(r)));
      case ReportKind.vendedor:
        return _w(ref.watch(vendedorReportProvider(r)), _vendedor,
            () => ref.invalidate(vendedorReportProvider(r)));
      case ReportKind.gastos:
        return _w(ref.watch(gastoReportProvider(r)), _gastos,
            () => ref.invalidate(gastoReportProvider(r)));
      case ReportKind.stocks:
        return _w(ref.watch(stocksReportProvider), _stocks,
            () => ref.invalidate(stocksReportProvider));
      case ReportKind.alertas:
        return _w(ref.watch(alertasReportProvider), _alertas,
            () => ref.invalidate(alertasReportProvider));
      case ReportKind.cheques:
        return _w(ref.watch(chequesReportProvider(r)), _cheques,
            () => ref.invalidate(chequesReportProvider(r)));
      case ReportKind.productos:
        return _w(ref.watch(productosReportProvider(r)), _productos,
            () => ref.invalidate(productosReportProvider(r)));
      case ReportKind.fallados:
        return _w(ref.watch(falladosReportProvider(r)),
            (rows) => _saleDoc(rows, AppColors.red, 'anulada'),
            () => ref.invalidate(falladosReportProvider(r)));
      case ReportKind.corregido:
        return _w(ref.watch(corregidoReportProvider(r)),
            (rows) => _saleDoc(rows, AppColors.amber, 'corregida'),
            () => ref.invalidate(corregidoReportProvider(r)));
      case ReportKind.facturacion:
        return _w(ref.watch(facturacionReportProvider(r)),
            (rows) => _saleDoc(rows, AppColors.green, 'facturada'),
            () => ref.invalidate(facturacionReportProvider(r)));
      case ReportKind.clientesCredito:
        return _w(ref.watch(clientesCreditoReportProvider), _clientesCredito,
            () => ref.invalidate(clientesCreditoReportProvider));
      case ReportKind.ingreso:
        return _w(ref.watch(ingresoReportProvider(r)),
            (rows) => _stockMov(rows, false),
            () => ref.invalidate(ingresoReportProvider(r)));
      case ReportKind.movidos:
        return _w(ref.watch(movidosReportProvider(r)),
            (rows) => _stockMov(rows, true),
            () => ref.invalidate(movidosReportProvider(r)));
      case ReportKind.reservado:
        return _w(ref.watch(reservadoReportProvider(r)), _reservado,
            () => ref.invalidate(reservadoReportProvider(r)));
      case ReportKind.provincia:
        return _wv(ref.watch(provinciaReportProvider(r)), _provincia,
            () => ref.invalidate(provinciaReportProvider(r)));
    }
  }

  Widget _w<T>(AsyncValue<List<T>> a, Widget Function(List<T>) build,
          VoidCallback refresh) =>
      _shell(a.isLoading, a.hasError, a.error,
          a.hasValue && a.value!.isEmpty, refresh, () => build(a.value!));

  Widget _wv(AsyncValue<ProvinciaResult> a,
          Widget Function(ProvinciaResult) build, VoidCallback refresh) =>
      _shell(a.isLoading, a.hasError, a.error,
          a.hasValue && a.value!.rows.isEmpty, refresh, () => build(a.value!));

  Widget _shell(bool loading, bool hasError, Object? error, bool empty,
      VoidCallback refresh, Widget Function() build) {
    return RefreshIndicator(
      onRefresh: () async => refresh(),
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : hasError
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('No se pudo cargar el reporte.\n$error',
                        style: const TextStyle(color: AppColors.red, fontSize: 12)),
                  )
                ])
              : empty
                  ? ListView(children: const [
                      Padding(
                        padding: EdgeInsets.only(top: 60),
                        child: Center(
                            child: Text('Sin datos en el período',
                                style: TextStyle(color: AppColors.dim))),
                      )
                    ])
                  : build(),
    );
  }

  // ── 렌더러 ──

  Widget _breve(List<BreveVentaRow> rows) {
    final t = rows.fold<num>(0, (a, b) => a + b.totalMonto);
    final v = rows.fold<int>(0, (a, b) => a + b.cantidadVentas);

    return _listView([
      _kpiRow('Total', money(t), AppColors.gold, 'Ventas', '$v', AppColors.cyan),
      for (final d in rows)
        _RowCard(
            left: d.fecha,
            sub: '${d.cantidadVentas} venta${d.cantidadVentas == 1 ? '' : 's'}',
            right: money(d.totalMonto),
            rightColor: AppColors.gold),
    ]);
  }

  Widget _ventas(List<SalesRow> rows) {
    final t = rows.fold<num>(0, (a, b) => a + b.totalAmount);

    return _listView([
      _kpiRow('Total', money(t), AppColors.gold, 'Comprobantes',
          '${rows.length}', AppColors.cyan),
      for (final s in rows)
        _RowCard(
            left: s.client.isEmpty ? 'Venta #${s.id}' : s.client,
            sub: [
              _short(s.saleDate),
              if (s.paymentMethods.isNotEmpty) s.paymentMethods,
              if (s.status.isNotEmpty) s.status,
            ].join(' · '),
            right: money(s.totalAmount),
            rightColor: AppColors.green),
    ]);
  }

  Widget _vendedor(List<VendedorRow> rows) => _listView([
        for (var i = 0; i < rows.length; i++)
          _RowCard(
              rank: i + 1,
              left: rows[i].sellerName,
              sub: '${rows[i].totalSales} venta${rows[i].totalSales == 1 ? '' : 's'}',
              right: money(rows[i].totalAmount),
              rightColor: AppColors.gold),
      ]);

  Widget _gastos(List<GastoRow> rows) {
    final t = rows.fold<num>(0, (a, b) => a + b.amount);

    return _listView([
      _kpiRow('Total gastos', money(t), AppColors.red, 'Ítems',
          '${rows.length}', AppColors.cyan),
      for (final g in rows)
        _RowCard(
            left: g.description.isEmpty ? g.category : g.description,
            sub: [
              _short(g.date),
              if (g.category.isNotEmpty) g.category,
              if (g.userName.isNotEmpty) g.userName,
            ].join(' · '),
            right: money(g.amount),
            rightColor: AppColors.red),
    ]);
  }

  Widget _stocks(List<StockRow> rows) => _listView([
        _hint('${rows.length} productos · stock real actual'),
        for (final s in rows)
          _RowCard(
              left: [s.code, s.description].where((e) => e.isNotEmpty).join(' · '),
              sub: 'Vendidos ${s.tVenta}',
              right: '${s.sReal}',
              rightColor: s.sReal <= 0 ? AppColors.red : AppColors.txt,
              rightSub: 'stock'),
      ]);

  Widget _alertas(List<AlertaRow> rows) => _listView([
        _hint('${rows.length} alertas de stock'),
        for (final a in rows) _AlertaCard(row: a),
      ]);

  Widget _cheques(List<ChequeRow> rows) {
    final t = rows.fold<num>(0, (a, b) => a + b.monto);

    return _listView([
      _kpiRow('Total', money(t), AppColors.gold, 'Cheques', '${rows.length}',
          AppColors.cyan),
      for (final c in rows)
        _RowCard(
            left: c.cliente.isEmpty ? 'Venta #${c.nroVenta}' : c.cliente,
            sub: [_short(c.fecha), if (c.estadoVenta.isNotEmpty) c.estadoVenta]
                .join(' · '),
            right: money(c.monto),
            rightColor: AppColors.gold),
    ]);
  }

  Widget _productos(List<ProductoRow> rows) => _listView([
        _hint('${rows.length} productos · más vendidos primero'),
        for (var i = 0; i < rows.length; i++)
          _RowCard(
              rank: i + 1,
              left: [rows[i].code, rows[i].description]
                  .where((e) => e.isNotEmpty)
                  .join(' · '),
              sub: 'Precio ${money(rows[i].price)}',
              right: '${rows[i].quantity}',
              rightColor: AppColors.txt,
              rightSub: 'vendidos'),
      ]);

  Widget _saleDoc(List<SaleDocRow> rows, Color color, String tag) {
    final t = rows.fold<num>(0, (a, b) => a + b.totalAmount);

    return _listView([
      _kpiRow('Total', money(t), color, 'Comprobantes', '${rows.length}',
          AppColors.cyan),
      for (final s in rows)
        _RowCard(
            left: s.client.isEmpty ? 'Venta #${s.saleId}' : s.client,
            sub: [_short(s.saleDate), if (s.seller.isNotEmpty) s.seller, tag]
                .join(' · '),
            right: money(s.totalAmount),
            rightColor: color),
    ]);
  }

  Widget _clientesCredito(List<ClienteCreditoRow> rows) {
    final t = rows.fold<num>(0, (a, b) => a + b.saldo);

    return _listView([
      _kpiRow('Saldo total', money(t), AppColors.gold, 'Clientes',
          '${rows.length}', AppColors.cyan),
      for (final c in rows)
        _RowCard(
            left: c.cliente.isEmpty ? c.documento : c.cliente,
            sub: [c.documento, c.telefono].where((e) => e.isNotEmpty).join(' · '),
            right: money(c.saldo),
            rightColor: AppColors.gold,
            rightSub: 'saldo'),
    ]);
  }

  Widget _stockMov(List<StockMovRow> rows, bool showTipo) => _listView([
        _hint('${rows.length} movimientos'),
        for (final m in rows)
          _RowCard(
              left: m.producto.isEmpty ? m.sku : m.producto,
              sub: [m.sku, m.sucursal, _short(m.fecha)]
                  .where((e) => e.isNotEmpty)
                  .join(' · '),
              right: '${m.cantidad}',
              rightColor: showTipo && m.tipo == 'Egreso'
                  ? AppColors.red
                  : AppColors.green,
              rightSub: showTipo ? m.tipo : 'u'),
      ]);

  Widget _reservado(List<ReservadoRow> rows) {
    final t = rows.fold<num>(0, (a, b) => a + b.monto);

    return _listView([
      _kpiRow('Total', money(t), AppColors.gold, 'Reservas', '${rows.length}',
          AppColors.cyan),
      for (final r in rows)
        _RowCard(
            left: r.cliente.isEmpty ? 'Reserva' : r.cliente,
            sub: [_short(r.fecha), if (r.vendedor.isNotEmpty) r.vendedor]
                .join(' · '),
            right: money(r.monto),
            rightColor: AppColors.gold),
    ]);
  }

  Widget _provincia(ProvinciaResult res) => _listView([
        _kpiRow('Total', money(res.totalAmount), AppColors.gold, 'Provincias',
            '${res.rows.length}', AppColors.cyan),
        for (var i = 0; i < res.rows.length; i++)
          _RowCard(
              rank: i + 1,
              left: res.rows[i].provinceName,
              sub: '${res.rows[i].sales.toInt()} ventas · ${res.rows[i].quantity.toInt()} u · ${res.rows[i].pct}%',
              right: money(res.rows[i].amount),
              rightColor: AppColors.gold),
      ]);

  // ── 공용 ──

  Widget _listView(List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: children,
      );

  Widget _kpiRow(String l1, String v1, Color c1, String l2, String v2, Color c2) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(children: [
          Expanded(child: _Kpi(l1, v1, c1)),
          const SizedBox(width: 11),
          Expanded(child: _Kpi(l2, v2, c2)),
        ]),
      );

  Widget _hint(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Text(t, style: const TextStyle(fontSize: 11.5, color: AppColors.dim)),
      );

  String _short(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    final l = d.toLocal();

    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}';
  }
}

// ── 위젯 ──

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
  final String? rightSub;
  const _RowCard({
    this.rank,
    required this.left,
    required this.sub,
    required this.right,
    required this.rightColor,
    this.rightSub,
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(right,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: rightColor)),
              if (rightSub != null)
                Text(rightSub!,
                    style: const TextStyle(fontSize: 9.5, color: AppColors.dim)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertaCard extends StatelessWidget {
  final AlertaRow row;
  const _AlertaCard({required this.row});
  @override
  Widget build(BuildContext context) {
    final sinStock = row.stockActual <= 0;
    final color = sinStock ? AppColors.red : AppColors.gold;

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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.producto.isEmpty ? row.sku : row.producto,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text([row.sku, row.sucursal].where((e) => e.isNotEmpty).join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10.5, color: AppColors.dim)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(row.estado.isEmpty ? '${row.stockActual}' : row.estado,
                style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: color)),
          ),
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
