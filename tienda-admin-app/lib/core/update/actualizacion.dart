// [2026-10-06] Actualización dentro de la app (Android, APK fuera de Play).
// (mismo archivo en mobile-sales-app y tienda-admin-app)
//
// Al abrir: lee version.json; si hay una versión más nueva pregunta «Actualizar / Más tarde».
// «Actualizar» baja el APK, verifica el SHA-256 y abre el instalador de Android — la persona
// toca «Instalar». Android sólo acepta el APK si está firmado con la MISMA clave que la app
// instalada, así que un APK ajeno no puede reemplazarla.
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'version_remota.dart';

const _canal = MethodChannel('ventago/actualizacion');

// Un chequeo por arranque de la app («Más tarde» = hasta la próxima vez que se abra)
bool _yaChequeado = false;

Future<void> chequearActualizacion(GlobalKey<NavigatorState> navegador, {required String feedUrl}) async {
  if (_yaChequeado || !Platform.isAndroid) {
    return;
  }
  _yaChequeado = true;

  final VersionRemota? remota;
  final int instalada;
  try {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
    final r = await dio.get<Object?>(
      feedUrl,
      options: Options(responseType: ResponseType.json, headers: {'Cache-Control': 'no-cache'}),
    );
    remota = VersionRemota.desdeJson(r.data);
    instalada = await _canal.invokeMethod<int>('versionCode') ?? 0;
  } catch (_) {
    // sin red o feed caído: la app sigue normal, se vuelve a mirar en el próximo arranque
    return;
  }
  final nueva = remota;
  if (nueva == null || instalada <= 0 || !nueva.esMasNuevaQue(instalada)) {
    return;
  }

  final ctx = navegador.currentContext;
  if (ctx == null || !ctx.mounted) {
    return;
  }
  final acepta = await showDialog<bool>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: const Text('Nueva versión disponible'),
      content: Text(
        'Versión ${nueva.versionName}${nueva.notas.isEmpty ? '' : '\n\n${nueva.notas}'}\n\n'
        'Se descarga y Android te pide confirmar la instalación.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Más tarde')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Actualizar')),
      ],
    ),
  );
  if (acepta != true) {
    return;
  }
  final ctx2 = navegador.currentContext;
  if (ctx2 == null || !ctx2.mounted) {
    return;
  }
  await showDialog<void>(
    context: ctx2,
    barrierDismissible: false,
    builder: (_) => _DescargaDialog(remota: nueva),
  );
}

class _DescargaDialog extends StatefulWidget {
  final VersionRemota remota;

  const _DescargaDialog({required this.remota});

  @override
  State<_DescargaDialog> createState() => _DescargaDialogState();
}

class _DescargaDialogState extends State<_DescargaDialog> {
  CancelToken _cancel = CancelToken();
  bool _procesando = false;
  double? _progreso;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bajarEInstalar();
  }

  @override
  void dispose() {
    _cancel.cancel();
    super.dispose();
  }

  Future<void> _bajarEInstalar() async {
    // un intento por vez: dos descargas sobre el mismo archivo se pisan (codex 014)
    if (_procesando) {
      return;
    }
    _procesando = true;
    _cancel = CancelToken();
    setState(() {
      _error = null;
      _progreso = null;
    });
    try {
      final dir = await _canal.invokeMethod<String>('dirDescarga');
      if (dir == null) {
        throw const _Falla('No se pudo preparar la descarga');
      }
      final ruta = '$dir/actualizacion.apk';
      await Dio().download(
        widget.remota.apkUrl,
        ruta,
        cancelToken: _cancel,
        onReceiveProgress: (r, t) {
          if (mounted && t > 0) {
            setState(() => _progreso = r / t);
          }
        },
      );
      // ★ el archivo bajado tiene que ser exactamente el publicado (hash por partes: sin cargar
      //   el APK entero en memoria)
      final digest = await sha256.bind(File(ruta).openRead()).first;
      if (digest.toString() != widget.remota.sha256) {
        await File(ruta).delete();
        throw const _Falla('La descarga llegó dañada. Probá de nuevo.');
      }
      final r = await _canal.invokeMethod<String>('instalar', {'ruta': ruta});
      if (!mounted) {
        return;
      }
      if (r == 'permiso') {
        setState(() => _error =
            'Activá «Permitir de esta fuente» para esta app en la pantalla que se abrió, volvé y tocá «Reintentar».');

        return;
      }
      Navigator.pop(context);
    } on _Falla catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } on DioException catch (e) {
      // «Cancelar» cierra el diálogo y corta la descarga: no es un error
      if (mounted && !CancelToken.isCancel(e)) {
        setState(() => _error = 'No se pudo descargar la actualización. Revisá la conexión.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'No se pudo instalar la actualización.');
    } finally {
      _procesando = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;

    return AlertDialog(
      title: Text('Actualizando a ${widget.remota.versionName}'),
      content: error != null
          ? Text(error)
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(value: _progreso),
                const SizedBox(height: 10),
                Text(_progreso == null ? 'Descargando…' : 'Descargando… ${(_progreso! * 100).floor()}%'),
              ],
            ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(error != null ? 'Cerrar' : 'Cancelar')),
        if (error != null) FilledButton(onPressed: _procesando ? null : _bajarEInstalar, child: const Text('Reintentar')),
      ],
    );
  }
}

class _Falla implements Exception {
  final String mensaje;

  const _Falla(this.mensaje);
}
