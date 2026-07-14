// Modo Revendedor — 랜딩 + 매장 승인 QR 게이트(37-08, 스펙 §revendedor L161-169).
// revendedor 는 매장에 물리 방문해 승인 QR 을 스캔해야 그 매장 카탈로그 판매권을 얻는다.
// 미승인(STORE_NOT_AUTHORIZED / 카탈로그 비어있음) → "Escaneá el QR de la tienda para habilitar" +
// showFichajeScannerSheet → store_authorized 결과 → 카탈로그 개방.
// 완전 강제(RequireStoreAuthGuard)는 Phase 24 카탈로그와 함께 활성 — 이 wave 는 프롬프트+해피패스만 배선.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../attendance/views/fichaje_scanner_sheet.dart';
import '../../auth/providers/scope_provider.dart';

class RevendedorHome extends ConsumerWidget {
  const RevendedorHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeNotifierProvider).value;
    final name = switch (scope) {
      MultiStoreScope(:final user) => user.name,
      _ => 'Revendedor',
    };
    // 이 wave 는 매장 승인 상태를 아직 서버에서 받지 않음(Phase 24) → 미승인으로 취급해
    // 승인 QR 프롬프트를 노출한다. store_authorized punch 성공 시 /fichaje/result 가 카탈로그로 개방.
    // Phase 24 도착 시 여기서 승인 여부를 조회해 승인 매장 목록/카탈로그로 분기한다.
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Modo revendedor'),
        actions: [
          IconButton(
            onPressed: () => ref.read(scopeNotifierProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
            tooltip: 'Salir',
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _StoreAuthPrompt(name: name),
        ),
      ),
    );
  }
}

// 매장 미승인 프롬프트 — 승인 QR 스캔 유도.
class _StoreAuthPrompt extends StatelessWidget {
  final String name;

  const _StoreAuthPrompt({required this.name});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: AppColors.amberSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.qr_code_2, color: AppColors.goldDark, size: 34),
        ),
        const SizedBox(height: 18),
        Text(
          'Hola, $name',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Escaneá el QR de la tienda para habilitar',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: () => showFichajeScannerSheet(context),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear QR de la tienda'),
          ),
        ),
      ],
    );
  }
}
