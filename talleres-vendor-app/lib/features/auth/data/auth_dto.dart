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

  // 로그인 응답 JSON으로 AuthState 생성
  factory AuthState.fromLoginResponse(Map<String, dynamic> json, String phone) => AuthState(
        token: json['token'] as String,
        phone: phone,
        stores: (json['stores'] as List<dynamic>)
            .map((s) => StoreInfo.fromJson(s as Map<String, dynamic>))
            .toList(),
      );
}
