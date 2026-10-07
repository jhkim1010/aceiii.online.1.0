import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import 'pedidos_repository.dart';

// [2026-10-07] Hilo de un pedido — mismo archivo en las dos apps. La plataforma además
// cambia el estado y tilda los renglones; la tienda sólo lee y responde.
// La lista recarga siempre al volver (abrirlo ya lo marca leído), así que no devuelve nada.

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
      // [codex 043] si se cerró mientras enviaba, el controller ya no existe
      if (mounted) _respuesta.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;

    return Scaffold(
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
