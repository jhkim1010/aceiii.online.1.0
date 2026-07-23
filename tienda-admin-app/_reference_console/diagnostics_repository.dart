import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';


// PG COUNT/SUM/numeric 은 JSON 에서 문자열로 내려올 수 있음 — 관용 파서
int _asInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

class PoolStatus {
  final int size, using, available, waiting, min, max, usagePct;

  PoolStatus.fromJson(Map<String, dynamic> j)
      : size = _asInt(j['size']),
        using = _asInt(j['using']),
        available = _asInt(j['available']),
        waiting = _asInt(j['waiting']),
        min = _asInt(j['min']),
        max = _asInt(j['max']),
        usagePct = _asInt(j['usagePct']);
}

class OutboxStatus {
  final Map<String, int> counts;
  final int? oldestPendingSecs;

  OutboxStatus.fromJson(Map<String, dynamic> j)
      : counts = ((j['counts'] ?? {}) as Map).map((k, v) => MapEntry(k.toString(), _asInt(v))),
        oldestPendingSecs = j['oldestPendingSecs'] == null ? null : _asInt(j['oldestPendingSecs']);
}

class SlowQuery {
  final int qid, durationMs;
  final String queryType, sql;
  final String? tableName;
  final String createdAt;

  SlowQuery.fromJson(Map<String, dynamic> j)
      : qid = _asInt(j['qid']),
        durationMs = _asInt(j['duration_ms']),
        queryType = (j['query_type'] ?? '').toString(),
        sql = (j['sql'] ?? '').toString(),
        tableName = j['table_name'] as String?,
        createdAt = (j['created_at'] ?? '').toString();
}

final diagnosticsRepositoryProvider = Provider<DiagnosticsRepository>((ref) {
  return DiagnosticsRepository(ref.read(dioClientProvider));
});

class DiagnosticsRepository {
  final Dio _dio;

  DiagnosticsRepository(this._dio);

  Future<PoolStatus> getPool() async {
    final res = await _dio.get<Map<String, dynamic>>('/diagnostics/pool');

    return PoolStatus.fromJson(res.data ?? {});
  }

  Future<OutboxStatus> getOutbox() async {
    final res = await _dio.get<Map<String, dynamic>>('/diagnostics/outbox');

    return OutboxStatus.fromJson(res.data ?? {});
  }

  Future<List<SlowQuery>> getSlowQueries() async {
    final res = await _dio.get<List<dynamic>>('/diagnostics/slow-queries', queryParameters: {'limit': 100});

    return (res.data ?? []).map((e) => SlowQuery.fromJson(e as Map<String, dynamic>)).toList();
  }

  // 느린쿼리 로그 전체 삭제 (수동 clear — 이후 새로 쌓이는 것만 보기).
  Future<void> clearSlowQueries() async {
    await _dio.delete<dynamic>('/diagnostics/slow-queries');
  }
}

final poolProvider = FutureProvider.autoDispose<PoolStatus>((ref) => ref.read(diagnosticsRepositoryProvider).getPool());
final outboxProvider = FutureProvider.autoDispose<OutboxStatus>((ref) => ref.read(diagnosticsRepositoryProvider).getOutbox());
final slowQueriesProvider = FutureProvider.autoDispose<List<SlowQuery>>((ref) => ref.read(diagnosticsRepositoryProvider).getSlowQueries());
