import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../auth/auth_controller.dart';
import '../../shared/format.dart';

// 리포트 기간 (YYYY-MM-DD HH:mm:ss 문자열).
typedef ReportRange = ({String start, String end});

// ── 모델 ──

class BreveVentaRow {
  final String fecha;
  final int cantidadVentas;
  final num totalMonto;
  BreveVentaRow.fromJson(Map<String, dynamic> j)
      : fecha = (j['fecha'] ?? '').toString(),
        cantidadVentas = asInt(j['cantidadVentas']),
        totalMonto = asNum(j['totalMonto']);
}

class SalesRow {
  final int id;
  final String saleDate;
  final String client;
  final num totalAmount;
  final String status;
  final String paymentMethods;
  SalesRow.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        saleDate = (j['saleDate'] ?? '').toString(),
        client = (j['client'] ?? '').toString(),
        totalAmount = asNum(j['totalAmount']),
        status = (j['status'] ?? '').toString(),
        paymentMethods = (j['paymentMethods'] ?? '').toString();
}

class VendedorRow {
  final String sellerName;
  final int totalSales;
  final num totalAmount;
  VendedorRow.fromJson(Map<String, dynamic> j)
      : sellerName = (j['sellerName'] ?? 'Sin asignar').toString(),
        totalSales = asInt(j['totalSales']),
        totalAmount = asNum(j['totalAmount']);
}

class GastoRow {
  final String date;
  final String description;
  final String category;
  final num amount;
  final String userName;
  GastoRow.fromJson(Map<String, dynamic> j)
      : date = (j['date'] ?? '').toString(),
        description = (j['description'] ?? '').toString(),
        category = (j['category'] ?? '').toString(),
        amount = asNum(j['amount']),
        userName = (j['userName'] ?? '').toString();
}

class StockRow {
  final String code;
  final String description;
  final num sReal;
  final num tVenta;
  StockRow.fromJson(Map<String, dynamic> j)
      : code = (j['code'] ?? '').toString(),
        description = (j['description'] ?? '').toString(),
        sReal = asNum(j['SReal']),
        tVenta = asNum(j['TVenta']);
}

class AlertaRow {
  final String sku;
  final String producto;
  final String sucursal;
  final num stockActual;
  final String estado;
  AlertaRow.fromJson(Map<String, dynamic> j)
      : sku = (j['sku'] ?? '').toString(),
        producto = (j['producto'] ?? '').toString(),
        sucursal = (j['sucursal'] ?? '').toString(),
        stockActual = asNum(j['stockActual']),
        estado = (j['estado'] ?? '').toString();
}

class ProvinciaRow {
  final String provinceName;
  final num quantity;
  final num amount;
  final num sales;
  final num pct;
  ProvinciaRow.fromJson(Map<String, dynamic> j)
      : provinceName = (j['provinceName'] ?? 'Sin provincia').toString(),
        quantity = asNum(j['quantity']),
        amount = asNum(j['amount']),
        sales = asNum(j['sales']),
        pct = asNum(j['pct']);
}

class ProvinciaResult {
  final num totalAmount;
  final List<ProvinciaRow> rows;
  ProvinciaResult(this.totalAmount, this.rows);
}

class ChequeRow {
  final int nroVenta;
  final String fecha;
  final String cliente;
  final num monto;
  final String estadoVenta;
  ChequeRow.fromJson(Map<String, dynamic> j)
      : nroVenta = asInt(j['nroVenta']),
        fecha = (j['fecha'] ?? '').toString(),
        cliente = (j['cliente'] ?? '').toString(),
        monto = asNum(j['monto']),
        estadoVenta = (j['estadoVenta'] ?? '').toString();
}

class ProductoRow {
  final String code;
  final String description;
  final num quantity;
  final num price; // ★DECIMAL 문자열 → asNum
  ProductoRow.fromJson(Map<String, dynamic> j)
      : code = (j['code'] ?? '').toString(),
        description = (j['description'] ?? '').toString(),
        quantity = asNum(j['quantity']),
        price = asNum(j['price']);
}

