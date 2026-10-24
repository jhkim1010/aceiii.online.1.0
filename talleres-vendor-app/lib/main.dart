// 앱 진입점 — ProviderScope로 Riverpod 상태관리 초기화
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/update/actualizacion.dart';
import 'router/app_router.dart';

void main() {
  runApp(
    // 전체 앱을 ProviderScope로 감싸 Riverpod 활성화
    const ProviderScope(child: TalleresVendorApp()),
  );
  // 첫 화면이 뜬 뒤 1회 — 새 버전이 있으면 묻는다(절대 혼자 설치하지 않음). Android 전용.
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => chequearActualizacion(rootNavigatorKey, feedUrl: _feedActualizacion),
  );
}

// [2026-10-24] 새 버전 안내 — build-apk.sh 가 이 주소에 version.json 을 올린다
const _feedActualizacion =
    'https://github.com/jhkim1010/ventago-downloads/releases/download/talleres-vendor-app-latest/version.json';

// 루트 앱 위젯 — ConsumerWidget으로 router Provider 구독
class TalleresVendorApp extends ConsumerWidget {
  const TalleresVendorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Portal de Talleres',
      theme: ThemeData(
        // 기본 색상 시드 — Material 3 색상 체계 사용
        colorSchemeSeed: const Color(0xFF1976D2),
        useMaterial3: true,
      ),
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
