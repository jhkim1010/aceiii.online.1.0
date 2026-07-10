import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

class MensajesScreen extends ConsumerStatefulWidget {
  const MensajesScreen({super.key});

  @override
  ConsumerState<MensajesScreen> createState() => _MensajesScreenState();
}

class _MensajesScreenState extends ConsumerState<MensajesScreen> {
  String _scope = 'store';
  String _level = 'info';
  int? _singleId;
  final Set<int> _selected = {};
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _sending = false;
  String? _sent;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  int _targetCount(List<Tenant> stores) => switch (_scope) {
        'all' => stores.length,
        'stores' => _selected.length,
        _ => _singleId != null ? 1 : 0,
      };

  Future<void> _send(List<Tenant> stores) async {
    setState(() {
      _sending = true;
      _sent = null;
    });
    try {
      final count = await ref.read(consoleRepositoryProvider).sendNotice(
            scope: _scope,
            level: _level,
            title: _title.text.trim(),
            body: _body.text.trim(),
            storeIds: _selected.toList(),
            storeId: _singleId,
          );
      setState(() {
        _sent = 'Enviado a $count cliente(s).';
        _title.clear();
        _body.clear();
        _selected.clear();
        _singleId = null;
      });
      ref.invalidate(noticeHistoryProvider);
    } finally {
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tenantsAsync = ref.watch(tenantsProvider);
    final history = ref.watch(noticeHistoryProvider);

    return tenantsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e', style: const TextStyle(color: AppColors.red))),
      data: (stores) {
        final canSend = _targetCount(stores) > 0 &&
            _title.text.trim().isNotEmpty &&
            _body.text.trim().isNotEmpty &&
            !_sending;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Mensajes a clientes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            // 대상
            const Text('Destino', style: TextStyle(color: AppColors.dim, fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: [
                const ButtonSegment(value: 'store', label: Text('Uno')),
                const ButtonSegment(value: 'stores', label: Text('Varios')),
                ButtonSegment(value: 'all', label: Text('Todos (${stores.length})')),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
            ),
            const SizedBox(height: 12),
            if (_scope == 'store')
              DropdownButtonFormField<int>(
                initialValue: _singleId,
                decoration: const InputDecoration(labelText: 'Cliente'),
                items: stores.map((s) => DropdownMenuItem(value: s.storeId, child: Text(s.storeName))).toList(),
                onChanged: (v) => setState(() => _singleId = v),
              ),
            if (_scope == 'stores')
              Card(
                child: Column(
                  children: stores
                      .map((s) => CheckboxListTile(
                            dense: true,
                            value: _selected.contains(s.storeId),
                            title: Text(s.storeName),
                            secondary: s.errors24h > 0
                                ? Text('${s.errors24h} err', style: const TextStyle(color: AppColors.red, fontSize: 12))
                                : null,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _selected.add(s.storeId);
                              } else {
                                _selected.remove(s.storeId);
                              }
                            }),
                          ))
                      .toList(),
                ),
              ),

            const SizedBox(height: 16),
            const Text('Nivel', style: TextStyle(color: AppColors.dim, fontSize: 12)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'info', label: Text('Info')),
                ButtonSegment(value: 'warning', label: Text('Aviso')),
                ButtonSegment(value: 'dunning', label: Text('Dunning')),
              ],
              selected: {_level},
              onSelectionChanged: (s) => setState(() => _level = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Título'),
              maxLength: 200,
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _body,
              decoration: const InputDecoration(labelText: 'Mensaje'),
              maxLines: 4,
              maxLength: 5000,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Se enviará a ${_targetCount(stores)} cliente(s)', style: const TextStyle(color: AppColors.dim)),
                const Spacer(),
                FilledButton.icon(
                  onPressed: canSend ? () => _send(stores) : null,
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(_sending ? 'Enviando…' : 'Enviar'),
                  style: _level == 'dunning' ? FilledButton.styleFrom(backgroundColor: AppColors.red) : null,
                ),
              ],
            ),
            if (_sent != null) ...[
              const SizedBox(height: 8),
              Text(_sent!, style: const TextStyle(color: AppColors.green)),
            ],

            const SizedBox(height: 24),
            const Text('Historial de envíos', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...history.maybeWhen(
              data: (list) => list
                  .map((c) => Card(
                        child: ListTile(
                          dense: true,
                          title: Text(c.title),
                          subtitle: Text('${c.level} · ${c.createdAt}', style: const TextStyle(color: AppColors.dim, fontSize: 12)),
                          trailing: Text('${c.read}/${c.total}', style: const TextStyle(color: AppColors.dim)),
                        ),
                      ))
                  .toList(),
              orElse: () => [const SizedBox.shrink()],
            ),
          ],
        );
      },
    );
  }
}
