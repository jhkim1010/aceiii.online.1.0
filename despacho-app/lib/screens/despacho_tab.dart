import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/order.dart';
import '../providers/app_providers.dart';

/// Despacho 탭(body 전용) — listo(발송 대기) 주문 목록.
/// 주문 탭 → 운송사(transporte) + 운송장번호(tracking) 입력 → 발송(ship).
class DespachoTab extends ConsumerStatefulWidget {
  const DespachoTab({super.key});

  @override
  ConsumerState<DespachoTab> createState() => _DespachoTabState();
}

class _DespachoTabState extends ConsumerState<DespachoTab> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(listoOrdersProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _refresh() => ref.invalidate(listoOrdersProvider);

  Future<void> _openShip(OnlineOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ShipDialog(order: order),
    );
    if (ok == true) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(listoOrdersProvider);

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [
          const SizedBox(height: 100),
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          Padding(padding: const EdgeInsets.all(24), child: Text('$e', textAlign: TextAlign.center)),
        ]),
        data: (orders) {
          if (orders.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.local_shipping_outlined, size: 56, color: Colors.black26),
                SizedBox(height: 8),
                Center(child: Text('No hay pedidos listos para despachar')),
              ],
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: orders.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final o = orders[i];

              return Card(
                elevation: 1,
                child: ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFE3F2FD),
                    child: Icon(Icons.local_shipping, color: Color(0xFF1976D2)),
                  ),
                  title: Text(o.displayNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    [
                      if (o.clientName != null) o.clientName!,
                      if (o.address != null) o.address!,
                    ].join(' · '),
                  ),
                  trailing: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1976D2),
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => _openShip(o),
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Despachar'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 발송 인계 다이얼로그 — transporte 선택 + tracking 입력 → ship.
class _ShipDialog extends ConsumerStatefulWidget {
  const _ShipDialog({required this.order});

  final OnlineOrder order;

  @override
  ConsumerState<_ShipDialog> createState() => _ShipDialogState();
}

class _ShipDialogState extends ConsumerState<_ShipDialog> {
  int? _transporteId;
  final _trackingCtrl = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 주문에 지정된 운송사를 기본값으로.
    _transporteId = widget.order.transporteId;
  }

  @override
  void dispose() {
    _trackingCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final tracking = _trackingCtrl.text.trim();
    if (_transporteId == null) {
      setState(() => _error = 'Seleccioná un transporte.');

      return;
    }
    if (tracking.isEmpty) {
      setState(() => _error = 'Ingresá el código de seguimiento.');

      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No autenticado');
      await api.ship(widget.order.id, transporteId: _transporteId!, trackingCode: tracking);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() {
        _error = '$e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final transportesAsync = ref.watch(transportesProvider);

    return AlertDialog(
      title: Text('Despachar ${widget.order.displayNumber}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            transportesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Error transportes: $e'),
              data: (list) {
                final ids = list.map((t) => t.id).toSet();
                final value = ids.contains(_transporteId) ? _transporteId : null;

                return DropdownButtonFormField<int>(
                  value: value,
                  decoration: const InputDecoration(labelText: 'Transporte'),
                  items: list
                      .map((t) => DropdownMenuItem<int>(value: t.id, child: Text(t.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _transporteId = v),
                );
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _trackingCtrl,
              decoration: const InputDecoration(
                labelText: 'Código de seguimiento',
                hintText: 'Ej: AR123456789',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1976D2)),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: const Text('Confirmar despacho'),
        ),
      ],
    );
  }
}
