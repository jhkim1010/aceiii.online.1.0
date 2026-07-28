import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../shared/format.dart';
import '../auth/auth_controller.dart';

// ── 모델 ──

// 한 카하(카시 레지스터) 세션. status 컬럼이 없으므로 closingTime 으로 판정.
class CajaSession {
  final int id;
  final int terminalId;
  final int boxId;
  final String terminalName;
  // 카하(box) 이름 — Caja 탭 표시는 터미널이 아닌 카하 기준 (2026-07-28 사용자 요청)
  final String boxName;
  final String userName;
  final String? branchName;
  final num initialAmount;
  final String date; // YYYY-MM-DD
  final String? startTime; // HH:mm:ss
  final String? closingTime; // null = 열림
  // 삭제(소프트)된 터미널의 세션 — 유령 세션 경고 표시용
  final bool terminalDeleted;
  // 열린 카하의 실시간 잔액(별도 resume 호출로 채움). 닫힌 경우 null.
  num? saldo;

  CajaSession.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        terminalId = asInt(j['terminalId']),
        boxId = asInt(j['boxId']),
        terminalName = _name(j['terminal'], fallback: 'Terminal ${asInt(j['terminalId'])}'),
        boxName = _name(j['box'], fallback: 'Caja'),
        userName = _person(j['user']),
        branchName = (j['box'] is Map && (j['box']['branch'] is Map))
            ? j['box']['branch']['name'] as String?
            : null,
        initialAmount = asNum(j['initialAmount']),
        date = (j['date'] ?? '').toString(),
        startTime = j['startTime'] as String?,
        closingTime = j['closingTime'] as String?,
        terminalDeleted =
            (j['terminal'] is Map) && (j['terminal']['isDeleted'] == true);

  bool get isOpen => closingTime == null || closingTime!.isEmpty;

  // 오늘이 아닌 날짜에 열린 채 남은 세션 (마감 누락 잔재)
  bool get isStaleOpen => isOpen && date != todayStr();

  static String _name(dynamic m, {required String fallback}) {
    if (m is Map && m['name'] != null && '${m['name']}'.isNotEmpty) {
      return m['name'].toString();
    }

    return fallback;
  }

  static String _person(dynamic m) {
    if (m is Map) {
      final parts = [m['name'], m['lastName']]
          .where((e) => e != null && '$e'.isNotEmpty)
          .join(' ')
          .trim();
      if (parts.isNotEmpty) return parts;
      if (m['username'] != null) return m['username'].toString();
    }

    return '—';
  }
}

// resume 의 totals + 초기금액.
class CajaTotals {
  final num initialAmount;
  final num venta;
  final num ingreso;
  final num gasto;
  final num retiro;
  final num saldoFinal;

  CajaTotals.fromResume(Map<String, dynamic> j)
      : initialAmount = asNum((j['cashRegister'] as Map?)?['initialAmount']),
        venta = asNum((j['totals'] as Map?)?['venta']),
        ingreso = asNum((j['totals'] as Map?)?['ingreso']),
        gasto = asNum((j['totals'] as Map?)?['gasto']),
        retiro = asNum((j['totals'] as Map?)?['retiro']),
        saldoFinal = asNum((j['totals'] as Map?)?['saldoFinal']);
}

// 카하 거래 1건 (box-operation).
class BoxOp {
  final int id;
  final String description;
  final num amount;
  final String type; // gasto | venta | ingreso | retiro
  final String executionType; // manual | automatico
  final String createdAt;

  BoxOp.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        description = (j['description'] ?? '').toString(),
        amount = asNum(j['amount']),
        type = (j['type'] ?? '').toString(),
        executionType = (j['executionType'] ?? '').toString(),
        createdAt = (j['createdAt'] ?? '').toString();
}

// 카하(box) 1개의 현재 상태 — Caja 탭의 단위. 터미널은 노출하지 않는다.
class CajaBoxStatus {
  final int boxId;
  final String name;
  final String? branchName;
  // 열린 세션 기준 잔액 (서버 GET /box/store 가 단일 쿼리로 계산)
  final num balance;
  final List<CajaSession> openSessions;
  final List<CajaSession> todaySessions;

  CajaBoxStatus({
    required this.boxId,
    required this.name,
    required this.branchName,
    required this.balance,
    required this.openSessions,
    required this.todaySessions,
  });

  bool get isOpen => openSessions.isNotEmpty;

  // 유령 세션 경고 (삭제된 터미널 / 이전 날짜 미마감)
  bool get hasDeletedTerminal =>
      openSessions.any((s) => s.terminalDeleted);
  bool get hasStaleOpen => openSessions.any((s) => s.isStaleOpen);
}

// Panel/Caja 공용 실시간 요약 — 매장의 모든 카하(box) 상태.
class CajaOverview {
  final List<CajaBoxStatus> boxes;
  final int openCount;
  final num totalSaldo; // 열린 카하 잔액 합

  CajaOverview(this.boxes, this.openCount, this.totalSaldo);
}

// ── 리포지토리 ──

final cajaRepositoryProvider = Provider<CajaRepository>((ref) {
  return CajaRepository(ref.read(dioClientProvider));
});

