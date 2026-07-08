import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'orders_screen.dart';
import 'despacho_tab.dart';
import 'entrega_tab.dart';

/// 상단 역할 토글 shell — Preparación(준비) ↔ Despacho(발송) 전환.
/// 토글 자체가 현재 역할을 표시하므로 별도 제목 줄 없이 AppBar 한 줄로 합침(공간 절약).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _role = 0; // 0 = Preparación, 1 = Despacho, 2 = Entrega

  void _refreshCurrent() {
    switch (_role) {
      case 0:
        ref.invalidate(preparingOrdersProvider);
        break;
      case 1:
        ref.invalidate(listoOrdersProvider);
        break;
      default:
        ref.invalidate(enviadoOrdersProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        centerTitle: true,
        titleSpacing: 0,
        title: SegmentedButton<int>(
          segments: const [
            ButtonSegment<int>(value: 0, label: Text('Preparar'), icon: Icon(Icons.inventory_2)),
            ButtonSegment<int>(value: 1, label: Text('Despachar'), icon: Icon(Icons.local_shipping)),
            ButtonSegment<int>(value: 2, label: Text('Entregar'), icon: Icon(Icons.assignment_turned_in)),
          ],
          selected: {_role},
          onSelectionChanged: (s) => setState(() => _role = s.first),
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            backgroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFFF5A623)
                  : Colors.white24,
            ),
            foregroundColor: WidgetStateProperty.resolveWith(
              (states) => states.contains(WidgetState.selected)
                  ? const Color(0xFF0F0F1E)
                  : Colors.white,
            ),
          ),
        ),
        actions: [
          // 현재 작업자 — 탭하면 교대(operario 전환).
          TextButton.icon(
            onPressed: () => ref.read(operarioProvider.notifier).clear(),
            icon: const Icon(Icons.person, color: Colors.white, size: 18),
            label: Text(
              ref.watch(operarioProvider)?.name ?? '',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _refreshCurrent,
          ),
          IconButton(
            tooltip: 'Cerrar sesión (cambiar operario)',
            icon: const Icon(Icons.logout),
            // 작업자만 해제 → "¿Quién sos?" 로. 기기 토큰은 유지(재입력 불필요).
            // 기기 자체 재설정은 그 화면의 ⚙ 아이콘에서.
            onPressed: () => ref.read(operarioProvider.notifier).clear(),
          ),
        ],
      ),
      body: _role == 0
          ? const PreparacionTab()
          : _role == 1
              ? const DespachoTab()
              : const EntregaTab(),
    );
  }
}
