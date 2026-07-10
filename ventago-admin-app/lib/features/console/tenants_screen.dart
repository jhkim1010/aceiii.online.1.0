import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

class TenantsScreen extends ConsumerWidget {
  const TenantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tenantsProvider);
    final fmt = NumberFormat.decimalPattern('es_AR');

    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(tenantsProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.red))),
        data: (rows) {
          final subsEnabled = rows.isNotEmpty && rows.first.subscriptionEnabled;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text('Clientes (Tenants)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              if (!subsEnabled)
                const Card(
                  color: Color(0xFF23324f),
                  child: Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('Suscripción no activa — managem. estimado (lista de precios).',
                        style: TextStyle(color: AppColors.dim, fontSize: 12)),
                  ),
                ),
              const SizedBox(height: 8),
              ...rows.map((t) => Card(
                    child: ListTile(
                      title: Text(t.storeName, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${t.branches} suc · ${t.terminals} term · ${t.salesMonth} ventas/mes · \$${fmt.format(t.revenueMonth)}\nmanagem. est. \$${fmt.format(t.expectedFee)}',
                        style: const TextStyle(color: AppColors.dim, fontSize: 12),
                      ),
                      isThreeLine: true,
                      trailing: t.errors24h > 0
                          ? Chip(
                              backgroundColor: Colors.transparent,
                              side: const BorderSide(color: AppColors.red),
                              label: Text('${t.errors24h} err', style: const TextStyle(color: AppColors.red, fontSize: 12)),
                            )
                          : const Text('0', style: TextStyle(color: AppColors.dim)),
                    ),
                  )),
            ],
          );
        },
      ),
    );
  }
}
