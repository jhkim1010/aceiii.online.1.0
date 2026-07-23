import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';

// ── 모델 ──

// PG COUNT/SUM/numeric 은 JSON 에서 문자열("12", "34500.00")로 내려올 수 있음.
// 'String is not a subtype of num' 크래시 방지용 관용 파서.
int _asInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

num _asNum(dynamic v) => v is num ? v : (num.tryParse('$v') ?? 0);

class SessionRow {
  final int userId;
  final String name;
  final String platform;
  final String status;
  final int storeId; // 매장 필터용 (백엔드 store_id, 없으면 0)
  final String? storeName;
  final String? branchName;
  final String? publicIp;
  final int idleSecs;

  SessionRow.fromJson(Map<String, dynamic> j)
      : userId = _asInt(j['userId']),
        name = [j['name'], j['lastName']].where((e) => e != null && '$e'.isNotEmpty).join(' ').trim().isEmpty
            ? (j['username'] ?? j['email'] ?? '#${j['userId']}').toString()
            : [j['name'], j['lastName']].where((e) => e != null).join(' '),
        platform = (j['platform'] ?? 'web').toString(),
        status = (j['status'] ?? 'idle').toString(),
        storeId = _asInt(j['storeId']),
        storeName = j['storeName'] as String?,
        branchName = j['branchName'] as String?,
        publicIp = j['publicIp'] as String?,
        idleSecs = _asInt(j['idleSecs']);
}

class Tenant {
  final int storeId;
  final String storeName;
  final int branches;
  final int terminals;
  final int salesToday;
  final int salesMonth;
  final num revenueMonth;
  // 오늘/이달 사용량
  final int vtoToday, vtoMonth, whatsappToday, whatsappMonth, facturasToday, facturasMonth, vendedorDevices;
  final List<int> activeDayNums;
  final int activeDaysMonth;
  // 모듈
  final bool modFacturaElectronica, modWhatsapp, modWoocommerce, modTiendanube, modVto, modVendedor;
  final num expectedFee; // 순액(할인 반영)
  final num grossFee; // 할인 전 총액
  final num recurringDiscount; // 상시 할인
  final num oneTimeDiscount; // 이번 달 일회성 할인
  final String currency;
  final bool subscriptionEnabled;
  final int errors24h;
  final DateTime? lastActivityAt;

  Tenant.fromJson(Map<String, dynamic> j)
      : storeId = _asInt(j['storeId']),
        storeName = (j['storeName'] ?? '#${j['storeId']}').toString(),
        branches = _asInt(j['branches']),
        terminals = _asInt(j['terminals']),
        salesToday = _asInt(j['salesToday']),
        salesMonth = _asInt(j['salesMonth']),
        revenueMonth = _asNum(j['revenueMonth']),
        vtoToday = _asInt(j['vtoToday']),
        vtoMonth = _asInt(j['vtoMonth']),
        whatsappToday = _asInt(j['whatsappToday']),
        whatsappMonth = _asInt(j['whatsappMonth']),
        facturasToday = _asInt(j['facturasToday']),
        facturasMonth = _asInt(j['facturasMonth']),
        vendedorDevices = _asInt(j['vendedorDevices']),
        activeDayNums = ((j['activeDayNums'] as List?) ?? const [])
            .map((e) => _asInt(e))
            .toList(),
        activeDaysMonth = _asInt(j['activeDaysMonth']),
        modFacturaElectronica = j['modFacturaElectronica'] == true,
        modWhatsapp = j['modWhatsapp'] == true,
        modWoocommerce = j['modWoocommerce'] == true,
        modTiendanube = j['modTiendanube'] == true,
        modVto = j['modVto'] == true,
        modVendedor = j['modVendedor'] == true,
        expectedFee = _asNum(j['expectedFee']),
        grossFee = _asNum(j['grossFee']),
        recurringDiscount = _asNum(j['recurringDiscount']),
        oneTimeDiscount = _asNum(j['oneTimeDiscount']),
        currency = (j['currency'] ?? 'ARS').toString(),
        subscriptionEnabled = j['subscriptionEnabled'] == true,
        errors24h = _asInt(j['errors24h']),
        lastActivityAt = j['lastActivityAt'] == null ? null : DateTime.tryParse('${j['lastActivityAt']}');
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
        total = _asInt(j['total']),
        read = _asInt(j['read']),
        createdAt = (j['createdAt'] ?? '').toString();
}

// soft-delete 된 매장 (Borrados 화면)
class DeletedTenant {
  final int storeId;
  final String storeName;
  final DateTime? deletedAt;

  DeletedTenant.fromJson(Map<String, dynamic> j)
      : storeId = _asInt(j['storeId']),
        storeName = (j['storeName'] ?? '#${j['storeId']}').toString(),
        deletedAt = j['deletedAt'] == null ? null : DateTime.tryParse('${j['deletedAt']}');
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

    return _asInt(res.data?['count']);
  }

  // ── 매장 soft-delete / 복구 / 삭제목록 ──
  Future<List<DeletedTenant>> getDeletedTenants() async {
    final res = await _dio.get<List<dynamic>>('/admin-console/tenants/deleted');

    return (res.data ?? [])
        .map((e) => DeletedTenant.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> softDeleteStore(int storeId) async {
    await _dio.delete<dynamic>('/admin-console/tenants/$storeId');
  }

  Future<void> restoreStore(int storeId) async {
    await _dio.post<dynamic>('/admin-console/tenants/$storeId/restore');
  }

  // ── 관리비 할인 적용/제거 ── kind: 'recurring' | 'one_time'
  Future<void> applyDiscount(int storeId, num amount, String kind) async {
    await _dio.post<dynamic>(
      '/admin-console/tenants/$storeId/discount',
      data: {'amount': amount, 'kind': kind},
    );
  }

  Future<void> removeDiscount(int storeId, String kind) async {
    await _dio.delete<dynamic>(
      '/admin-console/tenants/$storeId/discount',
      queryParameters: {'kind': kind},
    );
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

final deletedTenantsProvider = FutureProvider.autoDispose<List<DeletedTenant>>((ref) {
  return ref.read(consoleRepositoryProvider).getDeletedTenants();
});
