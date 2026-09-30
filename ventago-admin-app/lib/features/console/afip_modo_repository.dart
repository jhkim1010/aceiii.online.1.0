// [2026-09-30] 매장 AFIP 모드 전환 — `ws`(cool-invoice 게이트웨이) ↔ `soap`(ARCA 직접).
//
// 웹 Admin › Tiendas › Modo AFIP (`AfipModoCard.tsx`) 와 **같은 API** 를 쓴다.
// 판정(차단·경고·적용 가능 여부)은 전부 서버가 한다 — 앱은 그대로 보여 줄 뿐이다.
//
// ★ 적용은 미리보기에서 받은 지문(`estadoVisto`)을 되돌려 보내야 된다.
//   그 사이 누가 설정을 바꿨으면 서버가 거절한다.

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';

int _asInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

List<String> _strs(dynamic v) =>
    ((v as List?) ?? const []).map((e) => '$e').toList();

class AfipModo {
  final String provider;
  final bool production;

  AfipModo.fromJson(Map<String, dynamic> j)
      : provider = (j['provider'] ?? 'ws').toString(),
        production = j['production'] == true;

  bool same(AfipModo o) => provider == o.provider && production == o.production;

  String get label => provider == 'soap'
      ? 'ARCA directo · ${production ? 'Producción' : 'Homologación'}'
      : 'Gateway cool-invoice (siempre producción)';
}

class AfipEmisor {
  final int issuerId;
  final String cuit;
  final int puntoVenta;
  final String? entornoActual;
  final List<String> bloqueos;
  final List<String> advertencias;

  AfipEmisor.fromJson(Map<String, dynamic> j)
      : issuerId = _asInt(j['issuerId']),
        cuit = (j['cuit'] ?? '').toString(),
        puntoVenta = _asInt(j['puntoVenta']),
        entornoActual = j['entornoActual'] as String?,
        bloqueos = _strs(j['bloqueos']),
        advertencias = _strs(j['advertencias']);
}

class AfipModoPreview {
  final int storeId;
  final AfipModo actual;
  final AfipModo destino;
  final List<AfipEmisor> emisores;
  final List<String> bloqueos;
  final List<String> advertencias;
  final bool puedeAplicar;
  final String estadoVisto;

  AfipModoPreview.fromJson(Map<String, dynamic> j)
      : storeId = _asInt(j['storeId']),
        actual = AfipModo.fromJson((j['actual'] ?? {}) as Map<String, dynamic>),
        destino = AfipModo.fromJson((j['destino'] ?? {}) as Map<String, dynamic>),
        emisores = ((j['emisores'] ?? []) as List)
            .map((e) => AfipEmisor.fromJson(e as Map<String, dynamic>))
            .toList(),
        bloqueos = _strs(j['bloqueos']),
        advertencias = _strs(j['advertencias']),
        puedeAplicar = j['puedeAplicar'] == true,
        estadoVisto = (j['estadoVisto'] ?? '').toString();

  bool get sinCambio => actual.same(destino);
}

final afipModoRepositoryProvider = Provider<AfipModoRepository>((ref) {
  return AfipModoRepository(ref.read(dioClientProvider));
});

class AfipModoRepository {
  final Dio _dio;

  AfipModoRepository(this._dio);

  Future<AfipModoPreview> preview(int storeId, String destino, String entorno) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/afip/provider-switch/$storeId/preview',
      queryParameters: {'destino': destino, 'entorno': entorno},
    );

    return AfipModoPreview.fromJson(res.data ?? {});
  }

  Future<AfipModoPreview> aplicar(
    int storeId, {
    required String destino,
    required String entorno,
    required String estadoVisto,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/afip/provider-switch/$storeId',
      data: {'destino': destino, 'entorno': entorno, 'estadoVisto': estadoVisto},
    );

    return AfipModoPreview.fromJson(res.data ?? {});
  }
}

/// 서버 오류 메시지를 사람이 읽을 문장으로. (Nest 는 message 가 문자열 또는 배열)
String afipErrorMessage(Object e, String fallback) {
  if (e is DioException) {
    final m = (e.response?.data is Map) ? (e.response!.data as Map)['message'] : null;
    if (m is String && m.isNotEmpty) return m;
    if (m is List && m.isNotEmpty) return m.join(' ');
  }

  return fallback;
}
