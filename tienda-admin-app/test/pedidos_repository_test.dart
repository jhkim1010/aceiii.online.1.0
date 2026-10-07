// [2026-10-07] Pedidos a Ventago — repositorio compartido (mismo archivo en las dos apps).
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tienda_admin_app/features/pedidos/pedidos_repository.dart';

const listaJson = r'''{"items": [{"id": 17, "categoria": "mejora", "asunto": "(asunto)", "estado": "en_curso", "noLeido": true, "ultimoMensaje": "2026-10-07T16:19:59.501Z", "createdAt": "2026-10-06T21:50:32.937Z", "storeId": 22, "itemsTotal": 0, "itemsHechos": 0, "tienda": "Tienda A", "sucursal": "Sucursal A", "autor": "Persona Tienda"}, {"id": 18, "categoria": "mejora", "asunto": "(asunto)", "estado": "resuelto", "noLeido": false, "ultimoMensaje": "2026-10-07T13:58:53.720Z", "createdAt": "2026-10-06T23:40:00.647Z", "storeId": 6, "itemsTotal": 0, "itemsHechos": 0, "tienda": "Tienda B", "sucursal": "Sucursal B", "autor": "Persona Tienda"}], "porPagina": 20}''';
const detalleJson = r'''{"id": 11, "categoria": "mejora", "asunto": "sincronizacion con web", "estado": "resuelto", "createdAt": "2026-10-05T16:27:45.812Z", "storeId": 22, "tienda": "Tienda A", "sucursal": "Sucursal A", "autor": "Persona Tienda", "items": [{"id": 12, "texto": "(renglón)", "hecho": true, "hechoAt": "2026-10-07T01:26:42.558Z", "hechoPor": "Persona Ventago"}, {"id": 13, "texto": "(renglón)", "hecho": true, "hechoAt": "2026-10-07T01:26:44.679Z", "hechoPor": "Persona Ventago"}], "mensajes": [{"id": 57, "desdePlataforma": false, "texto": "(texto)", "fotos": 0, "autor": "Persona Tienda", "createdAt": "2026-10-05T16:27:45.812Z"}, {"id": 60, "desdePlataforma": true, "texto": "(texto)", "fotos": "2", "autor": "Ventago", "createdAt": "2026-10-05T16:37:07.247Z"}]}''';

// Adaptador falso: registra cada pedido y responde con el JSON real (anonimizado) de
// producción tomado el 2026-10-07 — así el parseo se prueba contra la forma verdadera.
class _Falso implements HttpClientAdapter {
  final pedidos = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    pedidos.add(o);
    final path = o.uri.path;
    String json;
    if (path.endsWith('/fotos/0')) {
      return ResponseBody.fromBytes([1, 2, 3], 200, headers: {'content-type': ['image/png']});
    } else if (path.endsWith('/no-leidos')) {
      json = '{"count":"2"}';
    } else if (RegExp(r'/\d+$').hasMatch(path) && o.method == 'GET') {
      json = detalleJson;
    } else if (o.method == 'GET') {
      json = listaJson;
    } else if (o.method == 'POST' && RegExp(r'pedidos-soporte$').hasMatch(path)) {
      json = '{"id":99}';
    } else {
      json = '{"ok":true}';
    }

    return ResponseBody.fromString(json, 200, headers: {'content-type': ['application/json']});
  }

  @override
  void close({bool force = false}) {}
}

(PedidosRepository, _Falso) armar(String base) {
  final f = _Falso();
  final dio = Dio(BaseOptions(baseUrl: 'https://x/api'))..httpClientAdapter = f;

  return (PedidosRepository(dio, base), f);
}

