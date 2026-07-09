// 앱 라우터 — go_router + scope(인증) 기반 redirect + 세션만료 신호 반영.
// 미인증/세션만료 → /login, 인증 → /home. 판매 화면은 Wave 4 에서 채운다.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/network/session_signal.dart';
import '../features/auth/providers/scope_provider.dart';
import '../features/auth/views/login_screen.dart';
import '../features/catalog/data/catalog_dto.dart';
import '../features/catalog/views/catalog_screen.dart';
import '../features/cart/views/comanda_screen.dart';
import '../features/done/views/done_screen.dart';
import '../features/home/views/home_screen.dart';
import '../features/product/views/product_detail_screen.dart';

// GoRouter Provider — scope 상태 + 세션만료 신호 변화 시 자동 리다이렉트
final appRouterProvider = Provider<GoRouter>((ref) {
  final sessionSignal = ref.read(sessionExpiredSignalProvider);

  return GoRouter(
    initialLocation: '/login',
    // 세션만료 신호가 바뀌면 redirect 재평가 (MOBILE-C-07)
    refreshListenable: sessionSignal,
    redirect: (context, state) {
      final scopeState = ref.read(scopeNotifierProvider);
      final isLoginRoute = state.matchedLocation == '/login';

      // 앱 시작 시 scope 복원 로딩 중에는 보류
      if (scopeState.isLoading) {
        return null;
      }

      // 세션 만료 신호 → 무조건 로그인으로
      if (sessionSignal.expired && !isLoginRoute) {
        return '/login';
      }

      final scope = scopeState.value;
      final isAuthenticated = scope != null && scope is! ScopeUnauthenticated;

      // 미인증 상태에서 보호 경로 접근 → 로그인
      if (!isAuthenticated && !isLoginRoute) {
        return '/login';
      }

      // 인증 상태에서 로그인 화면 접근 → 홈
      if (isAuthenticated && isLoginRoute) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const HomeScreen(),
      ),
      // ── Wave 4 판매 플로우 스텁 (S2~S5) ──
      GoRoute(
        path: '/catalog',
        builder: (context, state) => const CatalogScreen(),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (context, state) {
          final id = int.tryParse(state.pathParameters['id'] ?? '') ?? 0;
          // 카탈로그에서 넘어온 CatalogItem(hero/price). QR 직행 시 null → 캐시 역참조.
          final extra = state.extra;

          return ProductDetailScreen(
            productId: id,
            item: extra is CatalogItem ? extra : null,
          );
        },
      ),
      GoRoute(
        path: '/comanda',
        builder: (context, state) => const ComandaScreen(),
      ),
      GoRoute(
        path: '/done',
        builder: (context, state) {
          final extra = state.extra;

          return DoneScreen(args: extra is DoneArgs ? extra : null);
        },
      ),
    ],
  );
});
