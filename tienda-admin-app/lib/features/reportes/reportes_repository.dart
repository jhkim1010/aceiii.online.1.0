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
  final String seller;
  final num totalAmount; // DECIMAL → 문자열일 수 있음 → asNum
  final String status;
  final String paymentMethods;
  final int itemsCount;
  SalesRow.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        saleDate = (j['saleDate'] ?? '').toString(),
        client = (j['client'] ?? '').toString(),
        seller = (j['seller'] ?? '').toString(),
        totalAmount = asNum(j['totalAmount']),
        status = (j['status'] ?? '').toString(),
        paymentMethods = (j['paymentMethods'] ?? '').toString(),
        itemsCount = asInt(j['itemsCount']);
}

class VendedorRow {
  final int sellerId;
  final String sellerName;
  final int totalSales;
  final num totalAmount;
  VendedorRow.fromJson(Map<String, dynamic> j)
      : sellerId = asInt(j['sellerId']),
        sellerName = (j['sellerName'] ?? 'Sin asignar').toString(),
        totalSales = asInt(j['totalSales']),
        totalAmount = asNum(j['totalAmount']);
}

// ── 리포지토리 ──

final reportesRepositoryProvider = Provider<ReportesRepository>((ref) {
  return ReportesRepository(ref.read(dioClientProvider));
});

class ReportesRepository {
  final Dio _dio;
  ReportesRepository(this._dio);

  // 이 3개 리포트는 storeId 를 쿼리로 명시해야 매장 스코프가 걸림(생략 시 전체).
  Map<String, dynamic> _q(int storeId, ReportRange r) => {
        'storeId': storeId,
        'startDate': r.start,
        'endDate': r.end,
      };

  Future<List<T>> _list<T>(
    String slug,
    int storeId,
    ReportRange r,
    T Function(Map<String, dynamic>) parse,
  ) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/reports/$slug',
      queryParameters: _q(storeId, r),
    );
    final list = (res.data?['data'] as List?) ?? const [];

    return list.map((e) => parse(e as Map<String, dynamic>)).toList();
  }

  Future<List<BreveVentaRow>> getBreveVenta(int storeId, ReportRange r) =>
      _list('breve-venta-report', storeId, r, BreveVentaRow.fromJson);

  Future<List<SalesRow>> getSales(int storeId, ReportRange r) =>
      _list('sales-report', storeId, r, SalesRow.fromJson);

  Future<List<VendedorRow>> getVendedor(int storeId, ReportRange r) =>
      _list('vendedor-report', storeId, r, VendedorRow.fromJson);
}

// ── Providers (기간별 family) ──

final breveVentaProvider = FutureProvider.autoDispose
    .family<List<BreveVentaRow>, ReportRange>((ref, r) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) throw Exception('Sin storeId');

  return ref.read(reportesRepositoryProvider).getBreveVenta(storeId, r);
});

final salesReportProvider = FutureProvider.autoDispose
    .family<List<SalesRow>, ReportRange>((ref, r) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) throw Exception('Sin storeId');

  return ref.read(reportesRepositoryProvider).getSales(storeId, r);
});

final vendedorReportProvider = FutureProvider.autoDispose
    .family<List<VendedorRow>, ReportRange>((ref, r) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) throw Exception('Sin storeId');

  return ref.read(reportesRepositoryProvider).getVendedor(storeId, r);
});