void main() {
  test('lista real: campos, no leído, avance de renglones, tienda', () async {
    final (repo, _) = armar('/pedidos-soporte/plataforma');
    final l = await repo.listar();
    expect(l.length, 2);
    expect(l[0].id, 17);
    expect(l[0].noLeido, isTrue);
    expect(l[0].estado, 'en_curso');
    expect(l[0].tienda, 'Tienda A');
    expect(l[1].noLeido, isFalse);
    expect(l[1].ultimoMensaje, startsWith('2026-10-07'));
  });

  test('detalle real: renglones tildados, mensajes, fotos como texto se leen como número', () async {
    final (repo, _) = armar('/pedidos-soporte/plataforma');
    final p = await repo.detalle(11);
    expect(p.asunto, isNotEmpty);
    expect(p.items, isNotEmpty);
    expect(p.items.every((i) => i.hecho), isTrue);
    expect(p.items.first.hechoPor, isNotNull);
    expect(p.mensajes.length, 2);
    expect(p.mensajes[1].fotos, 2);
  });

  test('plataforma: rutas de estado, tilde, respuesta y foto bajo /plataforma', () async {
    final (repo, f) = armar('/pedidos-soporte/plataforma');
    expect(repo.esPlataforma, isTrue);
    await repo.cambiarEstado(11, 'resuelto');
    await repo.tildarItem(11, 5, false);
    await repo.responder(11, 'hola');
    final b = await repo.foto(11, 7, 0);
    expect(b, [1, 2, 3]);
    expect(f.pedidos.map((o) => '${o.method} ${o.uri.path}').toList(), [
      'PATCH /api/pedidos-soporte/plataforma/11/estado',
      'PATCH /api/pedidos-soporte/plataforma/11/items/5',
      'POST /api/pedidos-soporte/plataforma/11/mensajes',
      'GET /api/pedidos-soporte/plataforma/11/mensajes/7/fotos/0',
    ]);
    expect(f.pedidos[0].data, {'estado': 'resuelto'});
    expect(f.pedidos[1].data, {'hecho': false});
    expect(f.pedidos[2].data, {'texto': 'hola'});
  });

  test('filtros: sin estado no manda estado (= pendientes); búsqueda vacía no manda q', () async {
    final (repo, f) = armar('/pedidos-soporte/plataforma');
    await repo.listar(q: '  ');
    await repo.listar(estado: 'todos', q: ' cielo ');
    expect(f.pedidos[0].queryParameters.containsKey('estado'), isFalse);
    expect(f.pedidos[0].queryParameters.containsKey('q'), isFalse);
    expect(f.pedidos[1].queryParameters['estado'], 'todos');
    expect(f.pedidos[1].queryParameters['q'], 'cielo');
  });

  test('tienda: crear va a /pedidos-soporte con los tres campos y devuelve el id', () async {
    final (repo, f) = armar('/pedidos-soporte');
    expect(repo.esPlataforma, isFalse);
    final id = await repo.crear(categoria: 'reparacion', asunto: 'PC', texto: 'no prende');
    expect(id, 99);
    expect('${f.pedidos.single.method} ${f.pedidos.single.uri.path}', 'POST /api/pedidos-soporte');
    expect(f.pedidos.single.data, {'categoria': 'reparacion', 'asunto': 'PC', 'texto': 'no prende'});
    expect(await repo.noLeidos(), 2);
  });

  test('mensajeDeError: message de Nest (texto o lista) y 403', () {
    DioException err(int code, Object? data) => DioException(
          requestOptions: RequestOptions(),
          response: Response(requestOptions: RequestOptions(), statusCode: code, data: data),
        );
    expect(mensajeDeError(err(400, {'message': 'Completá el asunto y el detalle.'})), 'Completá el asunto y el detalle.');
    expect(mensajeDeError(err(400, {'message': ['a', 'b']})), 'a\nb');
    expect(mensajeDeError(err(403, null)), 'No tenés permiso para esto.');
    expect(etiquetaCategoria('reparacion'), 'Reparar una computadora');
    expect(etiquetaEstado('en_curso'), 'En curso');
  });
}
