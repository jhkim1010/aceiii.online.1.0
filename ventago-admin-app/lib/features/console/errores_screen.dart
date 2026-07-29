// 대시보드 'Errores 24h' 카드 더블탭 → 전 매장 최근 24h 5xx 오류 세부 목록.
// 각 항목 탭 → 전체 message/path/ip 를 다이얼로그로.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

class ErroresScreen extends ConsumerWidget {
  const ErroresScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final errors = ref.watch(recentErrorsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Errores 24h')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(recentErrorsProvider),
        child: errors.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Error: $e',
                    style: const TextStyle(color: AppColors.red)),
              ),
            ],
          ),
          data: (list) {
            if (list.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Sin errores en las últimas 24 h.',
                        style: TextStyle(color: AppColors.dim)),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) => _ErrorCard(e: list[i]),
            );
          },
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final StoreError e;
  const _ErrorCard({required this.e});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: () => _showDetail(context),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${e.statusCode}',
                        style: const TextStyle(
                            color: AppColors.red,
                            fontWeight: FontWeight.w800,
                            fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      e.storeName ?? 'store #${e.storeId ?? '?'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(_fmt(e.createdAt),
                      style: const TextStyle(color: AppColors.dim, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${e.method ?? ''} ${e.path ?? ''}'.trim(),
                style: const TextStyle(fontSize: 12, color: AppColors.txt),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (e.message != null && e.message!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  e.message!,
                  style: const TextStyle(fontSize: 12, color: AppColors.dim),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${e.statusCode} · ${e.storeName ?? 'store #${e.storeId ?? '?'}'}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _kv('Fecha', _fmt(e.createdAt)),
              _kv('Método', e.method ?? '—'),
              _kv('Ruta', e.path ?? '—'),
              if (e.userId != null) _kv('Usuario', '#${e.userId}'),
              if (e.ip != null && e.ip!.isNotEmpty) _kv('IP', e.ip!),
              const SizedBox(height: 8),
              const Text('Mensaje',
                  style: TextStyle(color: AppColors.dim, fontSize: 11)),
              const SizedBox(height: 2),
              SelectableText(
                e.message == null || e.message!.isEmpty ? '—' : e.message!,
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 68,
              child: Text(k,
                  style: const TextStyle(color: AppColors.dim, fontSize: 12)),
            ),
            Expanded(
              child: Text(v, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );

  String _fmt(DateTime? d) {
    if (d == null) return '';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');

    return '${two(l.day)}/${two(l.month)} ${two(l.hour)}:${two(l.minute)}';
  }
}
