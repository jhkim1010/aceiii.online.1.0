import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import 'nuevo_pedido_screen.dart';
import 'pedido_hilo_screen.dart';
import 'pedidos_repository.dart';

// [2026-10-07 pedido del usuario] «Pedidos a Ventago» desde el celular del admin de la tienda:
// escribir una nota nueva, ver las propias y seguir el hilo con Ventago. Mismo endpoint que la
// web (/pedidos-soporte); qué ve cada uno lo decide el servidor (admin/gerente: toda la tienda).
final pedidosTiendaProvider = Provider<PedidosRepository>(
  (ref) => PedidosRepository(ref.read(dioClientProvider), '/pedidos-soporte'),
);

/// Cuántos pedidos tienen respuesta de Ventago sin leer (el globito del ícono).
final pedidosNoLeidosProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.read(pedidosTiendaProvider).noLeidos(),
);

class PedidosScreen extends ConsumerStatefulWidget {
  const PedidosScreen({super.key});

  @override
  ConsumerState<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends ConsumerState<PedidosScreen> {
  List<PedidoResumen>? _lista;
  String? _error;
  bool _cargando = false;
  // [codex 043] sólo la última carga escribe: un filtro viejo que vuelve tarde no pisa al nuevo
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    final gen = ++_gen;
    setState(() => _cargando = true);
    try {
      final l = await ref.read(pedidosTiendaProvider).listar();
      if (mounted && gen == _gen) {
        setState(() {
          _lista = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted && gen == _gen) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted && gen == _gen) setState(() => _cargando = false);
    }
    if (mounted) ref.invalidate(pedidosNoLeidosProvider);
  }

  Future<void> _abrir(int id) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PedidoHiloScreen(repo: ref.read(pedidosTiendaProvider), id: id)),
    );
    if (mounted) await _cargar();
  }

  Future<void> _nuevo() async {
    final id = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const NuevoPedidoScreen()),
    );
    if (id == null || !mounted) return;
    await _cargar();
    if (mounted) _abrir(id);
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista;

    return Scaffold(
      appBar: AppBar(backgroundColor: AppColors.navy2, title: const Text('Pedidos a Ventago')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.edit_note),
        label: const Text('Nuevo pedido'),
        onPressed: _nuevo,
      ),
      body: Column(
        children: [
          if (_cargando) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _cargar,
              child: _error != null && lista == null
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!, style: const TextStyle(color: AppColors.red)),
                      ),
                    ])
                  : lista == null
                      ? const SizedBox.shrink()
                      : lista.isEmpty
                          ? ListView(children: const [
                              Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'Todavía no hay pedidos.\nTocá «Nuevo pedido» para pedir una mejora, '
                                  'una reparación o que corrijamos un error.',
                                  style: TextStyle(color: AppColors.dim),
                                ),
                              ),
                            ])
                          : ListView.separated(
                              padding: const EdgeInsets.only(bottom: 88),
                              itemCount: lista.length,
                              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.line),
                              itemBuilder: (_, i) => _fila(lista[i]),
                            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fila(PedidoResumen p) {
    return ListTile(
      onTap: () => _abrir(p.id),
      leading: Icon(
        p.noLeido ? Icons.mark_email_unread : Icons.mail_outline,
        color: p.noLeido ? AppColors.gold : AppColors.dim,
      ),
      title: Text(
        p.asunto,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: p.noLeido ? FontWeight.w800 : FontWeight.w500),
      ),
      subtitle: Text(
        [
          etiquetaCategoria(p.categoria),
          if (p.autor != null) p.autor!,
          if (p.itemsTotal > 0) '${p.itemsHechos}/${p.itemsTotal}',
        ].join(' · '),
        style: const TextStyle(color: AppColors.dim, fontSize: 12),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          EstadoChip(p.estado),
          const SizedBox(height: 4),
          Text(fechaCorta(p.ultimoMensaje), style: const TextStyle(color: AppColors.dim, fontSize: 11)),
        ],
      ),
    );
  }
}
