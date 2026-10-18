// Reporte a medida — cliente HTTP (/api/reporte-medida/*). Nunca envía la tienda ni permisos:
// la tienda la fuerza el servidor desde el token. Errores HTTP → estado de UI (port de errores.ts).
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/dio_client.dart';
import '../auth/auth_controller.dart';
import 'rm_modelos.dart';

const copyTimeout =
    'No pudimos armar el reporte a tiempo. Probá con un período más corto o un Top, y volvé a tocar Ver reporte.';
const copyRed = 'Sin conexión. Revisá tu internet y volvé a intentar.';
const copyPermiso = 'No tenés permiso para esto. Pedile acceso al administrador del local.';
const copyOcupado = 'Ya hay un reporte en curso. Esperá a que termine para pedir otro.';
const copyNoEncontrado = 'Ese reporte guardado ya no existe.';

enum TipoErrorRm { validacion, permiso, timeout, servidor, ocupado, noEncontrado, csvGrande, duplicado, red }

class ErrorRm implements Exception {
  final TipoErrorRm tipo;
  final String mensajeEs;
  final List<ErrorPedido> errores;
  final List<String> fixesCsv;
  const ErrorRm(this.tipo, this.mensajeEs, {this.errores = const [], this.fixesCsv = const []});

  @override
  String toString() => mensajeEs;
}

ErrorRm clasificarError(Object e) {
  if (e is ErrorRm) return e;
  if (e is! DioException) return const ErrorRm(TipoErrorRm.servidor, copyTimeout);
  final resp = e.response;
  if (resp == null) {
    final esTimeout = e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionTimeout;

    return esTimeout
        ? const ErrorRm(TipoErrorRm.timeout, copyTimeout)
        : const ErrorRm(TipoErrorRm.red, copyRed);
  }
  final status = resp.statusCode ?? 0;
  final data = resp.data is Map ? (resp.data as Map).cast<String, dynamic>() : <String, dynamic>{};
  final errores = ((data['errores'] as List?) ?? const [])
      .map((x) => ErrorPedido.fromJson((x as Map).cast<String, dynamic>()))
      .toList();

  if ((status == 400 || status == 403) && errores.isNotEmpty) {
    return ErrorRm(TipoErrorRm.validacion, errores.first.messageEs, errores: errores);
  }
  if (status == 400 && data['code'] != null && data['messageEs'] != null) {
    final err = ErrorPedido('${data['code']}', '${data['messageEs']}');

    return ErrorRm(TipoErrorRm.validacion, err.messageEs, errores: [err]);
  }

  return switch (status) {
    403 => const ErrorRm(TipoErrorRm.permiso, copyPermiso),
    404 => const ErrorRm(TipoErrorRm.noEncontrado, copyNoEncontrado),
    408 => const ErrorRm(TipoErrorRm.timeout, copyTimeout),
    429 => const ErrorRm(TipoErrorRm.ocupado, copyOcupado),
    409 => ErrorRm(TipoErrorRm.duplicado, '${data['messageEs'] ?? 'Ya tenés un reporte con ese nombre'}'),
    422 => ErrorRm(TipoErrorRm.csvGrande, '${data['messageEs'] ?? copyTimeout}',
        fixesCsv: ((data['fixes'] as List?) ?? const [])
            .map((f) => '${(f as Map)['labelEs'] ?? ''}')
            .toList()),
    _ => const ErrorRm(TipoErrorRm.servidor, copyTimeout),
  };
}

class CsvDescargado {
  final Uint8List bytes;
  final String nombre;
  const CsvDescargado(this.bytes, this.nombre);
}

final rmRepositoryProvider = Provider<RmRepository>((ref) => RmRepository(ref.read(dioClientProvider)));

class RmRepository {
  final Dio _dio;
  RmRepository(this._dio);

  static const _base = '/reporte-medida';

