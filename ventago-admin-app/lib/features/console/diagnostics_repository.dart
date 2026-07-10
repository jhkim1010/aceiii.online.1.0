import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';

class PoolStatus {
  final int size, using, available, waiting, min, max, usagePct;

  PoolStatus.fromJson(Map<String, dynamic> j)
      : size = (j['size'] ?? 0) as int,
        using = (j['using'] ?? 0) as int,
        available = (j['available'] ?? 0) as int,
        waiting = (j['waiting'] ?? 0) as int,
        min = (j['min'] ?? 0) as int,
        max = (j['max'] ?? 0) as int,
        usagePct = (j['usagePct'] ?? 0) as int;
}

class OutboxStatus {
  final Map<String, int> counts;
  final int? oldestPendingSecs;

  OutboxStatus.fromJson(Map<String, dynamic> j)
      : counts = ((j['counts'] ?? {}) as Map).map((k, v) => MapEntry(k.toString(), (v ?? 0) as int)),
        oldestPendingSecs = j['oldestPendingSecs'] as int?;
}

class SlowQuery {
  final int qid, durationMs;
  final String queryType, sql;
  final String? tableName;
  final String createdAt;

  SlowQuery.fromJson(Map<String, dynamic> j)
      : qid = (j['qid'] ?? 0) as int,
        durationMs = (j['duration_ms'] ?? 0) as int,
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
}

final poolProvider = FutureProvider.autoDispose<PoolStatus>((ref) => ref.read(diagnosticsRepositoryProvider).getPool());
final outboxProvider = FutureProvider.autoDispose<OutboxStatus>((ref) => ref.read(diagnosticsRepositoryProvider).getOutbox());
final slowQueriesProvider = FutureProvider.autoDispose<List<SlowQuery>>((ref) => ref.read(diagnosticsRepositoryProvider).getSlowQueries());
