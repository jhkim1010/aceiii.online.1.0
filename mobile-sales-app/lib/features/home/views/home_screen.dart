// S1 Home (/home) — vendedor 랜딩. 3버튼(Buscar / Ver carrito / Escanear QR).
// scope 로 "Hola, {nombre}" + 매장·지점 표시. 상세 판매 화면은 Wave 4 에서 채운다.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/providers/scope_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scope = ref.watch(scopeNotifierProvider).value;
    final user = switch (scope) {
      BranchScope(:final user) => user,
      MultiStoreScope(:final user) => user,
      _ => null,
    };
    final name = user?.name ?? 'Vendedor';
    final store = user?.storeName ?? '';
    final branch = user?.branchName ?? '';

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
            // 3버튼
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
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
                      onTap: () => context.push('/comanda'),
                    ),
                    const Spacer(),
                    // QR = primary big (navy)
                    _HomeButton(
                      emoji: '▣',
                      title: 'Escanear QR',
                      subtitle: 'Leé la percha y probá al instante',
                      primary: true,
                      onTap: () => context.push('/catalog'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeButton extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _HomeButton({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = primary ? AppColors.navy : AppColors.soft;
    final titleColor = primary ? Colors.white : AppColors.ink;
    final subColor = primary ? const Color(0xFFB9B9C6) : AppColors.muted;

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: primary ? 26 : 20),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 16),
                Column(
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
