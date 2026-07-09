// Modo Revendedor — Quote(cotización/pedido) STUB (BLOCKED, D-07).
// Phase 24(reseller.catalog_unified MV + reseller_tienda_link) 도착 전엔 cotización 로직을
// 구현하지 않는다. 활성화 시 cotización/pedido 는 pendiente/보류(Caja-neutral, D-13)로 동작한다.
// 활성화 체크리스트: lib/features/revendedor/README.md 참조.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';

// 로직 없음 — cotización 화면 자리표시자.
class QuoteScreen extends StatelessWidget {
  const QuoteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Cotización'),
        leading: context.canPop()
            ? IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => context.pop(),
              )
            : null,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.amberSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.receipt_long_outlined,
                    color: AppColors.goldDark, size: 34),
              ),
              const SizedBox(height: 18),
              const Text(
                'Cotización — Próximamente',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Modo revendedor — requiere Phase 24. '
                'Las cotizaciones serán pendientes (Caja-neutral).',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
