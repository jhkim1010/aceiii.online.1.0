Reading additional input from stdin...
2026-10-07T18:34:51.570422Z ERROR codex_models_manager::cache: failed to load models cache: missing field `base_instructions` at line 140 column 5
OpenAI Codex v0.146.0
--------
workdir: /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: none
reasoning summaries: none
session id: 01a117a5-9cf9-7c02-9381-86b6786aae22
--------
user
Revisá este código Flutter nuevo (Riverpod + Dio). Dos apps: ventago-admin-app (superadmin, bandeja de pedidos de todas las tiendas: /pedidos-soporte/plataforma — listar, detalle, responder, PATCH estado, PATCH items, fotos por bytes) y tienda-admin-app (admin de tienda: /pedidos-soporte — listar, crear {categoria,asunto,texto}, detalle, responder). pedidos_repository.dart y pedido_hilo_screen.dart son idénticos en las dos apps (se muestra la copia de ventago-admin-app). El API ya existe (NestJS); el servidor marca leído al pedir el detalle y cambia el estado al responder. Buscá errores concretos: estado de widgets tras await/mounted, doble envío, pérdida de texto, parseo, rutas, setState en dispose, PopScope, uso de ref en ConsumerState tras dispose, Badge/valueOrNull. No estilo. Código:
diff --git a/tienda-admin-app/lib/shared/app_shell.dart b/tienda-admin-app/lib/shared/app_shell.dart
index 2b9a671..db22f54 100644
--- a/tienda-admin-app/lib/shared/app_shell.dart
+++ b/tienda-admin-app/lib/shared/app_shell.dart
@@ -8,6 +8,7 @@ import '../features/reportes/reportes_screen.dart';
 import '../features/usuarios/usuarios_screen.dart';
 import '../features/actividad/actividad_screen.dart';
 import '../features/relojes/relojes_screen.dart';
+import '../features/pedidos/pedidos_screen.dart';
 import 'nav_state.dart';
 
 // 매장 admin 셸 — 폰 하단 5탭 네비게이션.
@@ -65,6 +66,20 @@ class AppShell extends ConsumerWidget {
                 MaterialPageRoute(builder: (_) => const RelojesScreen()),
               ),
             ),
+          // [2026-10-07] Pedidos a Ventago — los endpoints son de la tienda: sin storeId
+          // (superadmin) el servidor los rechaza, así que no se muestra.
+          if (user?.storeId != null)
+            IconButton(
+              icon: Badge(
+                isLabelVisible: (ref.watch(pedidosNoLeidosProvider).valueOrNull ?? 0) > 0,
+                label: Text('${ref.watch(pedidosNoLeidosProvider).valueOrNull ?? 0}'),
+                child: const Icon(Icons.support_agent),
+              ),
+              tooltip: 'Pedidos a Ventago',
+              onPressed: () => Navigator.of(context).push(
+                MaterialPageRoute(builder: (_) => const PedidosScreen()),
+              ),
+            ),
           IconButton(
             icon: const Icon(Icons.logout),
             tooltip: 'Salir',
diff --git a/ventago-admin-app/lib/shared/app_shell.dart b/ventago-admin-app/lib/shared/app_shell.dart
index aca781c..4bac337 100644
--- a/ventago-admin-app/lib/shared/app_shell.dart
+++ b/ventago-admin-app/lib/shared/app_shell.dart
@@ -12,6 +12,7 @@ import '../features/console/mensajes_screen.dart';
 import '../features/console/actividad_screen.dart';
 import '../features/console/aprobaciones_screen.dart';
 import '../features/console/cobranzas_screen.dart';
+import '../features/pedidos/pedidos_screen.dart';
 import 'acting_store_bar.dart';
 import 'nav_state.dart';
 
@@ -34,6 +35,7 @@ class _AppShellState extends ConsumerState<AppShell> {
     (Icons.how_to_reg_outlined, Icons.how_to_reg, 'Aprobaciones'),
     (Icons.point_of_sale_outlined, Icons.point_of_sale, 'Cobranzas'),
     (Icons.receipt_long_outlined, Icons.receipt_long, 'Fac. electrónica'),
+    (Icons.support_agent_outlined, Icons.support_agent, 'Pedidos'),
   ];
 
   Widget _body(int index) => switch (index) {
@@ -45,7 +47,8 @@ class _AppShellState extends ConsumerState<AppShell> {
         5 => const ActividadScreen(),
         6 => const AprobacionesScreen(),
         7 => const CobranzasScreen(),
-        _ => const FacturacionScreen(),
+        8 => const FacturacionScreen(),
+        _ => const PedidosScreen(),
       };
 
   @override
diff --git a/ventago-admin-app/lib/shared/nav_state.dart b/ventago-admin-app/lib/shared/nav_state.dart
index dfe6aa3..d7a7fb7 100644
--- a/ventago-admin-app/lib/shared/nav_state.dart
+++ b/ventago-admin-app/lib/shared/nav_state.dart
@@ -2,4 +2,5 @@ import 'package:flutter_riverpod/flutter_riverpod.dart';
 
 // AppShell 탭 인덱스 — 다른 화면(대시보드 카드 등)에서 탭 이동을 위해 provider로 관리.
 // 0=Panel 1=Diagnóstico 2=Sesiones 3=Clientes 4=Mensajes 5=Actividad 6=Aprobaciones
+// 7=Cobranzas 8=Fac. electrónica 9=Pedidos
 final navIndexProvider = StateProvider<int>((ref) => 0);
=== NEW ventago-admin-app/lib/features/pedidos/pedido_hilo_screen.dart
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'pedidos_repository.dart';

// [2026-10-07] Hilo de un pedido — mismo archivo en las dos apps. La plataforma además
// cambia el estado y tilda los renglones; la tienda sólo lee y responde.
// Devuelve `true` al cerrar si algo cambió (la lista se recarga).

Color colorEstado(String e) => switch (e) {
      'abierto' => AppColors.amber,
      'en_curso' => AppColors.cyan,
      'resuelto' => AppColors.green,
      _ => AppColors.dim,
    };

class EstadoChip extends StatelessWidget {
  final String estado;

  const EstadoChip(this.estado, {super.key});

  @override
  Widget build(BuildContext context) {
    final c = colorEstado(estado);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withValues(alpha: 0.6)),
      ),
      child: Text(etiquetaEstado(estado), style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

String fechaCorta(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  final hoy = DateTime.now();
  final mismoDia = d.year == hoy.year && d.month == hoy.month && d.day == hoy.day;

  return mismoDia ? DateFormat('HH:mm').format(d) : DateFormat('dd/MM HH:mm').format(d);
}

class PedidoHiloScreen extends StatefulWidget {
  final PedidosRepository repo;
  final int id;

  const PedidoHiloScreen({super.key, required this.repo, required this.id});

  @override
  State<PedidoHiloScreen> createState() => _PedidoHiloScreenState();
}

class _PedidoHiloScreenState extends State<PedidoHiloScreen> {
  PedidoDetalle? _p;
  String? _error;
  bool _enviando = false;
  bool _cambio = false;
  final _respuesta = TextEditingController();

  bool get _plataforma => widget.repo.esPlataforma;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _respuesta.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    try {
      final p = await widget.repo.detalle(widget.id);
      if (mounted) {
        setState(() {
          _p = p;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    }
  }

  void _aviso(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.red : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ★ cada acción va al servidor y después se recarga el hilo: el estado que se ve es
  //   siempre el que quedó guardado (el servidor puede cambiarlo, p.ej. al responder).
  Future<void> _hacer(Future<void> Function() accion, {String? ok}) async {
    if (_enviando) return;
    setState(() => _enviando = true);
    try {
      await accion();
      _cambio = true;
      if (ok != null && mounted) _aviso(ok);
      await _cargar();
    } catch (e) {
      if (mounted) _aviso(mensajeDeError(e), error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _responder() async {
    final texto = _respuesta.text.trim();
    if (texto.isEmpty) return;
    await _hacer(() async {
      await widget.repo.responder(widget.id, texto);
      _respuesta.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_cambio);
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.navy2,
          title: Text('Pedido #${widget.id}'),
          actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualizar', onPressed: _cargar)],
        ),
        body: _error != null && p == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error!, style: const TextStyle(color: AppColors.red)),
                ),
              )
            : p == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      if (_enviando) const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _cargar,
                          child: ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              _cabecera(p),
                              if (p.items.isNotEmpty) ...[const SizedBox(height: 12), _items(p)],
                              const SizedBox(height: 16),
                              ...p.mensajes.map(_mensaje),
                            ],
                          ),
                        ),
                      ),
                      _caja(),
                    ],
                  ),
      ),
    );
  }

  Widget _cabecera(PedidoDetalle p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.asunto, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          [
            etiquetaCategoria(p.categoria),
            if (p.tienda != null) p.tienda!,
            if (p.sucursal != null) p.sucursal!,
            if (p.autor != null) p.autor!,
            fechaCorta(p.createdAt),
          ].join(' · '),
          style: const TextStyle(color: AppColors.dim, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (_plataforma)
          // la plataforma decide el estado; el servidor avisa a la tienda y a Telegram
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: estados.map((e) => ButtonSegment(value: e.$1, label: Text(e.$2))).toList(),
            selected: {p.estado},
            onSelectionChanged: _enviando
                ? null
                : (s) => _hacer(
                      () => widget.repo.cambiarEstado(p.id, s.first),
                      ok: 'Estado: ${etiquetaEstado(s.first)}',
                    ),
          )
        else
          EstadoChip(p.estado),
      ],
    );
  }

  Widget _items(PedidoDetalle p) {
    final hechos = p.items.where((i) => i.hecho).length;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Text('Pedidos de la nota · $hechos/${p.items.length}',
                style: const TextStyle(color: AppColors.dim, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          ...p.items.map((i) => CheckboxListTile(
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                value: i.hecho,
                // la tienda ve el avance; tildar es de la plataforma
                onChanged: _plataforma && !_enviando
                    ? (v) => _hacer(() => widget.repo.tildarItem(p.id, i.id, v ?? false))
                    : null,
                title: Text(
                  i.texto,
                  style: TextStyle(
                    fontSize: 13,
                    decoration: i.hecho ? TextDecoration.lineThrough : null,
                    color: i.hecho ? AppColors.dim : null,
                  ),
                ),
                subtitle: i.hecho && i.hechoPor != null
                    ? Text(i.hechoPor!, style: const TextStyle(fontSize: 11, color: AppColors.dim))
                    : null,
              )),
        ],
      ),
    );
  }

  Widget _mensaje(PedidoMensaje m) {
    // lo propio va a la derecha: para la plataforma, sus respuestas; para la tienda, lo suyo
    final propio = m.desdePlataforma == _plataforma;

    return Align(
      alignment: propio ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: m.desdePlataforma ? AppColors.gold.withValues(alpha: 0.12) : AppColors.panel,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: m.desdePlataforma ? AppColors.gold.withValues(alpha: 0.4) : AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m.autor ?? (m.desdePlataforma ? 'Ventago' : 'Tienda')} · ${fechaCorta(m.createdAt)}',
                style: const TextStyle(color: AppColors.dim, fontSize: 11)),
            const SizedBox(height: 4),
            SelectableText(m.texto, style: const TextStyle(fontSize: 14)),
            if (m.fotos > 0) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(m.fotos, (i) => _Foto(repo: widget.repo, id: widget.id, mensajeId: m.id, idx: i)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _caja() {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.navy2,
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _respuesta,
                minLines: 1,
                maxLines: 5,
                maxLength: 5000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Escribí una respuesta…',
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: AppColors.gold),
              tooltip: 'Enviar',
              onPressed: _enviando ? null : _responder,
            ),
          ],
        ),
      ),
    );
  }
}

