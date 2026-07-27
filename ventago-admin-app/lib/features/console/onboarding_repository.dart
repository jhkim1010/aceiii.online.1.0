import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';

// 신규 매장 가입 승인 (superadmin 전용).
//
// 흐름: 가입 폼 → OTP/DNI 검증 → status='review_pending' → **여기서 승인** → 매장+오너 계정 생성.
// 승인 전에는 계정이 존재하지 않으므로 신청자는 로그인할 수 없다(로그인 시 USER_NOT_FOUND).
// 백엔드: GET /onboarding/admin/pending, GET :id/dni/:side, PATCH :id/approve, PATCH :id/reject

int _asInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

class PendingRegistration {
  final int id;
  final String companyName;
  final String? aliasName;
  final String companyCuit;
  final String companyAddress;
  final String ownerName;
  final String? username;
  final String email;
  final String phone;
  final bool emailVerified;
  final bool phoneVerified;
  final bool hasDniFront;
  final bool hasDniBack;
  final DateTime? createdAt;

  PendingRegistration.fromJson(Map<String, dynamic> j)
      : id = _asInt(j['id']),
        companyName = (j['companyName'] ?? '-').toString(),
        aliasName = j['aliasName'] as String?,
        companyCuit = (j['companyCuit'] ?? '-').toString(),
        companyAddress = (j['companyAddress'] ?? '-').toString(),
        ownerName = (j['ownerName'] ?? '-').toString(),
        username = j['username'] as String?,
        email = (j['email'] ?? '-').toString(),
        phone = (j['phone'] ?? '-').toString(),
        emailVerified = j['emailVerified'] == true,
        phoneVerified = j['phoneVerified'] == true,
        hasDniFront = j['hasDniFront'] == true,
        hasDniBack = j['hasDniBack'] == true,
        createdAt = DateTime.tryParse('${j['createdAt']}');
}

class OnboardingRepository {
  final Dio _dio;

  OnboardingRepository(this._dio);

  Future<List<PendingRegistration>> getPending() async {
    final res = await _dio.get('/onboarding/admin/pending');
    final data = res.data;
    final list = data is List ? data : (data['data'] as List? ?? const []);

    return list
        .map((e) => PendingRegistration.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // DNI 이미지는 JWT 가 필요해 Image.network 로 못 띄운다 → bytes 로 받아 Image.memory.
  Future<Uint8List> getDni(int id, String side) async {
    final res = await _dio.get<List<int>>(
      '/onboarding/admin/$id/dni/$side',
      options: Options(responseType: ResponseType.bytes),
    );

    return Uint8List.fromList(res.data ?? const []);
  }

  // 승인 → 매장 + 오너 계정 생성. 반환 storeId 로 결과를 안내한다.
  Future<int> approve(int id) async {
    final res = await _dio.patch('/onboarding/admin/$id/approve');
    final data = res.data;

    return data is Map ? _asInt(data['storeId']) : 0;
  }

  Future<void> reject(int id, String reason) async {
    await _dio.patch(
      '/onboarding/admin/$id/reject',
      data: {'reason': reason},
    );
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(ref.read(dioClientProvider)),
);

final pendingRegistrationsProvider =
    FutureProvider.autoDispose<List<PendingRegistration>>((ref) {
  return ref.read(onboardingRepositoryProvider).getPending();
});
