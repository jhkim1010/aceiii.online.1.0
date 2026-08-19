import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';

// 관리비 수납 — 검토 대기 comprobante 와 월별 청구 현황.
//
// ★ 웹(`/admin/cobranzas`)과 **같은 엔드포인트**를 쓴다. 앱이 자기 계산이나 자기
//   판정을 갖게 되면 두 화면이 서로 다른 답을 보여주고, 그러면 어느 쪽이 맞는지
//   아무도 모른다 — 청구액 계산이 백엔드에서 네 곳으로 갈라졌던 것과 같은 사고다.
//   금액 비교·중복 참조 경고도 서버가 판정해서 내려준 값을 그대로 쓴다.

// PG numeric 은 JSON 에서 문자열("34500.00")로 내려올 수 있다.
int _asInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

num _asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

/// 검토 대기 중인 제출 한 건.
class CobranzaPendiente {
  final int submissionId;
  final int storeId;
  final String storeName;
  final int invoiceId;
  final String billingPeriod;

  final num facturado;
  final num yaPagado;
  final num saldoAntes;
  final num declarado;

  /// 서버가 판정한 값 — 앱에서 다시 계산하지 않는다.
  final bool coincide;
  final num diferencia;

  final String depositDate;
  final String method;
  final String? bank;
  final String? reference;
  final String? payerName;
  final String? fileKey;
  final DateTime? createdAt;

  /// 같은 참조번호가 다른 제출에도 있다 — 가장 흔한 조용한 사고다.
  final bool referenciaRepetida;

  CobranzaPendiente.fromJson(Map<String, dynamic> j)
      : submissionId = _asInt(j['submissionId']),
        storeId = _asInt(j['storeId']),
        storeName = (j['storeName'] ?? '#${j['storeId']}').toString(),
        invoiceId = _asInt(j['invoiceId']),
        billingPeriod = (j['billingPeriod'] ?? '').toString(),
        facturado = _asNum(j['facturado']),
        yaPagado = _asNum(j['yaPagado']),
        saldoAntes = _asNum(j['saldoAntes']),
        declarado = _asNum(j['declarado']),
        coincide = j['coincide'] == true,
        diferencia = _asNum(j['diferencia']),
        depositDate = (j['depositDate'] ?? '').toString(),
        method = (j['method'] ?? '').toString(),
        bank = j['bank'] as String?,
        reference = j['reference'] as String?,
        payerName = j['payerName'] as String?,
        fileKey = j['fileKey'] as String?,
        createdAt = j['createdAt'] == null
            ? null
            : DateTime.tryParse('${j['createdAt']}'),
        referenciaRepetida = j['referenciaRepetida'] == true;
}

/// 월별 청구서 한 건.
class FacturaMes {
  final int id;
  final int storeId;
  final String? receiverName;
  final String billingPeriod;
  final String status;
  final num grandTotal;
  final String currency;
  final String? fiscalVoucherNumber;

  FacturaMes.fromJson(Map<String, dynamic> j)
      : id = _asInt(j['id']),
        storeId = _asInt(j['storeId']),
        receiverName = j['receiverName'] as String?,
        billingPeriod = (j['billingPeriod'] ?? '').toString(),
        status = (j['status'] ?? 'draft').toString(),
        grandTotal = _asNum(j['grandTotal']),
        currency = (j['currency'] ?? 'ARS').toString(),
        fiscalVoucherNumber = j['fiscalVoucherNumber'] as String?;
}

// ── 리포지토리 ──

final cobranzasRepositoryProvider = Provider<CobranzasRepository>((ref) {
  return CobranzasRepository(ref.read(dioClientProvider));
});

class CobranzasRepository {
  final Dio _dio;

  CobranzasRepository(this._dio);

  Future<List<CobranzaPendiente>> getPendientes() async {
    final res = await _dio.get<List<dynamic>>('/billing/cobranzas/pendientes');

    return (res.data ?? [])
        .map((e) => CobranzaPendiente.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<FacturaMes>> getFacturas({String? periodo}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/billing/facturas',
      queryParameters: periodo == null ? null : {'periodo': periodo},
    );
    final list = (res.data?['facturas'] as List?) ?? const [];

    return list
        .map((e) => FacturaMes.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// ★ **입금 확인**이지 영수증 발급이 아니다. 통장을 보고 누른다.
  Future<void> confirmarAcreditacion(int submissionId, {num? amount}) async {
    await _dio.post<dynamic>(
      '/billing/cobranzas/$submissionId/confirmar',
      data: amount == null ? <String, dynamic>{} : {'amount': amount},
    );
  }

  /// 반려 — 사유 없이는 서버가 거부한다(매장이 무엇을 고쳐야 할지 알아야 한다).
  Future<void> rechazar(int submissionId, String motivo) async {
    await _dio.post<dynamic>(
      '/billing/cobranzas/$submissionId/rechazar',
      data: {'motivo': motivo},
    );
  }

  /// 초안 생성·갱신 — 발행하지 않는다. 아무것도 청구되지 않는다.
  Future<Map<String, dynamic>> generarBorradores({String? periodo}) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/billing/facturas/generar',
      data: periodo == null ? <String, dynamic>{} : {'periodo': periodo},
    );

    return res.data ?? <String, dynamic>{};
  }

  /// comprobante 원본을 바이트로 가져온다.
  ///
  /// ★ 공개 MinIO URL 이 아니라 **인증 경로**로만 받는다. comprobante 에는 계좌번호·
  ///   금액·송금자 이름이 있어서, 파일명만 알면 열리는 자리에 두면 안 된다.
  Future<Uint8List> getArchivo(int submissionId) async {
    final res = await _dio.get<List<int>>(
      '/billing/comprobantes/$submissionId/archivo',
      options: Options(responseType: ResponseType.bytes),
    );

    return Uint8List.fromList(res.data ?? const []);
  }
}

// ── FutureProviders ──

final cobranzasPendientesProvider =
    FutureProvider.autoDispose<List<CobranzaPendiente>>((ref) {
  return ref.read(cobranzasRepositoryProvider).getPendientes();
});

final facturasMesProvider =
    FutureProvider.autoDispose<List<FacturaMes>>((ref) {
  return ref.read(cobranzasRepositoryProvider).getFacturas();
});