/// Miniatura de una foto del hilo. Se baja recién al mostrarse; tocándola se ve grande.
class _Foto extends StatefulWidget {
  final PedidosRepository repo;
  final int id, mensajeId, idx;

  const _Foto({required this.repo, required this.id, required this.mensajeId, required this.idx});

  @override
  State<_Foto> createState() => _FotoState();
}

class _FotoState extends State<_Foto> {
  late final Future<Uint8List> _bytes = widget.repo.foto(widget.id, widget.mensajeId, widget.idx);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snap) {
        final box = BoxDecoration(color: AppColors.navy2, borderRadius: BorderRadius.circular(6));
        if (snap.hasError) {
          return Container(width: 84, height: 84, decoration: box, child: const Icon(Icons.broken_image, color: AppColors.dim));
        }
        if (!snap.hasData) {
          return Container(
            width: 84,
            height: 84,
            decoration: box,
            child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }

        return GestureDetector(
          onTap: () => showDialog<void>(
            context: context,
            builder: (_) => Dialog(
              insetPadding: const EdgeInsets.all(8),
              backgroundColor: Colors.black,
              child: InteractiveViewer(child: Image.memory(snap.data!)),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(snap.data!, width: 84, height: 84, fit: BoxFit.cover),
          ),
        );
      },
    );
  }
}
=== NEW ventago-admin-app/lib/features/pedidos/pedidos_repository.dart
import 'dart:typed_data';

import 'package:dio/dio.dart';

// [2026-10-07] Pedidos a Ventago — mismo archivo en ventago-admin-app (bandeja de la
// plataforma) y tienda-admin-app (la tienda). Sólo cambia la base:
//   plataforma → /pedidos-soporte/plataforma   tienda → /pedidos-soporte
// Las reglas (estados, permisos, avisos a Telegram) son del servidor; acá no se decide nada.

// PG count(*)::int llega como int, pero por las dudas — mismo parser tolerante que el resto.
int _asInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('$v') ?? 0);

const categorias = [
  ('mejora', 'Pedir una mejora', 'Algo que el sistema podría hacer mejor o una función que falta.'),
  ('reparacion', 'Reparar una computadora', 'Una PC, impresora o lector que no anda en el local.'),
  ('correccion', 'Corregir un error que cometimos', 'Una venta, un precio o un movimiento cargado mal.'),
];

String etiquetaCategoria(String c) =>
    categorias.firstWhere((x) => x.$1 == c, orElse: () => (c, c, '')).$2;

const estados = [('abierto', 'Abierto'), ('en_curso', 'En curso'), ('resuelto', 'Resuelto')];

String etiquetaEstado(String e) => estados.firstWhere((x) => x.$1 == e, orElse: () => (e, e)).$2;

/// Mensaje legible de un error del servidor (Nest manda `message` string o lista).
String mensajeDeError(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map && d['message'] != null) {
      final m = d['message'];

      return m is List ? m.join('\n') : m.toString();
    }
    if (e.response?.statusCode == 403) return 'No tenés permiso para esto.';
    if (e.type == DioExceptionType.connectionError || e.type == DioExceptionType.connectionTimeout) {
      return 'Sin conexión con el servidor.';
    }
  }

  return 'No se pudo completar.';
}

class PedidoResumen {
  final int id;
  final String categoria, asunto, estado;
  final bool noLeido;
  final String ultimoMensaje;
  final int itemsTotal, itemsHechos;
  final String? autor, tienda, sucursal;

  PedidoResumen.fromJson(Map<String, dynamic> j)
      : id = _asInt(j['id']),
        categoria = (j['categoria'] ?? '').toString(),
        asunto = (j['asunto'] ?? '').toString(),
        estado = (j['estado'] ?? '').toString(),
        noLeido = j['noLeido'] == true,
        ultimoMensaje = (j['ultimoMensaje'] ?? j['createdAt'] ?? '').toString(),
        itemsTotal = _asInt(j['itemsTotal']),
        itemsHechos = _asInt(j['itemsHechos']),
        autor = j['autor'] as String?,
        tienda = j['tienda'] as String?,
        sucursal = j['sucursal'] as String?;
}

class PedidoItem {
  final int id;
  final String texto;
  final bool hecho;
  final String? hechoPor;

  PedidoItem.fromJson(Map<String, dynamic> j)
      : id = _asInt(j['id']),
        texto = (j['texto'] ?? '').toString(),
        hecho = j['hecho'] == true,
        hechoPor = j['hechoPor'] as String?;
}

class PedidoMensaje {
  final int id;
  final bool desdePlataforma;
  final String texto;
  final int fotos;
  final String? autor;
  final String createdAt;

  PedidoMensaje.fromJson(Map<String, dynamic> j)
      : id = _asInt(j['id']),
        desdePlataforma = j['desdePlataforma'] == true,
        texto = (j['texto'] ?? '').toString(),
        fotos = _asInt(j['fotos']),
        autor = j['autor'] as String?,
        createdAt = (j['createdAt'] ?? '').toString();
}

class PedidoDetalle {
  final int id;
  final String categoria, asunto, estado, createdAt;
  final String? tienda, sucursal, autor;
  final List<PedidoItem> items;
  final List<PedidoMensaje> mensajes;

  PedidoDetalle.fromJson(Map<String, dynamic> j)
      : id = _asInt(j['id']),
        categoria = (j['categoria'] ?? '').toString(),
        asunto = (j['asunto'] ?? '').toString(),
        estado = (j['estado'] ?? '').toString(),
        createdAt = (j['createdAt'] ?? '').toString(),
        tienda = j['tienda'] as String?,
        sucursal = j['sucursal'] as String?,
        autor = j['autor'] as String?,
        items = ((j['items'] ?? []) as List).map((e) => PedidoItem.fromJson(e as Map<String, dynamic>)).toList(),
        mensajes =
            ((j['mensajes'] ?? []) as List).map((e) => PedidoMensaje.fromJson(e as Map<String, dynamic>)).toList();
}

class PedidosRepository {
  final Dio _dio;
  final String base;

  PedidosRepository(this._dio, this.base);

  bool get esPlataforma => base.endsWith('/plataforma');