// Fallados / Facturación 공통 형태
class SaleDocRow {
  final int saleId;
  final String saleDate;
  final String client;
  final String seller;
  final num totalAmount;
  SaleDocRow.fromJson(Map<String, dynamic> j)
      : saleId = asInt(j['saleId']),
        saleDate = (j['saleDate'] ?? '').toString(),
        client = (j['client'] ?? '').toString(),
        seller = (j['seller'] ?? '').toString(),
        totalAmount = asNum(j['totalAmount']);
}

class ClienteCreditoRow {
  final String cliente;
  final String documento;
  final String telefono;
  final num saldo;
  final num limiteCredito;
  ClienteCreditoRow.fromJson(Map<String, dynamic> j)
      : cliente = (j['cliente'] ?? '').toString(),
        documento = (j['documento'] ?? '').toString(),
        telefono = (j['telefono'] ?? '').toString(),
        saldo = asNum(j['saldo']),
        limiteCredito = asNum(j['limiteCredito']);
}

class StockMovRow {
  final String fecha;
  final String sku;
  final String producto;
  final String sucursal;
  final num cantidad;
  final String tipo; // Movidos 만: Ingreso/Egreso
  StockMovRow.fromJson(Map<String, dynamic> j)
      : fecha = (j['fecha'] ?? '').toString(),
        sku = (j['sku'] ?? '').toString(),
        producto = (j['producto'] ?? '').toString(),
        sucursal = (j['sucursal'] ?? '').toString(),
        cantidad = asNum(j['cantidad']),
        tipo = (j['tipo'] ?? '').toString();
}

class ReservadoRow {
  final String fecha;
  final String cliente;
  final String vendedor;
  final num monto;
  ReservadoRow.fromJson(Map<String, dynamic> j)
      : fecha = (j['fecha'] ?? '').toString(),
        cliente = (j['cliente'] ?? '').toString(),
        vendedor = (j['vendedor'] ?? '').toString(),
        monto = asNum(j['monto']);
}

// ── 리포지토리 ──

final reportesRepositoryProvider = Provider<ReportesRepository>((ref) {
  return ReportesRepository(ref.read(dioClientProvider));
});

class ReportesRepository {
  final Dio _dio;
  ReportesRepository(this._dio);

  Map<String, dynamic> _q(int storeId, ReportRange? r) => {
        'storeId': storeId,
        if (r != null) 'startDate': r.start,
        if (r != null) 'endDate': r.end,
      };

  Future<List<T>> _list<T>(
    String slug,
    Map<String, dynamic> query,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/reports/$slug',
      queryParameters: query,
    );
    final list = (res.data?['data'] as List?) ?? const [];

