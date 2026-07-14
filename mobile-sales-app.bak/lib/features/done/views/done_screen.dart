// S5 Done — En espera (/done). 초록 링 ✓ + "En la lista de espera" + body + 티켓 번호
// + reserva 박스(셀별 −qty → disp) + 액션(Ver stock / Otra venta). D-13: Caja 무영향 명시.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

// /done 네비게이션 인자
class DoneArgs {
  final int suspendedSaleId;
  final List<DoneReserva> reservas;

  const DoneArgs({required this.suspendedSaleId, this.reservas = const []});
}

// reserva 표시 항목 (변형 라벨 + 예약 수량 + 남은 자지점 재고)
class DoneReserva {
  final String label;
  final int qty;
  final int remaining;

  const DoneReserva({required this.label, required this.qty, required this.remaining});
}

class DoneScreen extends StatelessWidget {
  final DoneArgs? args;

  const DoneScreen({super.key, this.args});

  @override
  Widget build(BuildContext context) {
    final saleId = args?.suspendedSaleId ?? 0;
    final reservas = args?.reservas ?? const [];

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              // 초록 링 ✓
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.green, width: 3),
                ),
                child: const Icon(Icons.check, color: AppColors.green, size: 44),
              ),
              const SizedBox(height: 20),
              const Text(
                'En la lista de espera',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.ink),
              ),
              const SizedBox(height: 8),
              const Text(
                'Quedó en la caja esperando que el administrador la restaure y cobre.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppColors.muted),
              ),
              const SizedBox(height: 20),
              // 티켓
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.soft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.gold),
                ),
                child: Text(
                  'En espera N°$saleId',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    fontFeatures: kTabularFigures,
                  ),
                ),
              ),
              if (reservas.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.amberSoft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔒 Reservado · stock disponible bajó',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.goldDark),
                      ),
                      const SizedBox(height: 8),
                      for (final r in reservas)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            '${r.label}:  −${r.qty} → ${r.remaining} disp.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.ink,
                              fontFeatures: kTabularFigures,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const Spacer(),
              // 액션
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.go('/catalog'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                        side: const BorderSide(color: AppColors.line),
                      ),
                      child: const Text('Ver stock', style: TextStyle(color: AppColors.ink)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Otra venta'),
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
