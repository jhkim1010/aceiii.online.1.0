// EnviosScreen — 매장별 발송 목록 화면 (D-07)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/status_chip.dart';
import '../data/envio_dto.dart';
import '../providers/envio_provider.dart';

// 발송 목록 화면 — ConsumerStatefulWidget으로 새로고침 지원
class EnviosScreen extends ConsumerWidget {
  const EnviosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStore = ref.watch(currentStoreProvider);

    // 선택된 매장이 없는 경우 안내 메시지 표시
    if (currentStore == null) {
      return const Center(
        child: Text('Selecciona una tienda para ver los envíos'),
      );
    }

    final enviosAsync = ref.watch(envioListProvider(currentStore.storeId));

    return enviosAsync.when(
      // 로딩 중 — 스피너 표시
      loading: () => const Center(child: CircularProgressIndicator()),

      // 에러 발생 — 메시지 + 재시도 버튼
      error: (error, _) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(
              'Error al cargar envíos',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error.toString(),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              onPressed: () => ref.invalidate(envioListProvider(currentStore.storeId)),
            ),
          ],
        ),
      ),

      // 데이터 로드 완료 — 목록 또는 빈 상태 표시
      data: (envios) => RefreshIndicator(
        // pull-to-refresh로 목록 새로고침
        onRefresh: () async {
          ref.invalidate(envioListProvider(currentStore.storeId));

          return ref.read(envioListProvider(currentStore.storeId).future).then((_) {});
        },
        child: envios.isEmpty
            ? const _EmptyEnviosView()
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: envios.length,
                itemBuilder: (context, index) =>
                    _EnvioCard(envio: envios[index], storeId: currentStore.storeId),
              ),
      ),
    );
  }
}

// 빈 목록 상태 위젯
class _EmptyEnviosView extends StatelessWidget {
  const _EmptyEnviosView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No hay envíos',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 8),
            Text(
              'Aún no hay envíos asignados para esta tienda',
              style: TextStyle(color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ],
    );
  }
}

// 발송 항목 카드 위젯
class _EnvioCard extends StatelessWidget {
  final EnvioDto envio;
  final int storeId;

  const _EnvioCard({required this.envio, required this.storeId});

  // 납기일 D-day 계산
  String _formatDueDate(String? dueDate) {
    if (dueDate == null) {
      return 'Sin vencimiento';
    }

    try {
      final due = DateTime.parse(dueDate);
      final now = DateTime.now();
      final diff = due.difference(DateTime(now.year, now.month, now.day)).inDays;

      if (diff < 0) {
        return 'Vencido (${diff.abs()}d)';
      } else if (diff == 0) {
        return 'Vence hoy';
      } else {
        return 'D-$diff';
      }
    } catch (_) {
      return dueDate;
    }
  }

  // 납기일에 따른 색상 결정
  Color _dueDateColor(String? dueDate) {
    if (dueDate == null) {
      return Colors.grey;
    }

    try {
      final due = DateTime.parse(dueDate);
      final now = DateTime.now();
      final diff = due.difference(DateTime(now.year, now.month, now.day)).inDays;

      if (diff < 0) {
        return Colors.red;
      } else if (diff <= 3) {
        return Colors.orange;
      }

      return Colors.green;
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        // 탭 시 발송 상세 화면으로 이동 (extra로 EnvioDto 전달)
        onTap: () => context.push('/envio/${envio.id}', extra: envio),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 로트 이름 + 상태 배지
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      envio.loteName ?? 'Lote #${envio.loteId}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  StatusChip(status: envio.status),
                ],
              ),
              const SizedBox(height: 8),

              // 중간: 에타파 이름 + 수량 정보
              Row(
                children: [
                  Icon(Icons.workspaces_outline, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    envio.etapaName ?? 'Etapa #${envio.etapaId}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Text(
                    'Total: ${envio.quantity}  —  Pendiente: ${envio.pendingQuantity}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 하단: 발송일 + 납기일 (D-day)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Enviado: ${envio.envioDate.split('T').first}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                  Text(
                    _formatDueDate(envio.dueDate),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: _dueDateColor(envio.dueDate),
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
