import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'diagnostics_repository.dart';

class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pool = ref.watch(poolProvider);
    final outbox = ref.watch(outboxProvider);
    final slow = ref.watch(slowQueriesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(poolProvider);
        ref.invalidate(outboxProvider);
        ref.invalidate(slowQueriesProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Diagnóstico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // Pool
          pool.when(
            loading: () => const Card(child: Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator())),
            error: (e, _) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text('Pool: $e', style: const TextStyle(color: AppColors.red)))),
            data: (p) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text('Pool de conexiones', style: TextStyle(fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${p.using}/${p.max} (${p.usagePct}%)',
                            style: TextStyle(color: p.waiting > 0 ? AppColors.red : AppColors.dim)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (p.usagePct / 100).clamp(0, 1),
                      color: p.waiting > 0 || p.usagePct >= 80 ? AppColors.red : AppColors.green,
                      backgroundColor: const Color(0xFF0E1428),
                    ),
                    const SizedBox(height: 6),
                    Text('size ${p.size} · available ${p.available} · waiting ${p.waiting}',
                        style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),

          // Outbox
          outbox.when(
            loading: () => const SizedBox.shrink(),
            error: (e, _) => const SizedBox.shrink(),
            data: (o) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Outbox', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      children: [
                        _chip('pending', o.counts['pending'] ?? 0, AppColors.amber),
                        _chip('processing', o.counts['processing'] ?? 0, AppColors.cyan),
                        _chip('done', o.counts['done'] ?? 0, AppColors.green),
                        _chip('failed', o.counts['failed'] ?? 0, AppColors.red),
                      ],
                    ),
                    if (o.oldestPendingSecs != null && o.oldestPendingSecs! > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text('más antiguo pendiente: ${o.oldestPendingSecs}s',
                            style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
          const Text('Consultas lentas', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...slow.when(
            loading: () => [const Center(child: CircularProgressIndicator())],
            error: (e, _) => [Text('$e', style: const TextStyle(color: AppColors.red))],
            data: (list) => list.isEmpty
                ? [const Text('Sin consultas lentas', style: TextStyle(color: AppColors.dim))]
                : list
                    .map((q) => Card(
                          child: ListTile(
                            dense: true,
                            title: Text('QID ${q.qid} · ${q.tableName ?? '-'}',
                                style: const TextStyle(fontSize: 13)),
                            subtitle: Text(q.sql, maxLines: 2, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: AppColors.dim, fontSize: 11)),
                            trailing: Text('${q.durationMs} ms',
                                style: TextStyle(
                                  color: q.durationMs >= 5000 ? AppColors.red : q.durationMs >= 500 ? AppColors.amber : AppColors.dim,
                                  fontWeight: FontWeight.bold,
                                )),
                          ),
                        ))
                    .toList(),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, int n, Color color) {
    return Column(
      children: [
        Text('$n', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 20)),
        Text(label, style: const TextStyle(color: AppColors.dim, fontSize: 11)),
      ],
    );
  }
}
