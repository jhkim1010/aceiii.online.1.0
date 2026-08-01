// 인증 데이터 전송 모델 — 로그인 응답 파싱
import '../.././../shared/models/store_info.dart';

// 인증 성공 후 유지되는 상태
class AuthState {
  final String token;
  final String phone;
  final List<StoreInfo> stores;

  AuthState({
    required this.token,
    required this.phone,
    required this.stores,
  });

  // 로그인 응답 JSON으로 AuthState 생성 — requiresStoreSelection 응답은 호출 전에
  // 별도 분기로 처리해야 한다 (json['token'] 이 없어 예외가 난다)
  factory AuthState.fromLoginResponse(Map<String, dynamic> json, String phone) => AuthState(
        token: json['token'] as String,
        phone: phone,
        stores: (json['stores'] as List<dynamic>)
            .map((s) => StoreInfo.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}

// 동일 PIN 이 2개 이상 매장에서 통과했을 때의 로그인 응답 — 토큰 미발급 (R3/CR-03)
class StoreSelectionRequired {
  final List<StoreInfo> stores;

  StoreSelectionRequired({required this.stores});

  // requiresStoreSelection=true 응답 JSON으로 후보 매장 목록 파싱
  factory StoreSelectionRequired.fromJson(Map<String, dynamic> json) => StoreSelectionRequired(
        stores: (json['stores'] as List<dynamic>)
            .map((s) => StoreInfo.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
