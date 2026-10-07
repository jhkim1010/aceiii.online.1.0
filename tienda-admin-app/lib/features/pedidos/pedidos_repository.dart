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
    // [codex 043] el servidor pudo haberlo guardado: no invitar a reenviar a ciegas
    if (e.type == DioExceptionType.receiveTimeout) {
      return 'El servidor no respondió a tiempo. Puede que se haya enviado: revisá antes de reenviar.';
    }
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