  Future<List<PedidoResumen>> listar({String? estado, String? q, int page = 0}) async {
    final res = await _dio.get<Map<String, dynamic>>(base, queryParameters: {
      'estado': ?estado,
      if (q != null && q.trim().isNotEmpty) 'q': q.trim(),
      'page': page,
    });

    return ((res.data?['items'] ?? []) as List)
        .map((e) => PedidoResumen.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<int> noLeidos() async {
    final res = await _dio.get<Map<String, dynamic>>('$base/no-leidos');

    return _asInt(res.data?['count']);
  }

  Future<PedidoDetalle> detalle(int id) async {
    final res = await _dio.get<Map<String, dynamic>>('$base/$id');

    return PedidoDetalle.fromJson(res.data ?? {});
  }

  /// Sólo la tienda. Sin fotos desde el celular (por ahora): asunto + detalle.
  Future<int> crear({required String categoria, required String asunto, required String texto}) async {
    final res = await _dio.post<Map<String, dynamic>>(base, data: {
      'categoria': categoria,
      'asunto': asunto,
      'texto': texto,
    });

    return _asInt(res.data?['id']);
  }

  Future<void> responder(int id, String texto) => _dio.post('$base/$id/mensajes', data: {'texto': texto});

  /// Sólo plataforma.
  Future<void> cambiarEstado(int id, String estado) => _dio.patch('$base/$id/estado', data: {'estado': estado});

  /// Sólo plataforma.
  Future<void> tildarItem(int id, int itemId, bool hecho) =>
      _dio.patch('$base/$id/items/$itemId', data: {'hecho': hecho});

  /// Las fotos no tienen URL pública: se piden con el token y se muestran en memoria.
  Future<Uint8List> foto(int id, int mensajeId, int idx) async {
    final res = await _dio.get<List<int>>(
      '$base/$id/mensajes/$mensajeId/fotos/$idx',
      options: Options(responseType: ResponseType.bytes),
    );

    return Uint8List.fromList(res.data ?? const []);
  }
}
=== NEW ventago-admin-app/lib/features/pedidos/pedidos_screen.dart
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
    setState(() => _cargando = true);
    try {
      final l = await ref.read(pedidosPlataformaProvider).listar(estado: _estado, q: _q);
      if (mounted) {
        setState(() {
          _lista = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _abrir(PedidoResumen p) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PedidoHiloScreen(repo: ref.read(pedidosPlataformaProvider), id: p.id)),
    );
    // al abrirlo deja de estar «sin leer» aunque no haya cambiado nada → siempre recargar
    _cargar();
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
=== NEW tienda-admin-app/lib/features/pedidos/pedidos_screen.dart
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

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    try {
      final l = await ref.read(pedidosTiendaProvider).listar();
      if (mounted) {
        setState(() {
          _lista = l;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
    ref.invalidate(pedidosNoLeidosProvider);
  }

  Future<void> _abrir(int id) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PedidoHiloScreen(repo: ref.read(pedidosTiendaProvider), id: id)),
    );
    _cargar();
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
=== NEW tienda-admin-app/lib/features/pedidos/nuevo_pedido_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'pedidos_repository.dart';
import 'pedidos_screen.dart';

// [2026-10-07] Nota nueva para Ventago: tipo + asunto + detalle (como la web, sin fotos ni
// lista de renglones por ahora). El servidor valida lo mismo y avisa a Ventago por Telegram.
// Devuelve el id creado.
class NuevoPedidoScreen extends ConsumerStatefulWidget {
  const NuevoPedidoScreen({super.key});

  @override
  ConsumerState<NuevoPedidoScreen> createState() => _NuevoPedidoScreenState();
}

class _NuevoPedidoScreenState extends ConsumerState<NuevoPedidoScreen> {
  String? _categoria;
  final _asunto = TextEditingController();
  final _texto = TextEditingController();
  bool _enviando = false;
  String? _error;

  @override
  void dispose() {
    _asunto.dispose();
    _texto.dispose();
    super.dispose();
  }

  bool get _listo => _categoria != null && _asunto.text.trim().isNotEmpty && _texto.text.trim().isNotEmpty;

  Future<void> _enviar() async {
    if (!_listo || _enviando) return;
    setState(() {
      _enviando = true;
      _error = null;
    });
    try {
      final id = await ref.read(pedidosTiendaProvider).crear(
            categoria: _categoria!,
            asunto: _asunto.text.trim(),
            texto: _texto.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Pedido enviado a Ventago.'),
        behavior: SnackBarBehavior.floating,
      ));
      Navigator.of(context).pop(id);
    } catch (e) {
      // ★ si falla no se pierde lo escrito: queda en el formulario para reintentar
      if (mounted) setState(() => _error = mensajeDeError(e));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(backgroundColor: AppColors.navy2, title: const Text('Nuevo pedido')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('¿Qué necesitás?', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            ...categorias.map((c) => Card(
                  color: _categoria == c.$1 ? AppColors.gold.withValues(alpha: 0.14) : AppColors.panel,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: _categoria == c.$1 ? AppColors.gold : AppColors.line),
                  ),
                  child: ListTile(
                    onTap: _enviando ? null : () => setState(() => _categoria = c.$1),
                    leading: Icon(
                      _categoria == c.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: _categoria == c.$1 ? AppColors.gold : AppColors.dim,
                    ),
                    title: Text(c.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(c.$3, style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                  ),
                )),
            const SizedBox(height: 16),
            TextField(
              controller: _asunto,
              enabled: !_enviando,
              maxLength: 150,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Asunto'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _texto,
              enabled: !_enviando,
              minLines: 5,
              maxLines: 12,
              maxLength: 5000,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Detalle',
                hintText: 'Contanos qué pasa, en qué pantalla, y si podés el número de venta o producto.',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: AppColors.red)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(48),
              ),
              icon: _enviando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: const Text('Enviar a Ventago'),
              onPressed: _listo && !_enviando ? _enviar : null,
            ),
            const SizedBox(height: 8),
            const Text(
              'Para adjuntar capturas de pantalla, usá Pedidos a Ventago en la web.',
              style: TextStyle(color: AppColors.dim, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
warning: `--dangerously-bypass-hook-trust` is enabled. Enabled hooks may run without review for this invocation.
hook: SessionStart
hook: SessionStart
hook: SessionStart
hook: SessionStart Failed
hook: SessionStart Failed
hook: SessionStart Completed
hook: UserPromptSubmit
hook: UserPromptSubmit Completed
codex
Voy a contrastar el diff con las rutas y contratos reales del backend y con las versiones de Flutter/Riverpod del repo. Haré sólo revisión: no voy a modificar archivos.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '1,240p' .team/REVIEW-PROTOCOL.md && sed -n '1,220p' CLAUDE.md && rg -n \"pedidos-soporte|no-leidos|desdePlataforma|itemsHechos|PopScope|valueOrNull\" --glob '"'!**/.dart_tool/**'"' --glob '"'!**/build/**'"' ." in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 172ms:
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.module.ts:4:import { PedidosSoporteController } from './pedidos-soporte.controller';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.module.ts:5:import { PedidosSoporteService } from './pedidos-soporte.service';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:24:import { MAX_FOTO_BYTES, MAX_FOTOS } from './pedidos-soporte-rules';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:28:} from './pedidos-soporte.service';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:48://   /pedidos-soporte/*             → la tienda (función `pedidos-soporte`: admin · gerente · cajero)
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:49://   /pedidos-soporte/plataforma/*  → superadmin · agent (bandeja de todas las tiendas)
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:51:@Controller('pedidos-soporte')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:71:  @Get('plataforma/no-leidos')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:136:  @FunctionGuard('pedidos-soporte', 'read')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:141:  @Get('no-leidos')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:142:  @FunctionGuard('pedidos-soporte', 'read')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:149:  @FunctionGuard('pedidos-soporte', 'create')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:160:  @FunctionGuard('pedidos-soporte', 'read')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:170:  @FunctionGuard('pedidos-soporte', 'create')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:183:  @FunctionGuard('pedidos-soporte', 'create')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts:193:  @FunctionGuard('pedidos-soporte', 'read')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:40:} from './pedidos-soporte-rules';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:97://   esto pasa por modelos (y el guard global sólo le abre /pedidos-soporte/plataforma).
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:180:      desdePlataforma: m.from_platform,
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:220:    desdePlataforma: boolean,
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:232:          desdePlataforma,
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:480:                WHERE i.request_id = r.id AND i.done_at IS NOT NULL) AS "itemsHechos",
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:683:                WHERE i.request_id = r.id AND i.done_at IS NOT NULL) AS "itemsHechos",
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:826:        `[pedidos-soporte] #${id} ítem ${itemId} → ${hecho ? 'hecho' : 'pendiente'}`,
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:903:    this.logger.log(`[pedidos-soporte] #${id} → ${estado}`);
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:932:      .update(`pedidos-soporte-webhook:${botToken}`)
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts:1055:      `[pedidos-soporte] #${id} desde Telegram (${quien || msg.from?.id}): ${comando.tipo}${
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.spec.ts:4:import { PedidosSoporteService } from './pedidos-soporte.service';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.spec.ts:16:} from './pedidos-soporte-rules';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.spec.ts:17:import { estadoTrasTilde, leerItems, MAX_ITEMS } from './pedidos-soporte-rules';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.spec.ts:43:              { key: 'pedidos-soporte/9/x.png', mime: 'image/png' },
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.spec.ts:187:      'pedidos-soporte/9/x.png',
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.spec.ts:227:    expect(minio.uploadFile.mock.calls[0][1]).toMatch(/^pedidos-soporte\/22\//);
./api-ventago/src/app/pedidos-soporte/pedidos-soporte.spec.ts:232:      /^pedidos-soporte\/22\//,
./api-ventago/src/app/pedidos-soporte/pedidos-telegram.controller.ts:12:import { PedidosSoporteService } from './pedidos-soporte.service';
./api-ventago/src/app/pedidos-soporte/pedidos-telegram.controller.ts:19:@Controller('pedidos-soporte/telegram')
./api-ventago/src/app/pedidos-soporte/pedidos-soporte-rules.ts:76:  desdePlataforma: boolean,
./api-ventago/src/app/pedidos-soporte/pedidos-soporte-rules.ts:79:  if (!desdePlataforma && actual === 'resuelto') return 'abierto';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte-rules.ts:81:  if (desdePlataforma && actual === 'abierto') return 'en_curso';
./api-ventago/src/app/pedidos-soporte/pedidos-soporte-rules.ts:137:  return `pedidos-soporte/${storeId}/${uuid}.${MIME_FOTO[mime]}`;

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
codex
Las rutas principales coinciden con el controlador. Ahora estoy verificando los puntos de ciclo de vida y concurrencia contra el código exacto y el analizador; ahí es donde aparecen fallas que los tests del repository no cubren.
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
exec
/bin/zsh -lc "sed -n '45,220p' api-ventago/src/app/pedidos-soporte/pedidos-soporte.controller.ts
sed -n '430,730p' api-ventago/src/app/pedidos-soporte/pedidos-soporte.service.ts
sed -n '1,130p' tienda-admin-app/pubspec.yaml
sed -n '1,130p' ventago-admin-app/pubspec.yaml
nl -ba tienda-admin-app/lib/features/pedidos/pedidos_screen.dart | sed -n '1,190p'
nl -ba ventago-admin-app/lib/features/pedidos/pedidos_screen.dart | sed -n '1,210p'
nl -ba ventago-admin-app/lib/features/pedidos/pedido_hilo_screen.dart | sed -n '75,180p'
nl -ba tienda-admin-app/lib/features/pedidos/nuevo_pedido_screen.dart | sed -n '20,95p'
nl -ba tienda-admin-app/lib/shared/app_shell.dart | sed -n '55,90p'" in /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0
 succeeded in 0ms:
}

// [2026-10-01] Pedidos a Ventago.
//   /pedidos-soporte/*             → la tienda (función `pedidos-soporte`: admin · gerente · cajero)
//   /pedidos-soporte/plataforma/*  → superadmin · agent (bandeja de todas las tiendas)
// ★ Las rutas `plataforma` van ANTES que `:id` para que Nest no lea «plataforma» como id.
@Controller('pedidos-soporte')
export class PedidosSoporteController {
  constructor(private readonly service: PedidosSoporteService) {}

  // ── plataforma ───────────────────────────────────────────────────────────
  @Get('plataforma')
  @Auth(ValidRoles.superadmin, ValidRoles.agent)
  @AgentePermitido()
  listarPlataforma(
    @Query('estado') estado?: string,
    @Query('q') q?: string,
    @Query('page') page?: string,
  ) {
    return this.service.listarPlataforma({
      estado,
      q,
      page: Number(page) || 0,
    });
  }

  @Get('plataforma/no-leidos')
  @Auth(ValidRoles.superadmin, ValidRoles.agent)
  @AgentePermitido()
  noLeidosPlataforma() {
    return this.service.noLeidosPlataforma();
  }

  @Get('plataforma/:id')
  @Auth(ValidRoles.superadmin, ValidRoles.agent)
  @AgentePermitido()
  detallePlataforma(@Param('id', ParseIntPipe) id: number) {
    return this.service.detallePlataforma(id);
  }

  @Post('plataforma/:id/mensajes')
  @HttpCode(201)
  @Auth(ValidRoles.superadmin, ValidRoles.agent)
  @AgentePermitido()
  @UseInterceptors(FOTOS)
  responderPlataforma(
    @GetUser() user: UsuarioPedido,
    @Param('id', ParseIntPipe) id: number,
    @Body() body: Record<string, unknown>,
    @UploadedFiles() files: Express.Multer.File[],
  ) {
    return this.service.responderPlataforma(user, id, body, files ?? []);
  }

  @Patch('plataforma/:id/estado')
  @Auth(ValidRoles.superadmin, ValidRoles.agent)
  @AgentePermitido()
  cambiarEstado(
    @GetUser() user: UsuarioPedido,
    @Param('id', ParseIntPipe) id: number,
    @Body() body: { estado?: string },
  ) {
    return this.service.cambiarEstado(user, id, body?.estado);
  }

  @Patch('plataforma/:id/items/:itemId')
  @Auth(ValidRoles.superadmin, ValidRoles.agent)
  @AgentePermitido()
  tildarItem(
    @GetUser() user: UsuarioPedido,
    @Param('id', ParseIntPipe) id: number,
    @Param('itemId', ParseIntPipe) itemId: number,
    @Body() body: { hecho?: unknown },
  ) {
    return this.service.tildarItem(user, id, itemId, body?.hecho);
  }

  @Get('plataforma/:id/mensajes/:messageId/fotos/:idx')
  @Auth(ValidRoles.superadmin, ValidRoles.agent)
  @AgentePermitido()
  async fotoPlataforma(
    @Param('id', ParseIntPipe) id: number,
    @Param('messageId', ParseIntPipe) messageId: number,
    @Param('idx', ParseIntPipe) idx: number,
    @Res() res: Response,
  ) {
    enviarFoto(res, await this.service.fotoPlataforma(id, messageId, idx));
  }

  // ── tienda ───────────────────────────────────────────────────────────────
  @Get()
  @FunctionGuard('pedidos-soporte', 'read')
  listar(@GetUser() user: UsuarioPedido, @Query('page') page?: string) {
    return this.service.listarTienda(user, Number(page) || 0);
  }

  @Get('no-leidos')
  @FunctionGuard('pedidos-soporte', 'read')
  noLeidos(@GetUser() user: UsuarioPedido) {
    return this.service.noLeidosTienda(user);
  }

  @Post()
  @HttpCode(201)
  @FunctionGuard('pedidos-soporte', 'create')
  @UseInterceptors(FOTOS)
  crear(
    @GetUser() user: UsuarioPedido,
    @Body() body: Record<string, unknown>,
    @UploadedFiles() files: Express.Multer.File[],
  ) {
    return this.service.crear(user, body, files ?? []);
  }

  @Get(':id')
  @FunctionGuard('pedidos-soporte', 'read')
  detalle(
    @GetUser() user: UsuarioPedido,
    @Param('id', ParseIntPipe) id: number,
  ) {
    return this.service.detalleTienda(user, id);
  }

  @Post(':id/mensajes')
  @HttpCode(201)
  @FunctionGuard('pedidos-soporte', 'create')
  @UseInterceptors(FOTOS)
  responder(
    @GetUser() user: UsuarioPedido,
    @Param('id', ParseIntPipe) id: number,
    @Body() body: Record<string, unknown>,
    @UploadedFiles() files: Express.Multer.File[],
  ) {
    return this.service.responderTienda(user, id, body, files ?? []);
  }

  @Post(':id/items')
  @HttpCode(201)
  @FunctionGuard('pedidos-soporte', 'create')
  agregarItem(
    @GetUser() user: UsuarioPedido,
    @Param('id', ParseIntPipe) id: number,
    @Body() body: Record<string, unknown>,
  ) {
    return this.service.agregarItemTienda(user, id, body);
  }

  @Get(':id/mensajes/:messageId/fotos/:idx')
  @FunctionGuard('pedidos-soporte', 'read')
  async foto(
    @GetUser() user: UsuarioPedido,
    @Param('id', ParseIntPipe) id: number,
    @Param('messageId', ParseIntPipe) messageId: number,
    @Param('idx', ParseIntPipe) idx: number,
    @Res() res: Response,
  ) {
    enviarFoto(res, await this.service.fotoTienda(user, id, messageId, idx));
  }
}
      const mensajes = construir({
        tienda: d?.tienda ?? null,
        sucursal: d?.sucursal ?? null,
        usuario: d?.usuario ?? null,
      });

      // en orden: el (2/3) no puede llegar antes que el (1/3)
      for (const m of mensajes) {
        const r = await sendTelegramMessageDetailed(m, { botToken, chatId });
        if (r !== 'sent') {
          this.logger.warn(`pedido #${id}: aviso Telegram ${r}`);

          return;
        }
      }
      // las fotos DESPUÉS del texto, con el número del pedido en la leyenda
      if (fotos.length > 0) {
        const r = await sendTelegramFotos(fotos, {
          botToken,
          chatId,
          caption: `📎 Pedido #${id} — ${fotos.length} foto${fotos.length > 1 ? 's' : ''}`,
        });
        if (r !== 'sent') {
          this.logger.warn(`pedido #${id}: fotos a Telegram ${r}`);
        }
      }
    } catch (e) {
      this.logger.warn(
        `pedido #${id}: aviso Telegram falló — ${e instanceof Error ? e.message : String(e)}`,
      );
    }
  }

