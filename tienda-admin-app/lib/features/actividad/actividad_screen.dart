import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';
import '../dashboard/dashboard_repository.dart';
import 'sale_detail_screen.dart';

// 최근 활동 = 최근 판매 피드 (실데이터). v2 에서 직원별 활동 타임라인으로 확장.
class ActividadScreen extends ConsumerWidget {
  const ActividadScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(lastSalesProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(lastSalesProvider);
        await ref.read(lastSalesProvider.future);
      },
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('No se pudo cargar la actividad.\n$e',
                  style: const TextStyle(color: AppColors.red, fontSize: 12)),
            ),
          ],
        ),
        data: (sales) => ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
          children: [
            const Text('ÚLTIMAS VENTAS',
                style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.dim)),
            const SizedBox(height: 10),
            if (sales.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                    child: Text('Sin ventas recientes',
                        style: TextStyle(color: AppColors.dim))),
              ),
            for (final s in sales)
              // 탭하면 판매 세부내역으로 이동
              GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SaleDetailScreen(saleId: s.id),
                  ),
                ),
                child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.panel,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.navy2,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: const Icon(Icons.receipt_long,
                          size: 17, color: AppColors.green),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Venta #${s.id}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            [
                              s.clientName ?? 'Consumidor final',
                              _date(s.saleDate),
                            ].join(' · '),
                            style: const TextStyle(
                                fontSize: 10.5, color: AppColors.dim),
                          ),
                        ],
                      ),
                    ),
                    Text('+${money(s.totalAmount)}',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green)),
                  ],
                ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _date(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return '';
    final l = d.toLocal();

    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
