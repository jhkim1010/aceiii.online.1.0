// 출퇴근(Fichaje) 데이터 전송 모델 — POST /attendance/punch 계약 (37-06).
// 신뢰 경계: /m/fichaje QR 페이로드는 untrusted — s/b/d/t 만 추출, 백엔드가 HMAC 재검증(T-37-31).
import 'package:flutter/foundation.dart';

// 스캔한 caja 일일 QR 페이로드 (`/m/fichaje?s=&b=&d=&t=`).
@immutable
class FichajeQr {
  final int s; // storeId
  final int b; // branchId
  final String d; // yyyy-mm-dd (매장 TZ 날짜)
  final String t; // HMAC 토큰

  const FichajeQr({
    required this.s,
    required this.b,
    required this.d,
    required this.t,
  });

  // POST /attendance/punch body
  Map<String, dynamic> toJson() => {
        's': s,
        'b': b,
        'd': d,
        't': t,
      };
}

// punch 결과 — role 로 분기.
// vendedor: action 'in'|'out' (+ branchName, todayWorkedSeconds)
// revendedor: action 'store_authorized' (+ storeId, storeName)
@immutable
class PunchResult {
  final String action;
  final String? at; // ISO 타임스탬프 (entrada/salida 순간)
  final String? branchName;
  final int? todayWorkedSeconds;
  final int? storeId;
  final String? storeName;

  const PunchResult({
    required this.action,
    this.at,
    this.branchName,
    this.todayWorkedSeconds,
    this.storeId,
    this.storeName,
  });

  bool get isIn => action == 'in';
  bool get isOut => action == 'out';
  bool get isStoreAuthorized => action == 'store_authorized';

  factory PunchResult.fromJson(Map<String, dynamic> json) => PunchResult(
        action: json['action'] as String? ?? '',
        at: json['at'] as String?,
        branchName: json['branchName'] as String?,
        todayWorkedSeconds: (json['todayWorkedSeconds'] as num?)?.toInt(),
        storeId: (json['storeId'] as num?)?.toInt(),
        storeName: json['storeName'] as String?,
      );
}
