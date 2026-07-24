import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../shared/format.dart';

// ── 모델 ──

// 한 카하(카시 레지스터) 세션. status 컬럼이 없으므로 closingTime 으로 판정.
class CajaSession {
  final int id;
  final int terminalId;
  final String terminalName;
  final String userName;
  final String? branchName;
  final num initialAmount;
  final String date; // YYYY-MM-DD
  final String? startTime; // HH:mm:ss
  final String? closingTime; // null = 열림
  // 열린 카하의 실시간 잔액(별도 resume 호출로 채움). 닫힌 경우 null.
  num? saldo;

  CajaSession.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        terminalId = asInt(j['terminalId']),
        terminalName = _name(j['terminal'], fallback: 'Terminal ${asInt(j['terminalId'])}'),
        userName = _person(j['user']),
        branchName = (j['box'] is Map && (j['box']['branch'] is Map))
            ? j['box']['branch']['name'] as String?
            : null,
        initialAmount = asNum(j['initialAmount']),
        date = (j['date'] ?? '').toString(),
        startTime = j['startTime'] as String?,
        closingTime = j['closingTime'] as String?;

  bool get isOpen => closingTime == null || closingTime!.isEmpty;

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

// Panel/Caja 공용 실시간 요약.
class CajaOverview {
  final List<CajaSession> sessions; // 오늘 + 미마감 세션
  final int openCount;
  final num totalSaldo; // 열린 카하 saldo 합

  CajaOverview(this.sessions, this.openCount, this.totalSaldo);
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

  // 실시간 요약: 오늘 카하 목록 + 열린 카하만 resume 병렬 조회로 saldo 채움.
  // 열린 카하 수는 보통 소수(1~3) → pool 부담 최소. 닫힌 카하는 추가 호출 없음.
  Future<CajaOverview> getOverview() async {
    final sessions = await getTodayCajas();
    final open = sessions.where((c) => c.isOpen).toList();

    final resumes = await Future.wait(
      open.map((c) async {
        try {
          final t = await getResume(c.id);
          c.saldo = t.saldoFinal;

          return t.saldoFinal;
        } catch (_) {
          // 개별 resume 실패는 요약을 막지 않음
          return 0 as num;
        }
      }),
    );

    final totalSaldo = resumes.fold<num>(0, (a, b) => a + b);

    return CajaOverview(sessions, open.length, totalSaldo);
  }
}

// ── Providers (갱신은 ref.invalidate) ──

final cajaOverviewProvider =
    FutureProvider.autoDispose<CajaOverview>((ref) {
  return ref.read(cajaRepositoryProvider).getOverview();
});

final cajaResumeProvider =
    FutureProvider.autoDispose.family<CajaTotals, int>((ref, id) {
  return ref.read(cajaRepositoryProvider).getResume(id);
});

final cajaMovementsProvider =
    FutureProvider.autoDispose.family<List<BoxOp>, int>((ref, id) {
  return ref.read(cajaRepositoryProvider).getMovements(id);
});
