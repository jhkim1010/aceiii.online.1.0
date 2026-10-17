import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

// Detalle de la tarjeta «Locales trabajando»: qué sucursales tienen gente ahora.
class LocalesActivosScreen extends ConsumerWidget {
  const LocalesActivosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(localesActivosProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Locales trabajando')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(localesActivosProvider),
        child: datos.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(padding: const EdgeInsets.all(16), child: Text('Error: $e')),
          ]),
          data: (r) => ListView(
            padding: const EdgeInsets.all(12),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  '${r.locales} local(es) · ${r.tiendas} tienda(s) · ${r.usuarios} usuario(s) — últimos ${r.ventanaMin} min',
                  style: const TextStyle(color: AppColors.dim, fontSize: 12),
                ),
              ),
              if (r.detalle.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Nadie trabajando en este momento.'),
                ),
              for (final l in r.detalle)
                Card(
                  child: ListTile(
                    dense: true,
                    title: Text(l.tienda, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(l.sucursal ?? 'Sin sucursal',
                        style: const TextStyle(color: AppColors.dim)),
                    trailing: Text('${l.usuarios}',
                        style: const TextStyle(
                            color: AppColors.green, fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