  /** WHERE del lado tienda — la tienda siempre; el cajero, además, sólo lo suyo. */
  private async alcance(user: UsuarioPedido) {
    const storeId = this.tiendaDe(user);
    const todo = await this.veTodo(user.id, storeId);

    return { storeId, todo };
  }

  async listarTienda(user: UsuarioPedido, page = 0) {
    const { storeId, todo } = await this.alcance(user);
    const filas = await this.sequelize.query(
      `SELECT r.id, r.category AS categoria, r.subject AS asunto, r.status AS estado,
              r.store_unread AS "noLeido", r.last_message_at AS "ultimoMensaje",
              r.created_at AS "createdAt",
              (SELECT count(*)::int FROM support_request_items i
                WHERE i.request_id = r.id) AS "itemsTotal",
              (SELECT count(*)::int FROM support_request_items i
                WHERE i.request_id = r.id AND i.done_at IS NOT NULL) AS "itemsHechos",
              NULLIF(TRIM(CONCAT_WS(' ', u.name, u.last_name)), '') AS autor
         FROM support_requests r
         LEFT JOIN users u ON u.id = r.user_id
        WHERE r.store_id = $1 AND ($2::boolean OR r.user_id = $3)
        ORDER BY r.last_message_at DESC
        LIMIT ${POR_PAGINA} OFFSET $4`,
      {
        bind: [storeId, todo, user.id, Math.max(0, page) * POR_PAGINA],
        type: QueryTypes.SELECT,
      },
    );

    return { items: filas, porPagina: POR_PAGINA };
  }

  private async cabeceraTienda(user: UsuarioPedido, id: number) {
    const { storeId, todo } = await this.alcance(user);
    const [r] = await this.sequelize.query<{
      id: number;
      categoria: string;
      asunto: string;
      estado: Estado;
      createdAt: string;
    }>(
      `SELECT id, category AS categoria, subject AS asunto, status AS estado,
              created_at AS "createdAt"
         FROM support_requests
        WHERE id = $1 AND store_id = $2 AND ($3::boolean OR user_id = $4)`,
      { bind: [id, storeId, todo, user.id], type: QueryTypes.SELECT },
    );
    if (!r) throw new NotFoundException('Pedido no encontrado');

    return { r, storeId };
  }

  async detalleTienda(user: UsuarioPedido, id: number) {
    const { r, storeId } = await this.cabeceraTienda(user, id);
    await this.sequelize.query(
      `UPDATE support_requests SET store_unread = FALSE WHERE id = $1 AND store_id = $2`,
      { bind: [id, storeId] },
    );

    return {
      ...r,
      items: await this.items(id, false),
      mensajes: await this.mensajes(id),
    };
  }

  /** La tienda agrega un pedido más a la nota (☑ nuevo renglón). */
  async agregarItemTienda(
    user: UsuarioPedido,
    id: number,
    body: Record<string, unknown>,
  ) {
    const { r, storeId } = await this.cabeceraTienda(user, id);
    const [texto] = leerItems([body?.texto]);
    if (!texto) throw new BadRequestException('Escribí el pedido.');

    const despues = estadoTrasMensaje(r.estado, false);
    await this.sequelize.transaction(async (t) => {
      // ★ serializa contra otro alta/tilde del mismo pedido (position es UNIQUE)
      await this.sequelize.query(
        `SELECT id FROM support_requests WHERE id = $1 AND store_id = $2 FOR UPDATE`,
        { bind: [id, storeId], transaction: t },
      );
      const [{ n }] = await this.sequelize.query<{ n: number }>(
        `SELECT count(*)::int AS n FROM support_request_items WHERE request_id = $1`,
        { bind: [id], type: QueryTypes.SELECT, transaction: t },
      );
      if (n >= MAX_ITEMS) {
        throw new BadRequestException(
          `Esta nota ya tiene ${MAX_ITEMS} pedidos — abrí otra.`,
        );
      }
      await this.sequelize.query(
        `INSERT INTO support_request_items
           (request_id, position, body, created_by_user_id, created_at)
         VALUES ($1, (SELECT COALESCE(MAX(position), 0) + 1
                        FROM support_request_items WHERE request_id = $1),
                 $2, $3, now())`,
        { bind: [id, texto, user.id], transaction: t },
      );
      await this.agregarMensaje(
        t,
        id,
        user.id,
        false,
        `➕ Nuevo pedido: «${texto}»`,
        [],
      );
      await this.sequelize.query(
        `UPDATE support_requests
            SET status = $1, platform_unread = TRUE, last_message_at = now(), updated_at = now()
          WHERE id = $2 AND store_id = $3`,
        { bind: [despues, id, storeId], transaction: t },
      );
    });
    this.avisar({ id, storeId, userId: user.id }, (d) =>
      avisoTelegramRespuesta({
        id,
        asunto: r.asunto,
        tienda: { id: storeId, nombre: d.tienda },
        desde: 'tienda',
        autor: d.usuario,
        texto: `➕ Nuevo pedido: «${texto}»`,
        fotos: 0,
        antes: r.estado,
        despues,
      }),
    );

    return this.detalleTienda(user, id);
  }

  async responderTienda(
    user: UsuarioPedido,
    id: number,
    body: Record<string, unknown>,
    files: Express.Multer.File[],
  ) {
    const { r, storeId } = await this.cabeceraTienda(user, id);
    const texto = textoLimpio(body?.texto, MAX_TEXTO);
    if (!texto) throw new BadRequestException('Escribí el mensaje.');

    const adjuntos = await this.subir(storeId, files);
    try {
      await this.sequelize.transaction(async (t) => {
        await this.agregarMensaje(t, id, user.id, false, texto, adjuntos);
        await this.sequelize.query(
          `UPDATE support_requests
              SET status = $1, platform_unread = TRUE, last_message_at = now(), updated_at = now()
            WHERE id = $2 AND store_id = $3`,
          {
            bind: [estadoTrasMensaje(r.estado, false), id, storeId],
            transaction: t,
          },
        );
      });
    } catch (e) {
      await this.borrar(adjuntos);
      throw e;
    }
    this.avisar(
      { id, storeId, userId: user.id },
      (d) =>
        avisoTelegramRespuesta({
          id,
          asunto: r.asunto,
          tienda: { id: storeId, nombre: d.tienda },
          desde: 'tienda',
          autor: d.usuario,
          texto,
          fotos: adjuntos.length,
          antes: r.estado,
          despues: estadoTrasMensaje(r.estado, false),
        }),
      fotosParaTelegram(files),
    );

    return this.detalleTienda(user, id);
  }

  async noLeidosTienda(user: UsuarioPedido) {
    const { storeId, todo } = await this.alcance(user);
    const [f] = await this.sequelize.query<{ n: number }>(
      `SELECT count(*)::int AS n FROM support_requests
        WHERE store_id = $1 AND ($2::boolean OR user_id = $3) AND store_unread`,
      { bind: [storeId, todo, user.id], type: QueryTypes.SELECT },
    );

    return { count: f?.n ?? 0 };
  }

  async fotoTienda(
    user: UsuarioPedido,
    id: number,
    messageId: number,
    idx: number,
  ) {
    await this.cabeceraTienda(user, id); // ★ primero: ¿es un pedido que este usuario puede ver?

    return this.abrirFoto(id, messageId, idx);
  }

  // ── lado plataforma (superadmin · agent) ─────────────────────────────────
  async listarPlataforma(opts: { estado?: string; q?: string; page?: number }) {
    // [2026-10-02 usuario] sin filtro = pendientes (lo resuelto se esconde de la bandeja;
    //   la tienda lo sigue viendo en su lista). 'todos' muestra todo.
    const estado = esEstado(opts.estado)
      ? opts.estado
      : opts.estado === 'todos'
        ? 'todos'
        : null;
    const q = textoLimpio(opts.q, 100);
    const filas = await this.sequelize.query(
      `SELECT r.id, r.category AS categoria, r.subject AS asunto, r.status AS estado,
              r.platform_unread AS "noLeido", r.last_message_at AS "ultimoMensaje",
              r.created_at AS "createdAt", r.store_id AS "storeId",
              (SELECT count(*)::int FROM support_request_items i
                WHERE i.request_id = r.id) AS "itemsTotal",
              (SELECT count(*)::int FROM support_request_items i
                WHERE i.request_id = r.id AND i.done_at IS NOT NULL) AS "itemsHechos",
              COALESCE(NULLIF(s.alias_name, ''), s.name) AS tienda,
              b.name AS sucursal,
              NULLIF(TRIM(CONCAT_WS(' ', u.name, u.last_name)), '') AS autor
         FROM support_requests r
         JOIN stores s ON s.id = r.store_id
         LEFT JOIN branches b ON b.id = r.branch_id
         LEFT JOIN users u ON u.id = r.user_id
        WHERE (CASE WHEN $1::text IS NULL THEN r.status <> 'resuelto'
                    WHEN $1 = 'todos' THEN TRUE
                    ELSE r.status = $1 END)
          AND ($2::text IS NULL OR r.subject ILIKE '%' || $2 || '%'
               OR s.name ILIKE '%' || $2 || '%' OR s.alias_name ILIKE '%' || $2 || '%')
        ORDER BY r.platform_unread DESC, r.last_message_at DESC
        LIMIT ${POR_PAGINA} OFFSET $3`,
      {
        bind: [estado, q, Math.max(0, Number(opts.page) || 0) * POR_PAGINA],
        type: QueryTypes.SELECT,
      },
    );

    return { items: filas, porPagina: POR_PAGINA };
  }

