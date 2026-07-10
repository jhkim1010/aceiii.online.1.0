import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';

// ── 모델 ──

class SessionRow {
  final int userId;
  final String name;
  final String platform;
  final String status;
  final String? storeName;
  final String? branchName;
  final String? publicIp;
  final int idleSecs;

  SessionRow.fromJson(Map<String, dynamic> j)
      : userId = j['userId'] as int,
        name = [j['name'], j['lastName']].where((e) => e != null && '$e'.isNotEmpty).join(' ').trim().isEmpty
            ? (j['username'] ?? j['email'] ?? '#${j['userId']}').toString()
            : [j['name'], j['lastName']].where((e) => e != null).join(' '),
        platform = (j['platform'] ?? 'web').toString(),
        status = (j['status'] ?? 'idle').toString(),
        storeName = j['storeName'] as String?,
        branchName = j['branchName'] as String?,
        publicIp = j['publicIp'] as String?,
        idleSecs = (j['idleSecs'] ?? 0) as int;
}

class Tenant {
  final int storeId;
  final String storeName;
  final int branches;
  final int terminals;
  final int salesToday;
  final int salesMonth;
  final num revenueMonth;
  final num expectedFee;
  final String currency;
  final bool subscriptionEnabled;
  final int errors24h;

  Tenant.fromJson(Map<String, dynamic> j)
      : storeId = j['storeId'] as int,
        storeName = (j['storeName'] ?? '#${j['storeId']}').toString(),
        branches = (j['branches'] ?? 0) as int,
        terminals = (j['terminals'] ?? 0) as int,
        salesToday = (j['salesToday'] ?? 0) as int,
        salesMonth = (j['salesMonth'] ?? 0) as int,
        revenueMonth = (j['revenueMonth'] ?? 0) as num,
        expectedFee = (j['expectedFee'] ?? 0) as num,
        currency = (j['currency'] ?? 'ARS').toString(),
        subscriptionEnabled = (j['subscriptionEnabled'] ?? false) as bool,
        errors24h = (j['errors24h'] ?? 0) as int;
}

class NoticeCampaign {
  final String campaignId;
  final String level;
  final String title;
  final int total;
  final int read;
  final String createdAt;

  NoticeCampaign.fromJson(Map<String, dynamic> j)
      : campaignId = (j['campaignId'] ?? '').toString(),
        level = (j['level'] ?? 'info').toString(),
        title = (j['title'] ?? '').toString(),
        total = (j['total'] ?? 0) as int,
        read = (j['read'] ?? 0) as int,
        createdAt = (j['createdAt'] ?? '').toString();
}

// ── 리포지토리 ──

final consoleRepositoryProvider = Provider<ConsoleRepository>((ref) {
  return ConsoleRepository(ref.read(dioClientProvider));
});

class ConsoleRepository {
  final Dio _dio;

  ConsoleRepository(this._dio);

  Future<List<SessionRow>> getSessions() async {
    final res = await _dio.get<List<dynamic>>('/admin-console/sessions');

    return (res.data ?? [])
        .map((e) => SessionRow.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> forceLogout(int userId) async {
    await _dio.delete<dynamic>('/admin-console/sessions/$userId');
  }

  Future<List<Tenant>> getTenants() async {
    final res = await _dio.get<List<dynamic>>('/admin-console/tenants');

    return (res.data ?? [])
        .map((e) => Tenant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<NoticeCampaign>> getNoticeHistory() async {
    final res = await _dio.get<List<dynamic>>('/admin-console/notices');

    return (res.data ?? [])
        .map((e) => NoticeCampaign.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // scope: 'all' | 'stores' | 'store'
  Future<int> sendNotice({
    required String scope,
    required String level,
    required String title,
    required String body,
    List<int>? storeIds,
    int? storeId,
  }) async {
    final payload = <String, dynamic>{
      'scope': scope,
      'level': level,
      'title': title,
      'body': body,
    };
    if (scope == 'stores') payload['storeIds'] = storeIds ?? [];
    if (scope == 'store') payload['storeId'] = storeId;
    final res = await _dio.post<Map<String, dynamic>>('/admin-console/notices', data: payload);

    return (res.data?['count'] ?? 0) as int;
  }
}

// ── FutureProviders (자동 갱신은 ref.invalidate 로) ──

final sessionsProvider = FutureProvider.autoDispose<List<SessionRow>>((ref) {
  return ref.read(consoleRepositoryProvider).getSessions();
});

final tenantsProvider = FutureProvider.autoDispose<List<Tenant>>((ref) {
  return ref.read(consoleRepositoryProvider).getTenants();
});

final noticeHistoryProvider = FutureProvider.autoDispose<List<NoticeCampaign>>((ref) {
  return ref.read(consoleRepositoryProvider).getNoticeHistory();
});
