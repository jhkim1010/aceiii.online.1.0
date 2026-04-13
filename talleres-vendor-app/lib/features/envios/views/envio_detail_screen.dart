// EnvioDetailScreen — 발송 상세 화면 (수령 이력 + 수령 확인)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/status_chip.dart';
import '../data/envio_dto.dart';
import '../providers/envio_provider.dart';
import '../../recepciones/views/recepcion_dialog.dart';

// 발송 상세 화면 — envio 객체를 extra로 전달받음
class EnvioDetailScreen extends ConsumerWidget {
  final int envioId;
  final EnvioDto? initialEnvio;

  const EnvioDetailScreen({
    super.key,
    required this.envioId,
    this.initialEnvio,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 전달받은 초기 envio 데이터 사용 (추가 API 호출 없음)
    final envio = initialEnvio;

    if (envio == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Envío #$envioId')),
        body: const Center(child: Text('Envío no encontrado')),
      );
    }

    // COMPLETED 또는 CANCELLED 상태에서는 FAB 숨김
    final canReceive = envio.status != 'COMPLETED' && envio.status != 'CANCELLED';

    return Scaffold(
      appBar: AppBar(
        title: Text('Envío #${envio.id}'),
        centerTitle: false,
      ),

      // 상세 정보 스크롤 뷰
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상태 및 기본 정보 카드
            _InfoCard(envio: envio),
            const SizedBox(height: 16),

            // 수령 이력 섹션
            _RecepcionesSection(recepciones: envio.recepciones),
          ],
        ),
      ),

      // 수령 확인 버튼 — COMPLETED/CANCELLED 상태에서는 숨김
      floatingActionButton: canReceive
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Confirmar recepción'),
              onPressed: () => _openRecepcionDialog(context, ref, envio),
            )
          : null,
    );
  }

  // 수령 확인 다이얼로그 열기
  void _openRecepcionDialog(BuildContext context, WidgetRef ref, EnvioDto envio) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => RecepcionDialog(
        envio: envio,
        onSuccess: () {
          // 수령 성공 시 envioListProvider 새로고침은 dialog 내부에서 처리
          ref.invalidate(envioListProvider);
        },
      ),
    );
  }
}

// 발송 기본 정보 카드
class _InfoCard extends StatelessWidget {
  final EnvioDto envio;

  const _InfoCard({required this.envio});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더: 로트 이름 + 상태
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    envio.loteName ?? 'Lote #${envio.loteId}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                StatusChip(status: envio.status),
              ],
            ),
            const Divider(height: 24),

            // 상세 정보 행 목록
            _DetailRow(icon: Icons.workspaces_outline, label: 'Etapa', value: envio.etapaName ?? 'Etapa #${envio.etapaId}'),
            _DetailRow(icon: Icons.inventory_2_outlined, label: 'Cantidad total', value: '${envio.quantity}'),
            _DetailRow(icon: Icons.hourglass_bottom_outlined, label: 'Cantidad pendiente', value: '${envio.pendingQuantity}'),
            _DetailRow(
              icon: Icons.calendar_today_outlined,
              label: 'Fecha envío',
              value: envio.envioDate.split('T').first,
            ),
            if (envio.dueDate != null)
              _DetailRow(
                icon: Icons.event_outlined,
                label: 'Fecha vencimiento',
                value: envio.dueDate!.split('T').first,
              ),
          ],
        ),
      ),
    );
  }
}

// 정보 행 위젯
class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// 수령 이력 섹션
class _RecepcionesSection extends StatelessWidget {
  final List<RecepcionDto> recepciones;

  const _RecepcionesSection({required this.recepciones});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Historial de recepciones',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),

        // 수령 이력이 없는 경우 안내 메시지
        if (recepciones.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Sin recepciones registradas',
                style: TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          ...recepciones.map((r) => _RecepcionItem(recepcion: r)),
      ],
    );
  }
}

// 수령 이력 항목 위젯
class _RecepcionItem extends StatelessWidget {
  final RecepcionDto recepcion;

  const _RecepcionItem({required this.recepcion});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(
          child: Icon(Icons.check, size: 18),
        ),
        title: Text(
          'Recibido: ${recepcion.receivedQuantity}  —  Rechazado: ${recepcion.rejectedQuantity}',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(recepcion.recepcionDate.split('T').first),
            if (recepcion.notes != null && recepcion.notes!.isNotEmpty)
              Text(
                recepcion.notes!,
                style: const TextStyle(fontStyle: FontStyle.italic),
              ),
          ],
        ),
        isThreeLine: recepcion.notes != null && recepcion.notes!.isNotEmpty,
      ),
    );
  }
}