  private async cabeceraPlataforma(id: number) {
    const [r] = await this.sequelize.query<{
      id: number;
      categoria: string;
      asunto: string;
      estado: Estado;
      createdAt: string;
      storeId: number;
      tienda: string;
      sucursal: string | null;
      autor: string | null;
    }>(
      `SELECT r.id, r.category AS categoria, r.subject AS asunto, r.status AS estado,
              r.created_at AS "createdAt", r.store_id AS "storeId",
              COALESCE(NULLIF(s.alias_name, ''), s.name) AS tienda, b.name AS sucursal,
              NULLIF(TRIM(CONCAT_WS(' ', u.name, u.last_name)), '') AS autor
         FROM support_requests r
         JOIN stores s ON s.id = r.store_id
         LEFT JOIN branches b ON b.id = r.branch_id
         LEFT JOIN users u ON u.id = r.user_id
        WHERE r.id = $1`,
      { bind: [id], type: QueryTypes.SELECT },
    );
    if (!r) throw new NotFoundException('Pedido no encontrado');
name: tienda_admin_app
description: "Ventago - App Admin de Tienda."
# The following line prevents the package from being accidentally published to
# pub.dev using `flutter pub publish`. This is preferred for private packages.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

# The following defines the version and build number for your application.
# A version number is three numbers separated by dots, like 1.2.43
# followed by an optional build number separated by a +.
# Both the version and the builder number may be overridden in flutter
# build by specifying --build-name and --build-number, respectively.
# In Android, build-name is used as versionName while build-number used as versionCode.
# Read more about Android versioning at https://developer.android.com/studio/publish/versioning
# In iOS, build-name is used as CFBundleShortVersionString while build-number is used as CFBundleVersion.
# Read more about iOS versioning at
# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
# In Windows, build-name is used as the major, minor, and patch parts
# of the product and file versions while build-number is used as the build suffix.
version: 1.0.1+2

environment:
  sdk: ^3.11.0

# Dependencies specify other packages that your package needs in order to work.
# To automatically upgrade your package dependencies to the latest versions
# consider running `flutter pub upgrade --major-versions`. Alternatively,
# dependencies can be manually updated by changing the version numbers below to
# the latest version available on pub.dev. To see which dependencies have newer
# versions available, run `flutter pub outdated`.
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8

  # 상태관리 (사용자 선호 — Riverpod)
  flutter_riverpod: ^2.5.1
  # HTTP (async/await + 인터셉터)
  dio: ^5.4.0
  crypto: ^3.0.6
  # 토큰 보안 저장
  flutter_secure_storage: ^9.0.0
  # 숫자/날짜 포맷
  intl: ^0.19.0
  # 카드 스와이프 액션 (Clientes 왼쪽 스와이프 → 메시지)
  flutter_slidable: ^3.1.0
  # 생체(지문) 인증
  local_auth: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices. The lint set provided by the package is
  # activated in the `analysis_options.yaml` file located at the root of your
  # package. See that file for information about deactivating specific lint
  # rules and activating additional ones.
  flutter_lints: ^6.0.0
  flutter_launcher_icons: ^0.14.4

# For information on the generic Dart part of this file, see the
# following page: https://dart.dev/tools/pub/pubspec

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg

  # An image asset can refer to one or more resolution-specific "variants", see
  # https://flutter.dev/to/resolution-aware-images

  # For details regarding adding assets from package dependencies, see
  # https://flutter.dev/to/asset-from-package

  # To add custom fonts to your application, add a fonts section here,
  # in this "flutter" section. Each entry in this list should have a
  # "family" key with the font family name, and a "fonts" key with a
  # list giving the asset and other descriptors for the font. For
  # example:
  # fonts:
  #   - family: Schyler
  #     fonts:
  #       - asset: fonts/Schyler-Regular.ttf
  #       - asset: fonts/Schyler-Italic.ttf
  #         style: italic
  #   - family: Trajan Pro
  #     fonts:
  #       - asset: fonts/TrajanPro.ttf
  #       - asset: fonts/TrajanPro_Bold.ttf
  #         weight: 700
  #
  # For details regarding fonts from package dependencies,
  # see https://flutter.dev/to/font-from-package

# ── 앱 아이콘 (방패 + 앱 구분 글자) ────────────────────────────────
# 소스: assets/icon/app_icon.png (full-bleed) + app_icon_fg.png (Android adaptive 전경)
# 재생성: dart run flutter_launcher_icons
flutter_launcher_icons:
  image_path: "assets/icon/app_icon.png"
  android: true
  adaptive_icon_background: "#1a1a2e"
  adaptive_icon_foreground: "assets/icon/app_icon_fg.png"
  macos:
    generate: true
    image_path: "assets/icon/app_icon.png"
  windows:
    generate: true
    image_path: "assets/icon/app_icon.png"
    icon_size: 256
name: ventago_admin_app
description: "A new Flutter project."
# The following line prevents the package from being accidentally published to
# pub.dev using `flutter pub publish`. This is preferred for private packages.
publish_to: 'none' # Remove this line if you wish to publish to pub.dev

# The following defines the version and build number for your application.
# A version number is three numbers separated by dots, like 1.2.43
# followed by an optional build number separated by a +.
# Both the version and the builder number may be overridden in flutter
# build by specifying --build-name and --build-number, respectively.
# In Android, build-name is used as versionName while build-number used as versionCode.
# Read more about Android versioning at https://developer.android.com/studio/publish/versioning
# In iOS, build-name is used as CFBundleShortVersionString while build-number is used as CFBundleVersion.
# Read more about iOS versioning at
# https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/CoreFoundationKeys.html
# In Windows, build-name is used as the major, minor, and patch parts
# of the product and file versions while build-number is used as the build suffix.
version: 1.1.2+4

environment:
  sdk: ^3.11.0

# Dependencies specify other packages that your package needs in order to work.
# To automatically upgrade your package dependencies to the latest versions
# consider running `flutter pub upgrade --major-versions`. Alternatively,
# dependencies can be manually updated by changing the version numbers below to
# the latest version available on pub.dev. To see which dependencies have newer
# versions available, run `flutter pub outdated`.
dependencies:
  flutter:
    sdk: flutter

  # The following adds the Cupertino Icons font to your application.
  # Use with the CupertinoIcons class for iOS style icons.
  cupertino_icons: ^1.0.8

  # 상태관리 (사용자 선호 — Riverpod)
  flutter_riverpod: ^2.5.1
  # HTTP (async/await + 인터셉터)
  dio: ^5.4.0
  # 토큰 보안 저장
  flutter_secure_storage: ^9.0.0
  # 숫자/날짜 포맷
  intl: ^0.19.0
  # 카드 스와이프 액션 (Clientes 왼쪽 스와이프 → 메시지)
  flutter_slidable: ^3.1.0
  # 생체(지문) 인증
  local_auth: ^2.1.0

dev_dependencies:
  flutter_test:
    sdk: flutter

  # The "flutter_lints" package below contains a set of recommended lints to
  # encourage good coding practices. The lint set provided by the package is
  # activated in the `analysis_options.yaml` file located at the root of your
  # package. See that file for information about deactivating specific lint
  # rules and activating additional ones.
  flutter_lints: ^6.0.0
  flutter_launcher_icons: ^0.14.4

# For information on the generic Dart part of this file, see the
# following page: https://dart.dev/tools/pub/pubspec

# The following section is specific to Flutter packages.
flutter:

  # The following line ensures that the Material Icons font is
  # included with your application, so that you can use the icons in
  # the material Icons class.
  uses-material-design: true

  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg

  # An image asset can refer to one or more resolution-specific "variants", see
  # https://flutter.dev/to/resolution-aware-images

  # For details regarding adding assets from package dependencies, see
  # https://flutter.dev/to/asset-from-package

  # To add custom fonts to your application, add a fonts section here,
  # in this "flutter" section. Each entry in this list should have a
  # "family" key with the font family name, and a "fonts" key with a
  # list giving the asset and other descriptors for the font. For
  # example:
  # fonts:
  #   - family: Schyler
  #     fonts:
  #       - asset: fonts/Schyler-Regular.ttf
  #       - asset: fonts/Schyler-Italic.ttf
  #         style: italic
  #   - family: Trajan Pro
  #     fonts:
  #       - asset: fonts/TrajanPro.ttf
  #       - asset: fonts/TrajanPro_Bold.ttf
  #         weight: 700
  #
  # For details regarding fonts from package dependencies,
  # see https://flutter.dev/to/font-from-package

# ── 앱 아이콘 (방패 + 앱 구분 글자) ────────────────────────────────
# 소스: assets/icon/app_icon.png (full-bleed) + app_icon_fg.png (Android adaptive 전경)
# 재생성: dart run flutter_launcher_icons
flutter_launcher_icons:
  image_path: "assets/icon/app_icon.png"
  android: true
  adaptive_icon_background: "#1a1a2e"
  adaptive_icon_foreground: "assets/icon/app_icon_fg.png"
  macos:
    generate: true
    image_path: "assets/icon/app_icon.png"
  windows:
    generate: true
    image_path: "assets/icon/app_icon.png"
    icon_size: 256
     1	import 'package:flutter/material.dart';
     2	import 'package:flutter_riverpod/flutter_riverpod.dart';
     3	
     4	import '../../core/network/dio_client.dart';
     5	import '../../core/theme/app_theme.dart';
     6	import 'nuevo_pedido_screen.dart';
     7	import 'pedido_hilo_screen.dart';
     8	import 'pedidos_repository.dart';
     9	
    10	// [2026-10-07 pedido del usuario] «Pedidos a Ventago» desde el celular del admin de la tienda:
    11	// escribir una nota nueva, ver las propias y seguir el hilo con Ventago. Mismo endpoint que la
    12	// web (/pedidos-soporte); qué ve cada uno lo decide el servidor (admin/gerente: toda la tienda).
    13	final pedidosTiendaProvider = Provider<PedidosRepository>(
    14	  (ref) => PedidosRepository(ref.read(dioClientProvider), '/pedidos-soporte'),
    15	);
    16	
    17	/// Cuántos pedidos tienen respuesta de Ventago sin leer (el globito del ícono).
    18	final pedidosNoLeidosProvider = FutureProvider.autoDispose<int>(
    19	  (ref) => ref.read(pedidosTiendaProvider).noLeidos(),
    20	);
    21	
    22	class PedidosScreen extends ConsumerStatefulWidget {
    23	  const PedidosScreen({super.key});
    24	
    25	  @override
    26	  ConsumerState<PedidosScreen> createState() => _PedidosScreenState();
    27	}
    28	
    29	class _PedidosScreenState extends ConsumerState<PedidosScreen> {
    30	  List<PedidoResumen>? _lista;
    31	  String? _error;
    32	  bool _cargando = false;
    33	
    34	  @override
    35	  void initState() {
    36	    super.initState();
    37	    _cargar();
    38	  }
    39	
    40	  Future<void> _cargar() async {
    41	    setState(() => _cargando = true);
    42	    try {
    43	      final l = await ref.read(pedidosTiendaProvider).listar();
    44	      if (mounted) {
    45	        setState(() {
    46	          _lista = l;
    47	          _error = null;
    48	        });
    49	      }
    50	    } catch (e) {
    51	      if (mounted) setState(() => _error = mensajeDeError(e));
    52	    } finally {
    53	      if (mounted) setState(() => _cargando = false);
    54	    }
    55	    ref.invalidate(pedidosNoLeidosProvider);
    56	  }
    57	
    58	  Future<void> _abrir(int id) async {
    59	    await Navigator.of(context).push<bool>(
    60	      MaterialPageRoute(builder: (_) => PedidoHiloScreen(repo: ref.read(pedidosTiendaProvider), id: id)),
    61	    );
    62	    _cargar();
    63	  }
    64	
    65	  Future<void> _nuevo() async {
    66	    final id = await Navigator.of(context).push<int>(
    67	      MaterialPageRoute(builder: (_) => const NuevoPedidoScreen()),
    68	    );
    69	    if (id == null || !mounted) return;
    70	    await _cargar();
    71	    if (mounted) _abrir(id);
    72	  }
    73	
    74	  @override
    75	  Widget build(BuildContext context) {
    76	    final lista = _lista;
    77	
    78	    return Scaffold(
    79	      appBar: AppBar(backgroundColor: AppColors.navy2, title: const Text('Pedidos a Ventago')),
    80	      floatingActionButton: FloatingActionButton.extended(
    81	        backgroundColor: AppColors.gold,
    82	        foregroundColor: Colors.black,
    83	        icon: const Icon(Icons.edit_note),
    84	        label: const Text('Nuevo pedido'),
    85	        onPressed: _nuevo,
    86	      ),
    87	      body: Column(
    88	        children: [
    89	          if (_cargando) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
    90	          Expanded(
    91	            child: RefreshIndicator(
    92	              onRefresh: _cargar,
    93	              child: _error != null && lista == null
    94	                  ? ListView(children: [
    95	                      Padding(
    96	                        padding: const EdgeInsets.all(24),
    97	                        child: Text(_error!, style: const TextStyle(color: AppColors.red)),
    98	                      ),
    99	                    ])
   100	                  : lista == null
   101	                      ? const SizedBox.shrink()
   102	                      : lista.isEmpty
   103	                          ? ListView(children: const [
   104	                              Padding(
   105	                                padding: EdgeInsets.all(24),
   106	                                child: Text(
   107	                                  'Todavía no hay pedidos.\nTocá «Nuevo pedido» para pedir una mejora, '
   108	                                  'una reparación o que corrijamos un error.',
   109	                                  style: TextStyle(color: AppColors.dim),
   110	                                ),
   111	                              ),
   112	                            ])
   113	                          : ListView.separated(
   114	                              padding: const EdgeInsets.only(bottom: 88),
   115	                              itemCount: lista.length,
   116	                              separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.line),
   117	                              itemBuilder: (_, i) => _fila(lista[i]),
   118	                            ),
   119	            ),
   120	          ),
   121	        ],
   122	      ),
   123	    );
   124	  }
   125	
   126	  Widget _fila(PedidoResumen p) {
   127	    return ListTile(
   128	      onTap: () => _abrir(p.id),
   129	      leading: Icon(
   130	        p.noLeido ? Icons.mark_email_unread : Icons.mail_outline,
   131	        color: p.noLeido ? AppColors.gold : AppColors.dim,
   132	      ),
   133	      title: Text(
   134	        p.asunto,
   135	        maxLines: 2,
   136	        overflow: TextOverflow.ellipsis,
   137	        style: TextStyle(fontWeight: p.noLeido ? FontWeight.w800 : FontWeight.w500),
   138	      ),
   139	      subtitle: Text(
   140	        [
   141	          etiquetaCategoria(p.categoria),
   142	          if (p.autor != null) p.autor!,
   143	          if (p.itemsTotal > 0) '${p.itemsHechos}/${p.itemsTotal}',
   144	        ].join(' · '),
   145	        style: const TextStyle(color: AppColors.dim, fontSize: 12),
   146	      ),
   147	      trailing: Column(
   148	        mainAxisAlignment: MainAxisAlignment.center,
   149	        crossAxisAlignment: CrossAxisAlignment.end,
   150	        children: [
   151	          EstadoChip(p.estado),
   152	          const SizedBox(height: 4),
   153	          Text(fechaCorta(p.ultimoMensaje), style: const TextStyle(color: AppColors.dim, fontSize: 11)),
   154	        ],
   155	      ),
   156	    );
   157	  }
   158	}
     1	import 'dart:async';
     2	
     3	import 'package:flutter/material.dart';
     4	import 'package:flutter_riverpod/flutter_riverpod.dart';
     5	
     6	import '../../core/network/dio_client.dart';
     7	import '../../core/theme/app_theme.dart';
     8	import 'pedido_hilo_screen.dart';
     9	import 'pedidos_repository.dart';
    10	
    11	// [2026-10-07 pedido del usuario] Bandeja de «Pedidos a Ventago» de todas las tiendas —
    12	// lo mismo que /admin/pedidos en la web: ver, responder, cambiar estado y tildar renglones.
    13	final pedidosPlataformaProvider = Provider<PedidosRepository>(
    14	  (ref) => PedidosRepository(ref.read(dioClientProvider), '/pedidos-soporte/plataforma'),
    15	);
    16	
    17	class PedidosScreen extends ConsumerStatefulWidget {
    18	  const PedidosScreen({super.key});
    19	
    20	  @override
    21	  ConsumerState<PedidosScreen> createState() => _PedidosScreenState();
    22	}
    23	
    24	class _PedidosScreenState extends ConsumerState<PedidosScreen> {
    25	  // null = pendientes (abierto + en curso), igual que la bandeja web
    26	  String? _estado;
    27	  String _q = '';
    28	  Timer? _debounce;
    29	  List<PedidoResumen>? _lista;
    30	  String? _error;
    31	  bool _cargando = false;
    32	
    33	  static const _filtros = [
    34	    (null, 'Pendientes'),
    35	    ('abierto', 'Abiertos'),
    36	    ('en_curso', 'En curso'),
    37	    ('resuelto', 'Resueltos'),
    38	    ('todos', 'Todos'),
    39	  ];
    40	
    41	  @override
    42	  void initState() {
    43	    super.initState();
    44	    _cargar();
    45	  }
    46	
    47	  @override
    48	  void dispose() {
    49	    _debounce?.cancel();
    50	    super.dispose();
    51	  }
    52	
    53	  Future<void> _cargar() async {
    54	    setState(() => _cargando = true);
    55	    try {
    56	      final l = await ref.read(pedidosPlataformaProvider).listar(estado: _estado, q: _q);
    57	      if (mounted) {
    58	        setState(() {
    59	          _lista = l;
    60	          _error = null;
    61	        });
    62	      }
    63	    } catch (e) {
    64	      if (mounted) setState(() => _error = mensajeDeError(e));
    65	    } finally {
    66	      if (mounted) setState(() => _cargando = false);
    67	    }
    68	  }
    69	
    70	  Future<void> _abrir(PedidoResumen p) async {
    71	    await Navigator.of(context).push<bool>(
    72	      MaterialPageRoute(builder: (_) => PedidoHiloScreen(repo: ref.read(pedidosPlataformaProvider), id: p.id)),
    73	    );
    74	    // al abrirlo deja de estar «sin leer» aunque no haya cambiado nada → siempre recargar
    75	    _cargar();
    76	  }
    77	
    78	  @override
    79	  Widget build(BuildContext context) {
    80	    final lista = _lista;
    81	
    82	    return Column(
    83	      children: [
    84	        Padding(
    85	          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    86	          child: TextField(
    87	            decoration: const InputDecoration(
    88	              prefixIcon: Icon(Icons.search),
    89	              hintText: 'Buscar por asunto o tienda',
    90	              isDense: true,
    91	            ),
    92	            onChanged: (v) {
    93	              _debounce?.cancel();
    94	              _debounce = Timer(const Duration(milliseconds: 400), () {
    95	                _q = v;
    96	                _cargar();
    97	              });
    98	            },
    99	          ),
   100	        ),
   101	        SizedBox(
   102	          height: 44,
   103	          child: ListView(
   104	            scrollDirection: Axis.horizontal,
   105	            padding: const EdgeInsets.symmetric(horizontal: 12),
   106	            children: _filtros
   107	                .map((f) => Padding(
   108	                      padding: const EdgeInsets.symmetric(horizontal: 4),
   109	                      child: ChoiceChip(
   110	                        label: Text(f.$2),
   111	                        selected: _estado == f.$1,
   112	                        onSelected: (_) {
   113	                          setState(() => _estado = f.$1);
   114	                          _cargar();
   115	                        },
   116	                      ),
   117	                    ))
   118	                .toList(),
   119	          ),
   120	        ),
   121	        if (_cargando) const LinearProgressIndicator(minHeight: 2) else const SizedBox(height: 2),
   122	        Expanded(
   123	          child: RefreshIndicator(
   124	            onRefresh: _cargar,
   125	            child: _error != null && lista == null
   126	                ? ListView(children: [
   127	                    Padding(
   128	                      padding: const EdgeInsets.all(24),
   129	                      child: Text(_error!, style: const TextStyle(color: AppColors.red)),
   130	                    ),
   131	                  ])
   132	                : lista == null
   133	                    ? const SizedBox.shrink()
   134	                    : lista.isEmpty
   135	                        ? ListView(children: const [
   136	                            Padding(
   137	                              padding: EdgeInsets.all(24),
   138	                              child: Text('No hay pedidos.', style: TextStyle(color: AppColors.dim)),
   139	                            ),
   140	                          ])
   141	                        : ListView.separated(
   142	                            itemCount: lista.length,
   143	                            separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.line),
   144	                            itemBuilder: (_, i) => _fila(lista[i]),
   145	                          ),
   146	          ),
   147	        ),
   148	      ],
   149	    );
   150	  }
   151	
   152	  Widget _fila(PedidoResumen p) {
   153	    return ListTile(
   154	      onTap: () => _abrir(p),
   155	      leading: Icon(
   156	        p.noLeido ? Icons.mark_email_unread : Icons.mail_outline,
   157	        color: p.noLeido ? AppColors.gold : AppColors.dim,
   158	      ),
   159	      title: Text(
   160	        p.asunto,
   161	        maxLines: 2,
   162	        overflow: TextOverflow.ellipsis,
   163	        style: TextStyle(fontWeight: p.noLeido ? FontWeight.w800 : FontWeight.w500),
   164	      ),
   165	      subtitle: Text(
   166	        [
   167	          p.tienda ?? '',
   168	          if (p.sucursal != null) p.sucursal!,
   169	          etiquetaCategoria(p.categoria),
   170	          if (p.itemsTotal > 0) '${p.itemsHechos}/${p.itemsTotal}',
   171	        ].where((s) => s.isNotEmpty).join(' · '),
   172	        style: const TextStyle(color: AppColors.dim, fontSize: 12),
   173	      ),
   174	      trailing: Column(
   175	        mainAxisAlignment: MainAxisAlignment.center,
   176	        crossAxisAlignment: CrossAxisAlignment.end,
   177	        children: [
   178	          EstadoChip(p.estado),
   179	          const SizedBox(height: 4),
   180	          Text(fechaCorta(p.ultimoMensaje), style: const TextStyle(color: AppColors.dim, fontSize: 11)),
   181	        ],
   182	      ),
   183	    );
   184	  }
   185	}
    75	  @override
    76	  void dispose() {
    77	    _respuesta.dispose();
    78	    super.dispose();
    79	  }
    80	
    81	  Future<void> _cargar() async {
    82	    try {
    83	      final p = await widget.repo.detalle(widget.id);
    84	      if (mounted) {
    85	        setState(() {
    86	          _p = p;
    87	          _error = null;
    88	        });
    89	      }
    90	    } catch (e) {
    91	      if (mounted) setState(() => _error = mensajeDeError(e));
    92	    }
    93	  }
    94	
    95	  void _aviso(String msg, {bool error = false}) {
    96	    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    97	      content: Text(msg),
    98	      backgroundColor: error ? AppColors.red : null,
    99	      behavior: SnackBarBehavior.floating,
   100	    ));
   101	  }
   102	
   103	  // ★ cada acción va al servidor y después se recarga el hilo: el estado que se ve es
   104	  //   siempre el que quedó guardado (el servidor puede cambiarlo, p.ej. al responder).
   105	  Future<void> _hacer(Future<void> Function() accion, {String? ok}) async {
   106	    if (_enviando) return;
   107	    setState(() => _enviando = true);
   108	    try {
   109	      await accion();
   110	      _cambio = true;
   111	      if (ok != null && mounted) _aviso(ok);
   112	      await _cargar();
   113	    } catch (e) {
   114	      if (mounted) _aviso(mensajeDeError(e), error: true);
   115	    } finally {
   116	      if (mounted) setState(() => _enviando = false);
   117	    }
   118	  }
   119	
   120	  Future<void> _responder() async {
   121	    final texto = _respuesta.text.trim();
   122	    if (texto.isEmpty) return;
   123	    await _hacer(() async {
   124	      await widget.repo.responder(widget.id, texto);
   125	      _respuesta.clear();
   126	    });
   127	  }
   128	
   129	  @override
   130	  Widget build(BuildContext context) {
   131	    final p = _p;
   132	
   133	    return PopScope(
   134	      canPop: false,
   135	      onPopInvokedWithResult: (didPop, _) {
   136	        if (!didPop) Navigator.of(context).pop(_cambio);
   137	      },
   138	      child: Scaffold(
   139	        appBar: AppBar(
   140	          backgroundColor: AppColors.navy2,
   141	          title: Text('Pedido #${widget.id}'),
   142	          actions: [IconButton(icon: const Icon(Icons.refresh), tooltip: 'Actualizar', onPressed: _cargar)],
   143	        ),
   144	        body: _error != null && p == null
   145	            ? Center(
   146	                child: Padding(
   147	                  padding: const EdgeInsets.all(24),
   148	                  child: Text(_error!, style: const TextStyle(color: AppColors.red)),
   149	                ),
   150	              )
   151	            : p == null
   152	                ? const Center(child: CircularProgressIndicator())
   153	                : Column(
   154	                    children: [
   155	                      if (_enviando) const LinearProgressIndicator(minHeight: 2),
   156	                      Expanded(
   157	                        child: RefreshIndicator(
   158	                          onRefresh: _cargar,
   159	                          child: ListView(
   160	                            padding: const EdgeInsets.all(16),
   161	                            children: [
   162	                              _cabecera(p),
   163	                              if (p.items.isNotEmpty) ...[const SizedBox(height: 12), _items(p)],
   164	                              const SizedBox(height: 16),
   165	                              ...p.mensajes.map(_mensaje),
   166	                            ],
   167	                          ),
   168	                        ),
   169	                      ),
   170	                      _caja(),
   171	                    ],
   172	                  ),
   173	      ),
   174	    );
   175	  }
   176	
   177	  Widget _cabecera(PedidoDetalle p) {
   178	    return Column(
   179	      crossAxisAlignment: CrossAxisAlignment.start,
   180	      children: [
    20	  final _asunto = TextEditingController();
    21	  final _texto = TextEditingController();
    22	  bool _enviando = false;
    23	  String? _error;
    24	
    25	  @override
    26	  void dispose() {
    27	    _asunto.dispose();
    28	    _texto.dispose();
    29	    super.dispose();
    30	  }
    31	
    32	  bool get _listo => _categoria != null && _asunto.text.trim().isNotEmpty && _texto.text.trim().isNotEmpty;
    33	
    34	  Future<void> _enviar() async {
    35	    if (!_listo || _enviando) return;
    36	    setState(() {
    37	      _enviando = true;
    38	      _error = null;
    39	    });
    40	    try {
    41	      final id = await ref.read(pedidosTiendaProvider).crear(
    42	            categoria: _categoria!,
    43	            asunto: _asunto.text.trim(),
    44	            texto: _texto.text.trim(),
    45	          );
    46	      if (!mounted) return;
    47	      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    48	        content: Text('Pedido enviado a Ventago.'),
    49	        behavior: SnackBarBehavior.floating,
    50	      ));
    51	      Navigator.of(context).pop(id);
    52	    } catch (e) {
    53	      // ★ si falla no se pierde lo escrito: queda en el formulario para reintentar
    54	      if (mounted) setState(() => _error = mensajeDeError(e));
    55	    } finally {
    56	      if (mounted) setState(() => _enviando = false);
    57	    }
    58	  }
    59	
    60	  @override
    61	  Widget build(BuildContext context) {
    62	    return PopScope(
    63	      canPop: !_enviando,
    64	      child: Scaffold(
    65	        appBar: AppBar(backgroundColor: AppColors.navy2, title: const Text('Nuevo pedido')),
    66	        body: ListView(
    67	          padding: const EdgeInsets.all(16),
    68	          children: [
    69	            const Text('¿Qué necesitás?', style: TextStyle(fontWeight: FontWeight.w700)),
    70	            const SizedBox(height: 8),
    71	            ...categorias.map((c) => Card(
    72	                  color: _categoria == c.$1 ? AppColors.gold.withValues(alpha: 0.14) : AppColors.panel,
    73	                  shape: RoundedRectangleBorder(
    74	                    borderRadius: BorderRadius.circular(10),
    75	                    side: BorderSide(color: _categoria == c.$1 ? AppColors.gold : AppColors.line),
    76	                  ),
    77	                  child: ListTile(
    78	                    onTap: _enviando ? null : () => setState(() => _categoria = c.$1),
    79	                    leading: Icon(
    80	                      _categoria == c.$1 ? Icons.radio_button_checked : Icons.radio_button_unchecked,
    81	                      color: _categoria == c.$1 ? AppColors.gold : AppColors.dim,
    82	                    ),
    83	                    title: Text(c.$2, style: const TextStyle(fontWeight: FontWeight.w600)),
    84	                    subtitle: Text(c.$3, style: const TextStyle(color: AppColors.dim, fontSize: 12)),
    85	                  ),
    86	                )),
    87	            const SizedBox(height: 16),
    88	            TextField(
    89	              controller: _asunto,
    90	              enabled: !_enviando,
    91	              maxLength: 150,
    92	              textCapitalization: TextCapitalization.sentences,
    93	              decoration: const InputDecoration(labelText: 'Asunto'),
    94	              onChanged: (_) => setState(() {}),
    95	            ),
    55	            ),
    56	          ],
    57	        ),
    58	        actions: [
    59	          // Relojes vinculados — admin 만. 서버도 403 으로 재판정하므로
    60	          // 이 플래그는 UX 전용(T-98-30, memo frontend-flag-is-not-a-security-boundary).
    61	          if (user?.roles.contains('admin') == true)
    62	            IconButton(
    63	              icon: const Icon(Icons.watch_outlined),
    64	              tooltip: 'Relojes',
    65	              onPressed: () => Navigator.of(context).push(
    66	                MaterialPageRoute(builder: (_) => const RelojesScreen()),
    67	              ),
    68	            ),
    69	          // [2026-10-07] Pedidos a Ventago — los endpoints son de la tienda: sin storeId
    70	          // (superadmin) el servidor los rechaza, así que no se muestra.
    71	          if (user?.storeId != null)
    72	            IconButton(
    73	              icon: Badge(
    74	                isLabelVisible: (ref.watch(pedidosNoLeidosProvider).valueOrNull ?? 0) > 0,
    75	                label: Text('${ref.watch(pedidosNoLeidosProvider).valueOrNull ?? 0}'),
    76	                child: const Icon(Icons.support_agent),
    77	              ),
    78	              tooltip: 'Pedidos a Ventago',
    79	              onPressed: () => Navigator.of(context).push(
    80	                MaterialPageRoute(builder: (_) => const PedidosScreen()),
    81	              ),
    82	            ),
    83	          IconButton(
    84	            icon: const Icon(Icons.logout),
    85	            tooltip: 'Salir',
    86	            onPressed: () =>
    87	                ref.read(authControllerProvider.notifier).logout(),
    88	          ),
    89	          const SizedBox(width: 4),
    90	        ],

hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
hook: PreToolUse Failed
hook: PreToolUse Completed
hook: PreToolUse Completed
hook: PostToolUse
hook: PostToolUse
hook: PostToolUse
hook: PostToolUse
hook: PostToolUse Failed
hook: PostToolUse Failed
hook: PostToolUse Completed
hook: PostToolUse Completed
codex
[HIGH] tienda-admin-app/lib/features/pedidos/nuevo_pedido_screen.dart:46-56 — 생성 성공 후 화면이 닫히지 않아 동일 pedido를 다시 전송할 수 있음

  문제: 요청 성공 시에도 `_enviando`가 아직 `true`이므로 `PopScope(canPop: !_enviando)`가 `Navigator.pop(id)`를 차단한다. 사용자는 성공 메시지만 보고 폼에 그대로 남으며, `finally` 이후 버튼이 다시 활성화되어 같은 pedido를 중복 생성할 수 있다.

  근거:

  ```dart
  if (!mounted) return;
  ...
  Navigator.of(context).pop(id);
  ...
  finally {
    if (mounted) setState(() => _enviando = false);
  }
  ```

  동시에:

  ```dart
  PopScope(
    canPop: !_enviando,
  ```

  수정: 성공 경로에서 먼저 `_enviando = false`로 바꾼 뒤 pop하거나, 성공 완료 플래그를 두어 프로그램 방식의 pop은 허용해야 한다. 서버 측에는 생성 요청 idempotency key도 권장한다.

[HIGH] ventago-admin-app/lib/features/pedidos/pedido_hilo_screen.dart:120-126 — 전송 중 화면을 닫으면 dispose된 TextEditingController를 사용함

  문제: hilo 화면은 `_enviando` 중에도 닫을 수 있다. 응답을 기다리는 동안 화면이 dispose된 뒤 서버 응답이 성공하면 `_respuesta.clear()`가 이미 dispose된 controller에 실행된다. 동일 파일을 쓰는 두 앱 모두 영향받는다.

  근거:

  ```dart
  await widget.repo.responder(widget.id, texto);
  _respuesta.clear();
  ```

  `clear()` 앞에는 `mounted` 검사가 없고, `dispose()`에서 controller를 폐기한다.

  수정: 성공 후 `if (!mounted) return;`을 확인한 다음 clear하거나, 전송 중 pop을 차단한다. 전자를 적용해도 서버 요청 자체는 정상 완료되므로 목록 갱신 전략이 필요하다.

[HIGH] ventago-admin-app/lib/features/pedidos/pedido_hilo_screen.dart:133-137 — PopScope가 pop을 영구 차단하며 재귀적인 pop 시도를 만들 수 있음

  문제: `canPop: false` 상태에서 pop이 거절되면 callback이 다시 `Navigator.pop()`을 호출한다. 그러나 `canPop`은 여전히 false이므로 두 번째 pop도 거절된다. Flutter 버전에 따라 callback 반복 또는 화면을 나갈 수 없는 동작이 발생한다. 동일 파일을 쓰는 두 앱 모두 영향받는다.

  근거:

  ```dart
  PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.of(context).pop(_cambio);
    },
  ```

  수정: pop 허용 플래그를 state로 관리하고 callback에서 플래그를 true로 바꾼 뒤 pop하거나, 이 화면에서 별도 결과가 꼭 필요하지 않다면 `canPop: true`로 두고 호출 측에서 항상 목록을 갱신한다.

[MEDIUM] tienda-admin-app/lib/features/pedidos/pedidos_screen.dart:29-43 — dispose 이후 Riverpod ref를 사용함

  문제: 목록 요청 중 화면이 닫히면 `mounted` 조건으로 `setState`는 피하지만, 함수 마지막의 `ref.invalidate()`는 무조건 실행된다. dispose된 `ConsumerState`의 ref 사용은 Riverpod assertion/예외를 발생시킬 수 있다.

  근거:

  ```dart
  } finally {
    if (mounted) setState(() => _cargando = false);
  }
  ref.invalidate(pedidosNoLeidosProvider);
  ```

  수정:

  ```dart
  if (mounted) {
    ref.invalidate(pedidosNoLeidosProvider);
  }
  ```

[MEDIUM] ventago-admin-app/lib/features/pedidos/pedidos_screen.dart:70-75 및 tienda-admin-app/lib/features/pedidos/pedidos_screen.dart:45-51 — Navigator await 이후 mounted 확인 없이 setState/ref 사용 경로 실행

  문제: hilo가 열린 동안 부모 화면 또는 AppShell이 제거될 수 있다. 돌아온 뒤 `_cargar()`가 즉시 `setState`하고 `ref.read`를 실행하므로 dispose된 State에서 예외가 난다.

  근거:

  ```dart
  await Navigator.of(context).push<bool>(...);
  _cargar();
  ```

  수정:

  ```dart
  await Navigator.of(context).push<bool>(...);
  if (!mounted) return;
  await _cargar();
  ```

[MEDIUM] ventago-admin-app/lib/features/pedidos/pedidos_screen.dart:53-67 — 검색·필터 요청 응답 순서가 뒤집히면 오래된 목록이 최신 결과를 덮어씀

  문제: debounce는 아직 시작하지 않은 검색만 취소한다. 이미 실행된 요청 A가 있는 상태에서 필터나 검색 요청 B를 시작하면 두 요청이 병렬 실행된다. B가 먼저 끝나도 A가 나중에 `_lista`를 덮어써 현재 필터와 다른 결과가 표시된다. 먼저 끝난 요청이 `_cargando = false`로 바꾸는 문제도 있다.

  근거:

  ```dart
  final l = await ...listar(estado: _estado, q: _q);
  ...
  _lista = l;
  ...
  _cargando = false;
  ```

  수정: 요청 세대 번호를 두고 최신 요청만 state에 반영하거나 Dio `CancelToken`으로 이전 요청을 취소한다.

[MEDIUM] 두 앱의 pedido_hilo_screen.dart:123-125 및 nuevo_pedido_screen.dart:41-45 — 네트워크 결과가 불명확할 때 재시도로 중복 메시지·pedido가 생성될 수 있음

  문제: 서버가 INSERT를 완료한 뒤 응답만 timeout/연결 단절되면 앱은 실패로 표시한다. hilo에서는 텍스트가 남고, 신규 pedido 화면에서도 전체 폼이 남으므로 사용자의 재시도가 중복 POST를 만든다. `_enviando`는 동시 탭은 막지만 이 경우는 막지 못한다.

  수정: 클라이언트 생성 UUID를 idempotency key로 보내고 API가 중복 key를 동일 결과로 처리하도록 하는 것이 확실하다. 최소한 timeout은 “전송 여부 확인 필요”로 표시하고 자동 재시도를 피해야 한다.

그 외 확인 결과:

- `/pedidos-soporte`, `/plataforma`, `/no-leidos`, 상태·item PATCH, 메시지 및 사진 경로는 NestJS 컨트롤러와 일치한다.
- 현재 API 응답 기준으로 JSON 필드와 parser 매핑은 일치한다.
- `_enviando`를 함수 시작에서 즉시 설정하므로 정상적인 빠른 이중 탭은 차단된다.
- `Badge`에서 `valueOrNull`을 두 번 watch하는 것은 불필요한 반복이지만 기능 오류는 아니다.
- Flutter analyzer는 SDK cache가 작업공간 밖이라 sandbox 쓰기 제한에 걸려 실행하지 못했다.
hook: Stop
hook: Stop
hook: Stop Failed
hook: Stop Completed
tokens used
56,489
[HIGH] tienda-admin-app/lib/features/pedidos/nuevo_pedido_screen.dart:46-56 — 생성 성공 후 화면이 닫히지 않아 동일 pedido를 다시 전송할 수 있음

  문제: 요청 성공 시에도 `_enviando`가 아직 `true`이므로 `PopScope(canPop: !_enviando)`가 `Navigator.pop(id)`를 차단한다. 사용자는 성공 메시지만 보고 폼에 그대로 남으며, `finally` 이후 버튼이 다시 활성화되어 같은 pedido를 중복 생성할 수 있다.

  근거:

  ```dart
  if (!mounted) return;
  ...
  Navigator.of(context).pop(id);
  ...
  finally {
    if (mounted) setState(() => _enviando = false);
  }
  ```

  동시에:

  ```dart
  PopScope(
    canPop: !_enviando,
  ```

  수정: 성공 경로에서 먼저 `_enviando = false`로 바꾼 뒤 pop하거나, 성공 완료 플래그를 두어 프로그램 방식의 pop은 허용해야 한다. 서버 측에는 생성 요청 idempotency key도 권장한다.

[HIGH] ventago-admin-app/lib/features/pedidos/pedido_hilo_screen.dart:120-126 — 전송 중 화면을 닫으면 dispose된 TextEditingController를 사용함

  문제: hilo 화면은 `_enviando` 중에도 닫을 수 있다. 응답을 기다리는 동안 화면이 dispose된 뒤 서버 응답이 성공하면 `_respuesta.clear()`가 이미 dispose된 controller에 실행된다. 동일 파일을 쓰는 두 앱 모두 영향받는다.

  근거:

  ```dart
  await widget.repo.responder(widget.id, texto);
  _respuesta.clear();
  ```

  `clear()` 앞에는 `mounted` 검사가 없고, `dispose()`에서 controller를 폐기한다.

  수정: 성공 후 `if (!mounted) return;`을 확인한 다음 clear하거나, 전송 중 pop을 차단한다. 전자를 적용해도 서버 요청 자체는 정상 완료되므로 목록 갱신 전략이 필요하다.

[HIGH] ventago-admin-app/lib/features/pedidos/pedido_hilo_screen.dart:133-137 — PopScope가 pop을 영구 차단하며 재귀적인 pop 시도를 만들 수 있음

  문제: `canPop: false` 상태에서 pop이 거절되면 callback이 다시 `Navigator.pop()`을 호출한다. 그러나 `canPop`은 여전히 false이므로 두 번째 pop도 거절된다. Flutter 버전에 따라 callback 반복 또는 화면을 나갈 수 없는 동작이 발생한다. 동일 파일을 쓰는 두 앱 모두 영향받는다.

  근거:

  ```dart
  PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) Navigator.of(context).pop(_cambio);
    },
  ```

  수정: pop 허용 플래그를 state로 관리하고 callback에서 플래그를 true로 바꾼 뒤 pop하거나, 이 화면에서 별도 결과가 꼭 필요하지 않다면 `canPop: true`로 두고 호출 측에서 항상 목록을 갱신한다.

[MEDIUM] tienda-admin-app/lib/features/pedidos/pedidos_screen.dart:29-43 — dispose 이후 Riverpod ref를 사용함

  문제: 목록 요청 중 화면이 닫히면 `mounted` 조건으로 `setState`는 피하지만, 함수 마지막의 `ref.invalidate()`는 무조건 실행된다. dispose된 `ConsumerState`의 ref 사용은 Riverpod assertion/예외를 발생시킬 수 있다.

  근거:

  ```dart
  } finally {
    if (mounted) setState(() => _cargando = false);
  }
  ref.invalidate(pedidosNoLeidosProvider);
  ```

  수정:

  ```dart
  if (mounted) {
    ref.invalidate(pedidosNoLeidosProvider);
  }
  ```

[MEDIUM] ventago-admin-app/lib/features/pedidos/pedidos_screen.dart:70-75 및 tienda-admin-app/lib/features/pedidos/pedidos_screen.dart:45-51 — Navigator await 이후 mounted 확인 없이 setState/ref 사용 경로 실행

  문제: hilo가 열린 동안 부모 화면 또는 AppShell이 제거될 수 있다. 돌아온 뒤 `_cargar()`가 즉시 `setState`하고 `ref.read`를 실행하므로 dispose된 State에서 예외가 난다.

  근거:

  ```dart
  await Navigator.of(context).push<bool>(...);
  _cargar();
  ```

  수정:

  ```dart
  await Navigator.of(context).push<bool>(...);
  if (!mounted) return;
  await _cargar();
  ```

[MEDIUM] ventago-admin-app/lib/features/pedidos/pedidos_screen.dart:53-67 — 검색·필터 요청 응답 순서가 뒤집히면 오래된 목록이 최신 결과를 덮어씀

  문제: debounce는 아직 시작하지 않은 검색만 취소한다. 이미 실행된 요청 A가 있는 상태에서 필터나 검색 요청 B를 시작하면 두 요청이 병렬 실행된다. B가 먼저 끝나도 A가 나중에 `_lista`를 덮어써 현재 필터와 다른 결과가 표시된다. 먼저 끝난 요청이 `_cargando = false`로 바꾸는 문제도 있다.

  근거:

  ```dart
  final l = await ...listar(estado: _estado, q: _q);
  ...
  _lista = l;
  ...
  _cargando = false;
  ```

  수정: 요청 세대 번호를 두고 최신 요청만 state에 반영하거나 Dio `CancelToken`으로 이전 요청을 취소한다.

[MEDIUM] 두 앱의 pedido_hilo_screen.dart:123-125 및 nuevo_pedido_screen.dart:41-45 — 네트워크 결과가 불명확할 때 재시도로 중복 메시지·pedido가 생성될 수 있음

  문제: 서버가 INSERT를 완료한 뒤 응답만 timeout/연결 단절되면 앱은 실패로 표시한다. hilo에서는 텍스트가 남고, 신규 pedido 화면에서도 전체 폼이 남으므로 사용자의 재시도가 중복 POST를 만든다. `_enviando`는 동시 탭은 막지만 이 경우는 막지 못한다.

  수정: 클라이언트 생성 UUID를 idempotency key로 보내고 API가 중복 key를 동일 결과로 처리하도록 하는 것이 확실하다. 최소한 timeout은 “전송 여부 확인 필요”로 표시하고 자동 재시도를 피해야 한다.

그 외 확인 결과:

- `/pedidos-soporte`, `/plataforma`, `/no-leidos`, 상태·item PATCH, 메시지 및 사진 경로는 NestJS 컨트롤러와 일치한다.
- 현재 API 응답 기준으로 JSON 필드와 parser 매핑은 일치한다.
- `_enviando`를 함수 시작에서 즉시 설정하므로 정상적인 빠른 이중 탭은 차단된다.
- `Badge`에서 `valueOrNull`을 두 번 watch하는 것은 불필요한 반복이지만 기능 오류는 아니다.
- Flutter analyzer는 SDK cache가 작업공간 밖이라 sandbox 쓰기 제한에 걸려 실행하지 못했다.

## 처리
- [HIGH] 신규 pedido 성공 후 PopScope 가 pop 을 막는다 → **기각.** `PopScope.canPop` 은 뒤로가기·`maybePop` 만 막고 `Navigator.pop()` 직접 호출은 막지 않는다. 성공 시 화면은 닫힌다.
- [HIGH] hilo 의 PopScope 재귀 → **기각(동작 근거)**, 하지만 결과값을 아무도 안 쓰므로 PopScope·`_cambio` 를 통째로 제거해 단순화.
- [HIGH] 닫힌 뒤 `_respuesta.clear()` → **수용.** `if (mounted)` 뒤로.
- [MEDIUM] dispose 후 `ref.invalidate` → **수용.** mounted 확인.
- [MEDIUM] Navigator await 후 `_cargar` → **수용.** `_cargar` 첫 줄 mounted 확인 + 호출부도 확인.
- [MEDIUM] 필터·검색 응답 역전 → **수용.** 세대 번호 `_gen`: 마지막 요청만 화면에 쓴다.
- [MEDIUM] 응답 유실 시 재전송 중복 → **부분 수용.** API 에 idempotency key 가 없어 앱만으로는 못 막는다. receiveTimeout 이면 「보냈을 수 있으니 확인 후 재전송」으로 안내. API 키 도입은 보류(사용자 보고).
