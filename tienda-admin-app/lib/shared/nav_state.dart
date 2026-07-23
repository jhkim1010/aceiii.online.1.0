import 'package:flutter_riverpod/flutter_riverpod.dart';

// AppShell 탭 인덱스 — 다른 화면(Panel 카드 등)에서 탭 이동을 위해 provider로 관리.
// 0=Panel 1=Caja 2=Reportes 3=Usuarios 4=Actividad
final navIndexProvider = StateProvider<int>((ref) => 0);