class CajaRepository {
  final Dio _dio;

  CajaRepository(this._dio);

  // 오늘 카하 목록 (store 는 토큰에서 서버가 스코핑). 최근 50건에서 오늘/미마감만 추림.
  Future<List<CajaSession>> getTodayCajas() async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/cash-register',
      queryParameters: {'page': 0, 'pageSize': 50},
    );
    final list = (res.data?['data'] as List?) ?? const [];
    final today = todayStr();
    final all = list
        .map((e) => CajaSession.fromJson(e as Map<String, dynamic>))
        .toList();

    // 오늘 것 + (날짜 무관) 아직 안 닫힌 것
    return all.where((c) => c.date == today || c.isOpen).toList();
  }

  Future<CajaTotals> getResume(int cashRegisterId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/cash-register/$cashRegisterId/resume',
    );

    return CajaTotals.fromResume(res.data ?? const {});
  }

  // 카하 마감 (열린 카하만). POST /cash-register/close/:id
  Future<void> closeCaja(int cashRegisterId) async {
    await _dio.post<dynamic>('/cash-register/close/$cashRegisterId');
  }

  // 수동 이동 등록 (Ingreso / Retiro / Gasto). POST /box-operation/manual
  // executionType 은 서버가 'manual' 로 고정. 열린 카하에만 호출할 것.
  Future<void> addManualOperation({
    required int cashRegisterId,
    required int terminalId,
    required String type, // ingreso | retiro | gasto
    required num amount,
    String? description,
    int? userId,
  }) async {
    await _dio.post<dynamic>('/box-operation/manual', data: {
      'cashRegisterId': cashRegisterId,
      'terminalId': terminalId,
      'type': type,
      'amount': amount,
      if (description != null && description.isNotEmpty)
        'description': description,
      'userId': ?userId,
    });
  }

  Future<List<BoxOp>> getMovements(int cashRegisterId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/box-operation',
      queryParameters: {
        'cashRegisterId': cashRegisterId,
        'page': 0,
        'pageSize': 50,
      },
    );
    final list = (res.data?['data'] as List?) ?? const [];

    return list
        .map((e) => BoxOp.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 매장의 카하(box) 목록 + 열린 세션 잔액. 서버가 잔액을 단일 쿼리로 계산 → pool 부담 최소.
  Future<List<Map<String, dynamic>>> getBoxes(int storeId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/box/store/$storeId',
      queryParameters: {'page': 0, 'pageSize': 50, 'isDeleted': 'false'},
    );
    final list = (res.data?['data'] as List?) ?? const [];

    return list.cast<Map<String, dynamic>>();
  }

  // 실시간 요약: 모든 카하 상태 (열리지 않은 카하도 Cerrada 로 포함).
  // 요청 2개 병렬 (box 목록 + 세션 목록) — 이전의 세션별 resume N회 호출보다 가볍다.
  Future<CajaOverview> getOverview(int storeId) async {
    final results = await Future.wait<dynamic>([
      getBoxes(storeId),
      getTodayCajas(),
    ]);
    final boxRows = results[0] as List<Map<String, dynamic>>;
    final sessions = results[1] as List<CajaSession>;

    // 세션을 boxId 로 그룹핑
    final byBox = <int, List<CajaSession>>{};
    for (final s in sessions) {
      byBox.putIfAbsent(s.boxId, () => []).add(s);
    }

    final boxes = boxRows.map((b) {
      final id = asInt(b['id']);
      final all = byBox[id] ?? const <CajaSession>[];

      return CajaBoxStatus(
        boxId: id,
        name: (b['name'] ?? 'Caja').toString(),
        branchName:
            (b['branch'] is Map) ? b['branch']['name'] as String? : null,
        balance: asNum(b['balance']),
        openSessions: all.where((s) => s.isOpen).toList(),
        todaySessions: all.where((s) => !s.isOpen).toList(),
      );
    }).toList();

    // 열린 것 먼저, 이후 이름순
    boxes.sort((a, b) {
      if (a.isOpen != b.isOpen) return a.isOpen ? -1 : 1;

      return a.name.compareTo(b.name);
    });

    final openCount = boxes.where((b) => b.isOpen).length;
    final totalSaldo = boxes
        .where((b) => b.isOpen)
        .fold<num>(0, (acc, b) => acc + b.balance);

    return CajaOverview(boxes, openCount, totalSaldo);
  }
}

// ── Providers (갱신은 ref.invalidate) ──

final cajaOverviewProvider =
    FutureProvider.autoDispose<CajaOverview>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  if (storeId == null) throw Exception('Sin storeId');

  return ref.read(cajaRepositoryProvider).getOverview(storeId);
});

final cajaResumeProvider =
    FutureProvider.autoDispose.family<CajaTotals, int>((ref, id) {
  return ref.read(cajaRepositoryProvider).getResume(id);
});

final cajaMovementsProvider =
    FutureProvider.autoDispose.family<List<BoxOp>, int>((ref, id) {
  return ref.read(cajaRepositoryProvider).getMovements(id);
});