    return list.map((e) => parse(e as Map<String, dynamic>)).toList();
  }

  Future<List<BreveVentaRow>> getBreveVenta(int s, ReportRange r) =>
      _list('breve-venta-report', _q(s, r), BreveVentaRow.fromJson);
  Future<List<SalesRow>> getSales(int s, ReportRange r) =>
      _list('sales-report', _q(s, r), SalesRow.fromJson);
  Future<List<VendedorRow>> getVendedor(int s, ReportRange r) =>
      _list('vendedor-report', _q(s, r), VendedorRow.fromJson);
  Future<List<GastoRow>> getGastos(int s, ReportRange r) =>
      _list('gasto-report', _q(s, r), GastoRow.fromJson);
  Future<List<StockRow>> getStocks(int s) =>
      _list('stocks-report', _q(s, null), StockRow.fromJson);
  Future<List<AlertaRow>> getAlertas(int s) =>
      _list('alertas-report', _q(s, null), AlertaRow.fromJson);
  Future<List<ChequeRow>> getCheques(int s, ReportRange r) =>
      _list('cheque-estado-report', _q(s, r), ChequeRow.fromJson);
  Future<List<ProductoRow>> getProductos(int s, ReportRange r) =>
      _list('products-report', _q(s, r), ProductoRow.fromJson);
  Future<List<SaleDocRow>> getFallados(int s, ReportRange r) =>
      _list('fallados-report', _q(s, r), SaleDocRow.fromJson);
  Future<List<SaleDocRow>> getCorregido(int s, ReportRange r) =>
      _list('corregido-report', _q(s, r), SaleDocRow.fromJson);
  Future<List<SaleDocRow>> getFacturacion(int s, ReportRange r) =>
      _list('facturacion-report', _q(s, r), SaleDocRow.fromJson);
  Future<List<ClienteCreditoRow>> getClientesCredito(int s) =>
      _list('clientes-credito-report', _q(s, null), ClienteCreditoRow.fromJson);
  Future<List<StockMovRow>> getIngreso(int s, ReportRange r) =>
      _list('ingreso-report', _q(s, r), StockMovRow.fromJson);
  Future<List<StockMovRow>> getMovidos(int s, ReportRange r) =>
      _list('movidos-report', _q(s, r), StockMovRow.fromJson);
  Future<List<ReservadoRow>> getReservado(int s, ReportRange r) =>
      _list('reservado-report', _q(s, r), ReservadoRow.fromJson);

  Future<ProvinciaResult> getProvincia(int s, ReportRange r) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/reports/provincia-dashboard',
      queryParameters: {..._q(s, r), 'limit': 50},
    );
    final data = res.data ?? const {};
    final rows = ((data['rows'] as List?) ?? const [])
        .map((e) => ProvinciaRow.fromJson(e as Map<String, dynamic>))
        .toList();
    final total = asNum((data['totals'] as Map?)?['amount']);

    return ProvinciaResult(total, rows);
  }
}

// ── Providers ──

int _requireStore(Ref ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) throw Exception('Sin storeId');

  return storeId;
}

final breveVentaProvider = FutureProvider.autoDispose
    .family<List<BreveVentaRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getBreveVenta(_requireStore(ref), r));
final salesReportProvider = FutureProvider.autoDispose
    .family<List<SalesRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getSales(_requireStore(ref), r));
final vendedorReportProvider = FutureProvider.autoDispose
    .family<List<VendedorRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getVendedor(_requireStore(ref), r));
final gastoReportProvider = FutureProvider.autoDispose
    .family<List<GastoRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getGastos(_requireStore(ref), r));
final stocksReportProvider = FutureProvider.autoDispose<List<StockRow>>((ref) =>
    ref.read(reportesRepositoryProvider).getStocks(_requireStore(ref)));
final alertasReportProvider = FutureProvider.autoDispose<List<AlertaRow>>((ref) =>
    ref.read(reportesRepositoryProvider).getAlertas(_requireStore(ref)));
final chequesReportProvider = FutureProvider.autoDispose
    .family<List<ChequeRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getCheques(_requireStore(ref), r));
final productosReportProvider = FutureProvider.autoDispose
    .family<List<ProductoRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getProductos(_requireStore(ref), r));
final falladosReportProvider = FutureProvider.autoDispose
    .family<List<SaleDocRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getFallados(_requireStore(ref), r));
final corregidoReportProvider = FutureProvider.autoDispose
    .family<List<SaleDocRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getCorregido(_requireStore(ref), r));
final facturacionReportProvider = FutureProvider.autoDispose
    .family<List<SaleDocRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getFacturacion(_requireStore(ref), r));
final clientesCreditoReportProvider =
    FutureProvider.autoDispose<List<ClienteCreditoRow>>((ref) =>
        ref.read(reportesRepositoryProvider).getClientesCredito(_requireStore(ref)));
final ingresoReportProvider = FutureProvider.autoDispose
    .family<List<StockMovRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getIngreso(_requireStore(ref), r));
final movidosReportProvider = FutureProvider.autoDispose
    .family<List<StockMovRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getMovidos(_requireStore(ref), r));
final reservadoReportProvider = FutureProvider.autoDispose
    .family<List<ReservadoRow>, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getReservado(_requireStore(ref), r));
final provinciaReportProvider = FutureProvider.autoDispose
    .family<ProvinciaResult, ReportRange>((ref, r) =>
        ref.read(reportesRepositoryProvider).getProvincia(_requireStore(ref), r));
