import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

// Clientes borrados — soft-delete 된 매장 목록 + 복구.
class BorradosScreen extends ConsumerWidget {
  const BorradosScreen({super.key});

  String _fecha(DateTime? d) {
    if (d == null) return 'sin fecha';
    final l = d.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(l.day)}/${two(l.month)}/${l.year} ${two(l.hour)}:${two(l.minute)}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(deletedTenantsProvider);

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: const Text('Clientes borrados'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.red))),
        data: (rows) {
          if (rows.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(30),
                child: Text('No hay clientes borrados', style: TextStyle(color: AppColors.dim)),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(deletedTenantsProvider),
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                Text('${rows.length} cliente(s) borrado(s)',
                    style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                const SizedBox(height: 10),
                ...rows.map((t) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: AppColors.panel,
                        border: Border.all(color: AppColors.line),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(t.storeName,
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 3),
                            Text('store #${t.storeId} · eliminado ${_fecha(t.deletedAt)}',
                                style: const TextStyle(color: AppColors.dim, fontSize: 11.5)),
                          ]),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _confirmRestore(context, ref, t),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.green,
                            foregroundColor: AppColors.navy,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          icon: const Icon(Icons.restore, size: 17),
                          label: const Text('Restaurar', style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ]),
                    )),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmRestore(BuildContext context, WidgetRef ref, DeletedTenant t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.panel,
        title: const Text('Restaurar cliente'),
        content: Text('¿Restaurar "${t.storeName}"? Volverá a Clientes y su personal podrá iniciar sesión de nuevo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: AppColors.navy),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(consoleRepositoryProvider).restoreStore(t.storeId);
      ref.invalidate(deletedTenantsProvider);
      ref.invalidate(tenantsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.green,
          content: Text('${t.storeName} restaurado.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: AppColors.red,
          content: Text('No se pudo restaurar: $e'),
        ));
      }
    }
  }
}
