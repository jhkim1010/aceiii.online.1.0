import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'providers/app_providers.dart';
import 'screens/login_screen.dart';
import 'screens/orders_screen.dart';

void main() {
  runApp(const ProviderScope(child: DespachoApp()));
}

class DespachoApp extends ConsumerWidget {
  const DespachoApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    // 다크 네이비 + 골드 (Ventago 테마 규약).
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFF5A623),
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: const Color(0xFFF6F6FA),
    );

    return MaterialApp(
      title: AppConfig.appTitle,
      debugShowCheckedModeBanner: false,
      theme: theme,
      home: auth.isAuthenticated ? const OrdersScreen() : const LoginScreen(),
    );
  }
}
