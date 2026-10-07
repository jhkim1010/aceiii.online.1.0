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
