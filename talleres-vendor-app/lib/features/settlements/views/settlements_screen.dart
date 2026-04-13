// 정산 화면 — 정산 목록, 기간 필터, 합계 카드 (읽기 전용)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../../../shared/widgets/status_chip.dart';
import '../data/settlement_dto.dart';
import '../providers/settlement_provider.dart';

// 정산 화면 — ConsumerWidget으로 Riverpod 상태 구독
// 읽기 전용 — 정산 데이터 수정 불가 (T-17-12)
class SettlementsScreen extends ConsumerWidget {
  const SettlementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStore = ref.watch(currentStoreProvider);

    // 현재 선택된 매장이 없으면 안내 메시지 표시
    if (currentStore == null) {
      return const Center(child: Text('Selecciona una tienda'));
    }

    final storeId = currentStore.storeId;
    final dateRange = ref.watch(settlementDateRangeProvider);
    final settlementsAsync = ref.watch(settlementListProvider(storeId));
    final total = ref.watch(settlementTotalProvider(storeId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Liquidaciones'),
        centerTitle: false,
      ),
      body: Column(
        children: [
          // 기간 필터 섹션
          _DateRangeFilter(
            dateRange: dateRange,
            onChanged: (newRange) {
              ref.read(settlementDateRangeProvider.notifier).setRange(newRange);
            },
          ),

          // 기간 합계 카드
          settlementsAsync.maybeWhen(
            data: (settlements) => settlements.isEmpty
                ? const SizedBox.shrink()
                : _TotalCard(total: total),
            orElse: () => const SizedBox.shrink(),
          ),

          // 정산 목록
          Expanded(
            child: settlementsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 48,
                      color: Colors.red,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error: $error',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () =>
                          ref.invalidate(settlementListProvider(storeId)),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
              data: (settlements) => _SettlementList(
                settlements: settlements,
                onRefresh: () async {
                  ref.invalidate(settlementListProvider(storeId));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 기간 필터 위젯 — 날짜 범위 선택
class _DateRangeFilter extends StatelessWidget {
  final DateTimeRange? dateRange;
  final void Function(DateTimeRange?) onChanged;

  const _DateRangeFilter({
    required this.dateRange,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy', 'es');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // 기간 선택 버튼
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.date_range, size: 18),
              label: Text(
                dateRange != null
                    ? '${dateFmt.format(dateRange!.start)} - ${dateFmt.format(dateRange!.end)}'
                    : 'Seleccionar período',
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () => _pickDateRange(context),
            ),
          ),

          // 필터 초기화 버튼 — 기간 선택 시만 표시
          if (dateRange != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.clear),
              tooltip: 'Quitar filtro',
              onPressed: () => onChanged(null),
            ),
          ],
        ],
      ),
    );
  }

  // 날짜 범위 선택 다이얼로그 표시
  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: dateRange,
      locale: const Locale('es'),
      helpText: 'Seleccionar período',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
    );

    if (picked != null) {
      onChanged(picked);
    }
  }
}

// 합계 카드 — 기간 내 순액 합계 표시
class _TotalCard extends StatelessWidget {
  final double total;

  const _TotalCard({required this.total});

  @override
  Widget build(BuildContext context) {
    final currencyFmt = NumberFormat('#,##0.00', 'es');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total neto del período',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
              Text(
                '\$${currencyFmt.format(total)}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 정산 목록 위젯 — pull-to-refresh 지원
class _SettlementList extends StatelessWidget {
  final List<SettlementDto> settlements;
  final Future<void> Function() onRefresh;

  const _SettlementList({
    required this.settlements,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    // 정산 내역이 없을 때 빈 상태 화면
    if (settlements.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No hay liquidaciones',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Colors.grey.shade500,
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: settlements.length,
        itemBuilder: (context, index) {
          final settlement = settlements[index];

          return _SettlementCard(settlement: settlement);
        },
      ),
    );
  }
}

// 정산 카드 위젯 — 단일 정산 항목 표시 (읽기 전용)
class _SettlementCard extends StatelessWidget {
  final SettlementDto settlement;

  const _SettlementCard({required this.settlement});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('dd/MM/yyyy', 'es');
    final currencyFmt = NumberFormat('#,##0.00', 'es');

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더 — 주문 번호 + 상태 배지
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    settlement.orderNumber != null
                        ? 'Orden #${settlement.orderNumber}'
                        : 'Orden #${settlement.subconOrderId}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                StatusChip(status: settlement.status),
              ],
            ),

            const SizedBox(height: 8),

            // 기간 표시
            if (settlement.periodFrom != null && settlement.periodTo != null)
              Row(
                children: [
                  const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '${dateFmt.format(settlement.periodFrom!)} - ${dateFmt.format(settlement.periodTo!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                  ),
                ],
              ),

            const Divider(height: 16),

            // 금액 정보
            _AmountRow(
              label: 'Total bruto',
              amount: currencyFmt.format(settlement.totalGrossAmount),
              isBold: false,
            ),
            const SizedBox(height: 4),
            _AmountRow(
              label: 'Descuentos',
              amount: '- ${currencyFmt.format(settlement.deductionAmount)}',
              isBold: false,
              color: Colors.red.shade600,
            ),
            const SizedBox(height: 4),
            _AmountRow(
              label: 'Neto',
              amount: '\$${currencyFmt.format(settlement.netAmount)}',
              isBold: true,
            ),

            // 비고 (있을 때만)
            if (settlement.notes != null && settlement.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                settlement.notes!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 금액 행 위젯 — 라벨 + 금액 한 줄 표시
class _AmountRow extends StatelessWidget {
  final String label;
  final String amount;
  final bool isBold;
  final Color? color;

  const _AmountRow({
    required this.label,
    required this.amount,
    required this.isBold,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          color: color,
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(amount, style: style),
      ],
    );
  }
}