  Future<T> _llamar<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw clasificarError(e);
    }
  }

  Map<String, dynamic> _map(Response r) => ((r.data as Map?) ?? const {}).cast<String, dynamic>();

  Future<Catalogo> catalogo() => _llamar(() async =>
      Catalogo.fromJson(_map(await _dio.get('$_base/catalogo'))));

  Future<ValidarRespuesta> validar(Pedido p) => _llamar(() async => ValidarRespuesta.fromJson(_map(
      await _dio.post('$_base/validar',
          data: {'order': p.toJson()},
          options: Options(receiveTimeout: const Duration(seconds: 15))))));

  Future<ResultadoReporte> ejecutar(Pedido p) => _llamar(() async => ResultadoReporte.fromJson(_map(
      await _dio.post('$_base/ejecutar',
          data: {'order': p.toJson()},
          options: Options(receiveTimeout: const Duration(seconds: 30))))));

  Future<ResultadoReporte> ejecutarGuardado(int id) => _llamar(() async => ResultadoReporte.fromJson(_map(
      await _dio.post('$_base/pedidos/$id/ejecutar',
          data: const {}, options: Options(receiveTimeout: const Duration(seconds: 30))))));

  Future<CsvDescargado> _csv(String path, Object data) => _llamar(() async {
        final r = await _dio.post<List<int>>(path,
            data: data,
            options: Options(
                responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)));
        final disp = r.headers.value('content-disposition') ?? '';
        final m = RegExp(r'filename="?([^";]+)"?').firstMatch(disp);
        final hoy = DateTime.now().toIso8601String().substring(0, 10);

        return CsvDescargado(
            Uint8List.fromList(r.data ?? const []), m?.group(1) ?? 'reporte-a-medida-$hoy.csv');
      });

  Future<CsvDescargado> csv(Pedido p) => _csv('$_base/exportar-csv', {'order': p.toJson()});
  Future<CsvDescargado> csvGuardado(int id) => _csv('$_base/pedidos/$id/exportar-csv', const {});

  Future<List<GuardadoListado>> guardados() => _llamar(() async {
        final r = await _dio.get('$_base/pedidos');
        final lista = r.data is List ? r.data as List : ((r.data as Map?)?['items'] as List? ?? const []);

        return lista.map((e) => GuardadoListado.fromJson((e as Map).cast<String, dynamic>())).toList()
          ..sort((a, b) => a.position != b.position ? a.position - b.position : a.id - b.id);
      });

  Future<GuardadoDetalle> guardado(int id) =>
      _llamar(() async => GuardadoDetalle.fromJson(_map(await _dio.get('$_base/pedidos/$id'))));

  Future<int> crear(String name, bool shared, Pedido p) => _llamar(() async {
        final r = await _dio.post('$_base/pedidos', data: {'name': name, 'shared': shared, 'order': p.toJson()});

        return (_map(r)['id'] as num).toInt();
      });

  Future<void> actualizar(int id, {String? name, bool? shared, Pedido? order}) => _llamar(() => _dio.patch(
      '$_base/pedidos/$id',
      data: {'name': ?name, 'shared': ?shared, 'order': ?order?.toJson()}));

  Future<void> eliminar(int id) => _llamar(() => _dio.delete('$_base/pedidos/$id'));

  Future<void> reordenar(List<int> ids) => _llamar(() => _dio.put('$_base/pedidos/orden', data: {'ids': ids}));

  // Valores de los filtros: las mismas listas de referencia que usa la web.
  // El servidor vuelve a verificar que cada id sea de la tienda.
  Future<List<(int, String)>> valoresFiltro(String filtro, int storeId) async {
    final path = switch (filtro) {
      'sucursales' => '/branch/store/$storeId',
      'vendedores' => '/sellers',
      'mediosPago' => '/payment-methods',
      'categorias' => '/categories/by-store',
      'temporadas' => '/seasons/by-store',
      'colores' => '/colors/by-store',
      'talles' => '/sizes/by-store',
      _ => null,
    };
    if (path == null) return const [];
    final r = await _dio.get(path);
    final d = r.data;
    final lista = d is List ? d : (d is Map && d['data'] is List ? d['data'] as List : const []);

    return lista.whereType<Map>().map((x) {
      final nombre = filtro == 'vendedores'
          ? '${x['name'] ?? ''} ${x['lastName'] ?? ''}'.trim()
          : '${x['title'] ?? x['name'] ?? ''}';

      return ((x['id'] as num).toInt(), nombre.isEmpty ? '${x['id']}' : nombre);
    }).toList();
  }
}

final rmValoresFiltroProvider =
    FutureProvider.autoDispose.family<List<(int, String)>, (String, int)>((ref, k) {
  ref.keepAlive();

  return ref.read(rmRepositoryProvider).valoresFiltro(k.$1, k.$2);
});

// Catálogo: se guarda mientras dure la sesión, pero es POR USUARIO y tienda (el margen bloqueado
// depende de quién mira): si cambia el usuario logueado se vuelve a pedir.
final rmCatalogoProvider = FutureProvider.autoDispose<Catalogo>((ref) {
  ref.watch(authControllerProvider.select((s) => (s.user?.id, s.user?.storeId)));
  ref.keepAlive();

  return ref.read(rmRepositoryProvider).catalogo();
});

final rmGuardadosProvider = FutureProvider.autoDispose<List<GuardadoListado>>((ref) {
  ref.watch(authControllerProvider.select((s) => (s.user?.id, s.user?.storeId)));

  return ref.read(rmRepositoryProvider).guardados();
});
