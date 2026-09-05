import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';
import 'errores_screen.dart';
import 'onboarding_repository.dart';
import 'facturacion_repository.dart';
import '../../shared/nav_state.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenants = ref.watch(tenantsProvider);
    final sessions = ref.watch(sessionsProvider);
    final pending = ref.watch(pendingRegistrationsProvider);
    // 오류 카드는 세부 화면과 같은 소스(전 매장 24h 5xx, store_id NULL 인 로그인 실패 포함)를
    // 써야 카드 숫자와 세부 목록이 일치한다. tenants.errors24h 합계는 매장귀속분만 세어 불일치.
    final recentErrors = ref.watch(recentErrorsProvider);
    // [2026-09-05] 전자 영수증 인증서 — 7일 이내 갱신 대상.
    // ★ 판정은 **서버가** 한다(`porRenovar`). 앱이 daysLeft 를 다시 재면
    //   목록과 배지가 갈라진다.
    final facElec = ref.watch(facElectronicaProvider);

    final online = sessions.maybeWhen(data: (s) => s.where((x) => x.status == 'online').length, orElse: () => 0);
    final errors = recentErrors.maybeWhen(data: (l) => l.length, orElse: () => 0);
    final clients = tenants.maybeWhen(data: (t) => t.length, orElse: () => 0);
    // 승인 대기 건수 — 0 이 아니면 강조. 탭하면 승인 화면(6)으로 이동.
    final aprobaciones = pending.maybeWhen(data: (p) => p.length, orElse: () => 0);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tenantsProvider);
        ref.invalidate(sessionsProvider);
        ref.invalidate(pendingRegistrationsProvider);
        ref.invalidate(recentErrorsProvider);
        ref.invalidate(facElectronicaProvider);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Dashboard', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          // ★★ 경보는 **그리드 위**에 둔다. 인증서가 만료되면 그 매장은 영수증을
          //   못 끊는다 — 스크롤해야 보이는 자리에 두면 미리 아는 뜻이 없다.
          facElec.maybeWhen(
            data: (r) => r.porRenovar == 0
                ? const SizedBox.shrink()
                : _avisoCert(context, ref, r),
            orElse: () => const SizedBox.shrink(),
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.7,
            children: [
              GestureDetector(
                // 대시보드 Clientes 카드 더블탭 → Clientes 리스트 탭(3)으로 이동
                onDoubleTap: () => ref.read(navIndexProvider.notifier).state = 3,
                child: _kpi('Clientes', '$clients', AppColors.txt),
              ),
              _kpi('Empleados online', '$online', AppColors.green),
              GestureDetector(
                // Errores 24h 더블탭 → 오류 세부 목록 화면
                onDoubleTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ErroresScreen()),
                ),
                child: _kpi(
                  'Errores 24h',
                  '$errors',
                  errors > 0 ? AppColors.red : AppColors.txt,
                  hint: errors > 0 ? 'Doble toque: detalle' : null,
                ),
              ),
              GestureDetector(
                // 승인 대기 카드 → 탭 1번으로 승인 화면(6)으로 이동.
                // 승인해야 매장+계정이 생성되므로 대기 중이면 신청자는 로그인 불가.
                onTap: () => ref.read(navIndexProvider.notifier).state = 6,
                child: _kpi(
                  'Aprobaciones',
                  '$aprobaciones',
                  aprobaciones > 0 ? AppColors.gold : AppColors.txt,
                  hint: aprobaciones > 0 ? 'Tocar para revisar' : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 7일 이내(만료 포함) 갱신이 필요한 인증서 경보. 탭하면 목록 탭(8)으로 간다.
  Widget _avisoCert(BuildContext context, WidgetRef ref, FacElectronicaResult r) {
    final vencidos = r.items.where((i) => i.estado == EstadoCert.vencido).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: const Color(0xFF3A1E1E),
        child: ListTile(
          onTap: () => ref.read(navIndexProvider.notifier).state = 8,
          leading: const Icon(Icons.warning_amber_rounded,
              color: AppColors.red, size: 32),
          title: Text(
            'Fac. electrónica: ${r.porRenovar} por renovar',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            vencidos > 0
                ? '$vencidos ya vencido(s) — no pueden facturar'
                : 'Vence(n) dentro de ${r.diasAviso} días · tocar para ver',
            style: const TextStyle(color: AppColors.dim, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: AppColors.dim),
        ),
      ),
    );
  }

  Widget _kpi(String label, String value, Color color, {String? hint}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label.toUpperCase(), style: const TextStyle(color: AppColors.dim, fontSize: 11)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.w800)),
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(hint, style: const TextStyle(color: AppColors.gold, fontSize: 10)),
              ),
          ],
        ),
      ),
    );
  }
}
