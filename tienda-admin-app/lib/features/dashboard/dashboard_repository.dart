import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../shared/format.dart';

class SalesSummary {
  final num ventasHoy;
  final num ventasChange;
  final num ingresoHoy;
  final num ingresoChange;
  final num gastosHoy;
  final num gastosChange;
  final num descuentosHoy;
  final int facturasPendientes;
  final int totalClientes;
  final List<({String day, num total})> ventasSemana;

  SalesSummary.fromJson(Map<String, dynamic> j)
      : ventasHoy = asNum(j['ventasHoy']),
        ventasChange = asNum(j['ventasChange']),
        ingresoHoy = asNum(j['ingresoHoy']),
        ingresoChange = asNum(j['ingresoChange']),
        gastosHoy = asNum(j['gastosHoy']),
        gastosChange = asNum(j['gastosChange']),
        descuentosHoy = asNum(j['descuentosHoy']),
        facturasPendientes = asInt(j['facturasPendientes']),
        totalClientes = asInt(j['totalClientes']),
        ventasSemana = ((j['ventasSemana'] as List?) ?? const [])
            .map((e) => (
                  day: (e['day'] ?? '').toString(),
                  total: asNum(e['total']),
                ))
            .toList();
}

class LastSale {
  final int id;
  final num totalAmount;
  final String saleDate;
  final String? clientName;

  LastSale.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        totalAmount = asNum(j['totalAmount']),
        saleDate = (j['saleDate'] ?? '').toString(),
        clientName = (j['client'] is Map)
            ? j['client']['fullname'] as String?
            : null;
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.read(dioClientProvider));
});

class DashboardRepository {
  final Dio _dio;

  DashboardRepository(this._dio);

  // store 는 토큰에서 서버가 스코핑 → 파라미터 불필요.
  Future<SalesSummary> getSummary() async {
    final res =
        await _dio.get<Map<String, dynamic>>('/dashboards/sales/summary');

    return SalesSummary.fromJson(res.data ?? const {});
  }

  Future<List<LastSale>> getLastSales() async {
    final res =
        await _dio.get<List<dynamic>>('/dashboards/sales/last-sales');

    return (res.data ?? const [])
        .map((e) => LastSale.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

final salesSummaryProvider =
    FutureProvider.autoDispose<SalesSummary>((ref) {
  return ref.read(dashboardRepositoryProvider).getSummary();
});

final lastSalesProvider =
    FutureProvider.autoDispose<List<LastSale>>((ref) {
  return ref.read(dashboardRepositoryProvider).getLastSales();
});
