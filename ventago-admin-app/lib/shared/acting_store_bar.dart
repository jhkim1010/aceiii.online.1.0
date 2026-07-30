import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/tenant/acting_store.dart';
import '../core/theme/app_theme.dart';
import '../features/console/console_repository.dart';

// [Phase 67-C] 매장 대행 배너 + 매장 선택 시트
//
// 대행 중에는 백엔드가 superadmin 을 그 매장 사용자와 동일하게 취급한다.
// 켜 둔 걸 잊고 작업하면 남의 매장에 데이터를 만들게 되므로 화면 하단에
// 항상 보이게 고정하고, 한 번에 해제할 수 있게 한다.

class ActingStoreBar extends ConsumerWidget {
  const ActingStoreBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acting = ref.watch(actingStoreProvider);
    if (acting == null) {
      return const SizedBox.shrink();
    }

    return Material(
      color: AppColors.gold,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Colors.black87, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Actuando como ${acting.name} (#${acting.id})',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => showActingStorePicker(context, ref),
                child: const Text('Cambiar', style: TextStyle(color: Colors.black87)),
              ),
              TextButton(
                onPressed: () => ref.read(actingStoreProvider.notifier).stop(),
                child: const Text('Salir',
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 매장 선택 시트 — 테넌트 목록에서 하나를 골라 대행을 시작한다.
Future<void> showActingStorePicker(BuildContext context, WidgetRef ref) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.navy2,
    isScrollControlled: true,
    builder: (ctx) => const _ActingStorePickerSheet(),
  );
}

class _ActingStorePickerSheet extends ConsumerStatefulWidget {
  const _ActingStorePickerSheet();

  @override
  ConsumerState<_ActingStorePickerSheet> createState() => _ActingStorePickerSheetState();
}

class _ActingStorePickerSheetState extends ConsumerState<_ActingStorePickerSheet> {
  List<Tenant> _tenants = const [];
  bool _loading = true;
  String? _error;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repo = ref.read(consoleRepositoryProvider);
      final list = await repo.getTenants();
      if (!mounted) return;
      setState(() {
        _tenants = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudieron cargar las tiendas';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final acting = ref.watch(actingStoreProvider);
    final visible = _tenants
        .where((t) => t.storeName.toLowerCase().contains(_filter.trim().toLowerCase()))
        .toList();

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Actuar como tienda',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Mientras esté activo, todas las consultas y ediciones se harán como un usuario de esa tienda. Queda registrado en la auditoría.',
              style: TextStyle(color: AppColors.dim, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Buscar tienda…',
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 320,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(child: Text(_error!, style: const TextStyle(color: AppColors.dim)))
                      : ListView.builder(
                          itemCount: visible.length,
                          itemBuilder: (_, i) {
                            final t = visible[i];
                            final selected = acting?.id == t.storeId;

                            return ListTile(
                              dense: true,
                              selected: selected,
                              leading: const Icon(Icons.storefront_outlined),
                              title: Text(t.storeName),
                              subtitle: Text('#${t.storeId}',
                                  style: const TextStyle(color: AppColors.dim, fontSize: 11)),
                              trailing: selected ? const Icon(Icons.check) : null,
                              onTap: () {
                                ref
                                    .read(actingStoreProvider.notifier)
                                    .actAs(t.storeId, t.storeName);
                                Navigator.pop(context);
                              },
                            );
                          },
                        ),
            ),
            if (acting != null)
              TextButton(
                onPressed: () {
                  ref.read(actingStoreProvider.notifier).stop();
                  Navigator.pop(context);
                },
                child: const Text('Dejar de actuar'),
              ),
          ],
        ),
      ),
    );
  }
}
