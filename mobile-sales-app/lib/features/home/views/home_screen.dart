// S1 Home (/home) — vendedor 랜딩. 3버튼(Buscar / Ver carrito / Escanear QR).
// scope 로 "Hola, {nombre}" + 매장·지점 표시.
// 출근 게이트(37-08): clockedIn=false 면 작업 버튼 잠금 + "Fichá tu entrada" + fichaje 버튼만.
// 백엔드 RequireAttendanceGuard 가 권위 — 홈은 UX 미러링(라운드트립 절약).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../attendance/views/fichaje_scanner_sheet.dart';
import '../../auth/providers/scope_provider.dart';
import '../../cart/providers/cart_provider.dart';
import '../../scanner/views/qr_scanner_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeNotifierProvider).value;
    final cartUnits = ref.watch(cartProvider).totalUnits;
    final user = switch (scope) {
      BranchScope(:final user) => user,
      MultiStoreScope(:final user) => user,
      _ => null,
    };
    final name = user?.name ?? 'Vendedor';
    final store = user?.storeName ?? '';
    final branch = user?.branchName ?? '';
    // 출근 게이트: 열린 세션 없으면(clockedIn=false) 작업 잠금 + fichaje 유도.
    final clockedIn = user?.clockedIn ?? false;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            // navy hello 헤더
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              color: AppColors.navy,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppColors.gold,
                    child: Text(
                      name.isNotEmpty ? name.characters.first.toUpperCase() : '?',
                      style: const TextStyle(
                        color: AppColors.navy2,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hola, $name',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '📍 $store · Sucursal $branch',
                          style: const TextStyle(color: Color(0xFFB9B9C6), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => ref.read(scopeNotifierProvider.notifier).logout(),
                    icon: const Icon(Icons.logout, color: Color(0xFFB9B9C6)),
                    tooltip: 'Salir',
                  ),
                ],
              ),
            ),
            // 본문 — 출근 여부로 분기
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: clockedIn
                    ? _WorkActions(cartUnits: cartUnits)
                    : const _ClockInGate(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 근무 중(clockedIn=true) 화면 — 기존 3버튼 + 하단 "Fichar salida" 어포던스.
class _WorkActions extends StatelessWidget {
  final int cartUnits;

  const _WorkActions({required this.cartUnits});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HomeButton(
          emoji: '🔎',
          title: 'Buscar producto',
          subtitle: 'Elegir de la lista',
          onTap: () => context.push('/catalog'),
        ),
        const SizedBox(height: 12),
        _HomeButton(
          emoji: '🛒',
          title: 'Ver carrito',
          subtitle: 'Editar y mandar a caja',
          badge: cartUnits > 0 ? cartUnits : null,
          onTap: () => context.push('/comanda'),
        ),
        const Spacer(),
        // QR = primary big (navy) → 스캐너 바텀시트 (D-14 scan-to-detail)
        _HomeButton(
          emoji: '▣',
          title: 'Escanear QR',
          subtitle: 'Leé la percha y probá al instante',
          primary: true,
          onTap: () => showQrScannerSheet(context),
        ),
        const SizedBox(height: 12),
        // 근무 중이라도 언제든 퇴근(salida) 가능 — 같은 fichaje 스캐너.
        TextButton.icon(
          onPressed: () => showFichajeScannerSheet(context),
          icon: const Icon(Icons.logout, size: 18, color: AppColors.muted),
          label: const Text('Fichar salida',
              style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

// 미출근(clockedIn=false) 게이트 — "Fichá tu entrada para empezar" + fichaje 버튼만.
// 작업 액션은 잠금(greyed + 안내). 백엔드 RequireAttendanceGuard 미러링.
class _ClockInGate extends StatelessWidget {
  const _ClockInGate();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.amberSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fichá tu entrada para empezar',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Escaneá el QR de fichaje de la caja para habilitar el catálogo y las ventas.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 작업 버튼 잠금(비활성 + 안내). 스캔 전엔 백엔드도 NOT_CLOCKED_IN 으로 차단.
        const _HomeButton(
          emoji: '🔎',
          title: 'Buscar producto',
          subtitle: 'Fichá tu entrada para habilitar',
          disabled: true,
        ),
        const SizedBox(height: 12),
        const _HomeButton(
          emoji: '🛒',
          title: 'Ver carrito',
          subtitle: 'Fichá tu entrada para habilitar',
          disabled: true,
        ),
        const Spacer(),
        _HomeButton(
          emoji: '🕑',
          title: 'Fichar entrada/salida',
          subtitle: 'Escaneá el QR de la caja',
          primary: true,
          onTap: () => showFichajeScannerSheet(context),
        ),
      ],
    );
  }
}

class _HomeButton extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool primary;
  final bool disabled;
  final int? badge;
  final VoidCallback? onTap;

  const _HomeButton({
    required this.emoji,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.primary = false,
    this.disabled = false,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppColors.navy : AppColors.soft;
    final titleColor = primary ? Colors.white : AppColors.ink;
    final subColor = primary ? const Color(0xFFB9B9C6) : AppColors.muted;

    final button = SizedBox(
      width: double.infinity,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: disabled ? null : onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: primary ? 26 : 20),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(subtitle, style: TextStyle(color: subColor, fontSize: 12)),
                    ],
                  ),
                ),
                // 카트 수량 badge (0 이면 숨김)
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: AppColors.navy2,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        fontFeatures: kTabularFigures,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    // 잠금 상태는 흐리게 표시(작업 게이트 UX).
    return disabled ? Opacity(opacity: 0.45, child: button) : button;
  }
}
