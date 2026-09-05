// [2026-09-05] 전자 영수증(fac. electrónica)을 쓰는 매장과 인증서 갱신 시한.
//
// ★ 경보 판정은 **서버가 한다** (`estado` · `porRenovar`). 앱이 `daysLeft` 를 보고
//   다시 판정하면 두 곳이 갈라져 「목록엔 빨간데 배지는 0」 이 된다.
//   서버의 `necesitaAtencion` 하나가 유일한 출처다.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';

int _asInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

/// 서버의 `EstadoCertificado` 와 같은 값. 순서가 급한 순이다.
enum EstadoCert { vencido, porRenovar, ilegible, sinCertificado, ok }

EstadoCert _estado(String raw) {
  switch (raw) {
    case 'vencido':
      return EstadoCert.vencido;
    case 'por_renovar':
      return EstadoCert.porRenovar;
    case 'ilegible':
      return EstadoCert.ilegible;
    case 'sin_certificado':
      return EstadoCert.sinCertificado;
    default:
      return EstadoCert.ok;
  }
}

class FacElectronicaItem {
  final int storeId;
  final String storeName;
  final int puntoVenta;
  final String? cuit;
  final String? slug;
  final String? invoiceType;
  final String? razonSocial;
  final String? provider;

  /// true = 운영(ARCA 유효) · false = 홈올로가시온(전표가 세무상 무효)
  final bool produccion;
  final bool autoIssue;

  final String? validTo;
  final int? daysLeft;
  final String? certError;
  final EstadoCert estado;

  final int vouchers;
  final String? ultimaEmision;

  FacElectronicaItem.fromJson(Map<String, dynamic> j)
      : storeId = _asInt(j['storeId']),
        storeName = (j['storeName'] ?? '').toString(),
        puntoVenta = _asInt(j['puntoVenta']),
        cuit = j['cuit'] as String?,
        slug = j['slug'] as String?,
        invoiceType = j['invoiceType'] as String?,
        razonSocial = j['razonSocial'] as String?,
        provider = j['provider'] as String?,
        produccion = j['produccion'] == true,
        autoIssue = j['autoIssue'] == true,
        validTo = j['validTo'] as String?,
        daysLeft = j['daysLeft'] == null ? null : _asInt(j['daysLeft']),
        certError = j['certError'] as String?,
        estado = _estado((j['estado'] ?? 'ok').toString()),
        vouchers = _asInt(j['vouchers']),
        ultimaEmision = j['ultimaEmision'] as String?;
}

class FacElectronicaResult {
  final String scannedAt;
  final String certsDir;
  final String? dirError;
  final int diasAviso;
  final int total;

  /// 서버가 센 「지금 손을 써야 하는」 수. **앱의 배지는 이 값 하나다.**
  final int porRenovar;
  final List<FacElectronicaItem> items;

  FacElectronicaResult.fromJson(Map<String, dynamic> j)
      : scannedAt = (j['scannedAt'] ?? '').toString(),
        certsDir = (j['certsDir'] ?? '').toString(),
        dirError = j['dirError'] as String?,
        diasAviso = _asInt(j['diasAviso']),
        total = _asInt(j['total']),
        porRenovar = _asInt(j['porRenovar']),
        items = ((j['items'] ?? []) as List)
            .map((e) => FacElectronicaItem.fromJson(e as Map<String, dynamic>))
            .toList();
}

final facturacionRepositoryProvider = Provider<FacturacionRepository>((ref) {
  return FacturacionRepository(ref.read(dioClientProvider));
});

class FacturacionRepository {
  final Dio _dio;

  FacturacionRepository(this._dio);

  Future<FacElectronicaResult> getFacElectronica() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/afip/facturacion-electronica',
    );

    return FacElectronicaResult.fromJson(res.data ?? {});
  }
}

final facElectronicaProvider =
    FutureProvider.autoDispose<FacElectronicaResult>(
  (ref) => ref.read(facturacionRepositoryProvider).getFacElectronica(),
);
