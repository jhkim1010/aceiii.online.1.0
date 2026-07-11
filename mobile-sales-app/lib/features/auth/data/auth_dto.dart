// 인증 데이터 전송 모델 — POST /mobile/auth/login, GET /mobile/me 계약 (Wave 1)
import 'package:flutter/foundation.dart';

// 로그인 요청 body
@immutable
class MobileLoginRequest {
  final String usuario;
  final String pin;
  final String deviceFingerprint;
  // FCM 미사용(Phase 37 MVP 연기) — nullable/optional 유지
  final String? deviceToken;

  const MobileLoginRequest({
    required this.usuario,
    required this.pin,
    required this.deviceFingerprint,
    this.deviceToken,
  });

  Map<String, dynamic> toJson() => {
        'usuario': usuario,
        'pin': pin,
        'deviceFingerprint': deviceFingerprint,
        if (deviceToken != null) 'deviceToken': deviceToken,
      };
}

// scope 모드 (백엔드 user.scopeMode)
enum ScopeMode {
  vendedor,
  revendedor,
  unknown;

  static ScopeMode fromString(String? value) {
    switch (value) {
      case 'vendedor':
        return ScopeMode.vendedor;
      case 'revendedor':
        return ScopeMode.revendedor;
      default:
        return ScopeMode.unknown;
    }
  }
}

// /mobile/me + login 응답의 user 객체
@immutable
class MobileUser {
  final int id;
  final String name;
  final String role;
  final ScopeMode scopeMode;
  final List<int> scopeBranchIds;
  final List<int> scopeStoreIds;
  final int? storeId;
  final String? storeName;
  final String? branchName;
  // 출근 게이트(37-06 /mobile/me) — 열린 seller_attendance 세션 여부 + 시작시각.
  // clockedIn=false 면 홈이 Catálogo/스캐너/판매를 잠그고 fichaje 만 노출.
  final bool clockedIn;
  final DateTime? openSince;

  const MobileUser({
    required this.id,
    required this.name,
    required this.role,
    required this.scopeMode,
    required this.scopeBranchIds,
    required this.scopeStoreIds,
    this.storeId,
    this.storeName,
    this.branchName,
    this.clockedIn = false,
    this.openSince,
  });

  factory MobileUser.fromJson(Map<String, dynamic> json) => MobileUser(
        id: (json['id'] as num).toInt(),
        name: json['name'] as String? ?? '',
        role: json['role'] as String? ?? '',
        scopeMode: ScopeMode.fromString(json['scopeMode'] as String?),
        scopeBranchIds: _intList(json['scopeBranchIds']),
        scopeStoreIds: _intList(json['scopeStoreIds']),
        storeId: (json['storeId'] as num?)?.toInt(),
        storeName: json['storeName'] as String?,
        branchName: json['branchName'] as String?,
        clockedIn: json['clockedIn'] as bool? ?? false,
        openSince: _parseDate(json['openSince']),
      );

  // 안전한 ISO 날짜 파싱 (null / 형식 오류 방어)
  static DateTime? _parseDate(dynamic value) {
    if (value is String && value.isNotEmpty) {
      return DateTime.tryParse(value);
    }

    return null;
  }

  // 안전한 int 리스트 파싱 (null / 혼합 타입 방어)
  static List<int> _intList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Object>()
          .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
          .whereType<int>()
          .toList();
    }

    return const [];
  }
}

// 로그인 성공 응답 (accessToken + mobileSessionToken + user)
@immutable
class MobileLoginResponse {
  final String accessToken;
  final String mobileSessionToken;
  final MobileUser user;

  const MobileLoginResponse({
    required this.accessToken,
    required this.mobileSessionToken,
    required this.user,
  });

  factory MobileLoginResponse.fromJson(Map<String, dynamic> json) => MobileLoginResponse(
        accessToken: json['accessToken'] as String,
        mobileSessionToken: json['mobileSessionToken'] as String,
        user: MobileUser.fromJson(json['user'] as Map<String, dynamic>),
      );
}
