// Fichaje 결과 화면 — punch 성공 후 role 로 분기(스펙 §모바일 앱 L141-147).
//  action 'in'  → "Entrada registrada HH:mm"
//  action 'out' → "Salida registrada HH:mm · Hoy Xh Ym"
//  action 'store_authorized' → "Tienda {name} habilitada" + 카탈로그 개방 CTA(revendedor)
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../data/attendance_dto.dart';

// ISO 타임스탬프 → "HH:mm" (로컬 표시). 파싱 실패 시 빈 문자열.
String formatHhmm(String? iso) {
  if (iso == null || iso.isEmpty) {
    return '';
  }
  final dt = DateTime.tryParse(iso);
  if (dt == null) {
    return '';
  }
  final local = dt.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');

  return '$hh:$mm';
}

// 근무 초 → "Xh Ym" (스펙 카피). 음수/null 방어.
String formatWorked(int? seconds) {
  final s = (seconds ?? 0) < 0 ? 0 : (seconds ?? 0);
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;

  return '${h}h ${m}m';
}

class FichajeResultScreen extends StatelessWidget {
  final PunchResult? result;

  const FichajeResultScreen({super.key, this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: r == null ? _fallback(context) : _body(context, r),
          ),
        ),
      ),
    );
  }

  // 결과 누락(딥링크 직접 진입 등) 방어.
  Widget _fallback(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Fichaje registrado',
              style: TextStyle(color: AppColors.ink, fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/home'),
            child: const Text('Volver'),
          ),
        ],
      );

  Widget _body(BuildContext context, PunchResult r) {
    if (r.isStoreAuthorized) {
      return _storeAuthorized(context, r);
    }
    if (r.isOut) {
      return _out(context, r);
    }

    return _in(context, r);
  }

  // entrada — 초록 체크 + "Entrada registrada HH:mm"
  Widget _in(BuildContext context, PunchResult r) {
    final time = formatHhmm(r.at);
    final branch = r.branchName;

    return _Card(
      color: AppColors.green,
      icon: Icons.login,
      title: 'Entrada registrada${time.isEmpty ? '' : ' $time'}',
      subtitle: branch == null ? 'Buen trabajo' : 'Sucursal $branch',
      primaryLabel: 'Empezar a vender',
      onPrimary: () => context.go('/home'),
    );
  }

  // salida — "Salida registrada HH:mm · Hoy Xh Ym"
  Widget _out(BuildContext context, PunchResult r) {
    final time = formatHhmm(r.at);
    final worked = formatWorked(r.todayWorkedSeconds);

    return _Card(
      color: AppColors.navy,
      icon: Icons.logout,
      title: 'Salida registrada${time.isEmpty ? '' : ' $time'}',
      subtitle: 'Hoy $worked',
      primaryLabel: 'Volver',
      onPrimary: () => context.go('/home'),
    );
  }

  // store_authorized (revendedor) — "Tienda {name} habilitada" + 카탈로그 개방
  Widget _storeAuthorized(BuildContext context, PunchResult r) {
    final name = r.storeName ?? '';

    return _Card(
      color: AppColors.gold,
      iconColor: AppColors.navy2,
      icon: Icons.storefront,
      title: name.isEmpty ? 'Tienda habilitada' : 'Tienda $name habilitada',
      subtitle: 'Ya podés ver el catálogo de esta tienda',
      primaryLabel: 'Ver catálogo',
      onPrimary: () => context.go('/catalog'),
    );
  }
}

// 결과 카드 공용 룩 (아이콘 링 + 제목 + 부제 + CTA).
class _Card extends StatelessWidget {
  final Color color;
  final Color? iconColor;
  final IconData icon;
  final String title;
  final String subtitle;
  final String primaryLabel;
  final VoidCallback onPrimary;

  const _Card({
    required this.color,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.primaryLabel,
    required this.onPrimary,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Icon(icon, color: iconColor ?? Colors.white, size: 40),
        ),
        const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.ink, fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.muted, fontSize: 14),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            onPressed: onPrimary,
            child: Text(primaryLabel),
          ),
        ),
      ],
    );
  }
}
