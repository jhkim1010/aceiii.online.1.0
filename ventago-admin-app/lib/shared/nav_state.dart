import 'package:flutter_riverpod/flutter_riverpod.dart';

// AppShell 탭 인덱스 — 다른 화면(대시보드 카드 등)에서 탭 이동을 위해 provider로 관리.
// 0=Panel 1=Diagnóstico 2=Sesiones 3=Clientes 4=Mensajes 5=Actividad 6=Aprobaciones
final navIndexProvider = StateProvider<int>((ref) => 0);
