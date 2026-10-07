import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import 'pedido_hilo_screen.dart';
import 'pedidos_repository.dart';

// [2026-10-07 pedido del usuario] Bandeja de «Pedidos a Ventago» de todas las tiendas —
// lo mismo que /admin/pedidos en la web: ver, responder, cambiar estado y tildar renglones.
final pedidosPlataformaProvider = Provider<PedidosRepository>(
  (ref) => PedidosRepository(ref.read(dioClientProvider), '/pedidos-soporte/plataforma'),
);

class PedidosScreen extends ConsumerStatefulWidget {
  const PedidosScreen({super.key});

  @override
  ConsumerState<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends ConsumerState<PedidosScreen> {
  // null = pendientes (abierto + en curso), igual que la bandeja web
  String? _estado;
  String _q = '';
  Timer? _debounce;
  List<PedidoResumen>? _lista;
  String? _error;
  bool _cargando = false;
  // [codex 043] sólo la última carga escribe: un filtro viejo que vuelve tarde no pisa al nuevo
  int _gen = 0;

  static const _filtros = [
    (null, 'Pendientes'),
    ('abierto', 'Abiertos'),
    ('en_curso', 'En curso'),
    ('resuelto', 'Resueltos'),
    ('todos', 'Todos'),
  ];

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _cargar() async {
    if (!mounted) return;
    final gen = ++_gen;
    setState(() => _cargando = true);
    try {
      final l = await ref.read(pedidosPlataformaProvider).listar(estado: _estado, q: _q);
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
  }

  Future<void> _abrir(PedidoResumen p) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => PedidoHiloScreen(repo: ref.read(pedidosPlataformaProvider), id: p.id)),
    );
    // al abrirlo deja de estar «sin leer» aunque no haya cambiado nada → siempre recargar
    if (mounted) await _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _lista;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar por asunto o tienda',
              isDense: true,
            ),
            onChanged: (v) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 400), () {
                _q = v;
                _cargar();
              });
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _filtros
                .map((f) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: ChoiceChip(
                        label: Text(f.$2),
                        selected: _estado == f.$1,
                        onSelected: (_) {
                          setState(() => _estado = f.$1);
                          _cargar();
                        },
                      ),
                    ))
                .toList(),
          ),
        ),
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
                              child: Text('No hay pedidos.', style: TextStyle(color: AppColors.dim)),
                            ),
                          ])
                        : ListView.separated(
                            itemCount: lista.length,
                            separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.line),
                            itemBuilder: (_, i) => _fila(lista[i]),
                          ),
          ),
        ),
      ],
    );
  }

  Widget _fila(PedidoResumen p) {
    return ListTile(
      onTap: () => _abrir(p),
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
          p.tienda ?? '',
          if (p.sucursal != null) p.sucursal!,
          etiquetaCategoria(p.categoria),
          if (p.itemsTotal > 0) '${p.itemsHechos}/${p.itemsTotal}',
        ].where((s) => s.isNotEmpty).join(' · '),
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
