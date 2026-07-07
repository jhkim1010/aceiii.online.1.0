import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/order.dart';
import '../providers/app_providers.dart';

/// 주문 상세 — picking 체크리스트 + "Listo para despacho".
/// 모든 항목 체크 시에만 Listo 활성화(오배송 방지). Listo → mark-ready 호출.
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final int orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  final Set<int> _checked = <int>{};
  bool _submitting = false;

  Future<void> _markReady(int total) async {
    if (_checked.length < total) return;
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No autenticado');
      await api.markReady(widget.orderId);

      // 목록 갱신 후 뒤로.
      ref.invalidate(preparingOrdersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido listo para despacho')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(orderDetailProvider(widget.orderId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A1A2E),
        foregroundColor: Colors.white,
        title: const Text('Preparar pedido'),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('$e', textAlign: TextAlign.center),
          ),
        ),
        data: (order) => _buildBody(order),
      ),
    );
  }

  Widget _buildBody(OnlineOrder order) {
    final total = order.items.length;
    final allChecked = total > 0 && _checked.length >= total;

    return Column(
      children: [
        _header(order),
        Expanded(
          child: total == 0
              ? const Center(child: Text('Sin items en el pedido'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: total,
                  itemBuilder: (context, i) {
                    final it = order.items[i];
                    final done = _checked.contains(i);

                    return Card(
                      color: done ? const Color(0xFFE8F5E9) : null,
                      child: CheckboxListTile(
                        value: done,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _checked.add(i);
                          } else {
                            _checked.remove(i);
                          }
                        }),
                        title: Text(
                          it.productName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: it.variantLabel.isEmpty
                            ? null
                            : Text(it.variantLabel),
                        secondary: CircleAvatar(
                          backgroundColor: const Color(0xFF1A1A2E),
                          child: Text(
                            'x${it.quantity}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  '${_checked.length} / $total preparados',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: allChecked
                          ? const Color(0xFFF5A623)
                          : Colors.grey.shade400,
                      foregroundColor: const Color(0xFF0F0F1E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed:
                        (!allChecked || _submitting) ? null : () => _markReady(total),
                    icon: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle),
                    label: const Text(
                      'Listo para despacho',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _header(OnlineOrder order) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            order.displayNumber,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          if (order.clientName != null)
            Text(order.clientName!, style: const TextStyle(color: Colors.white70)),
          if (order.address != null)
            Text(order.address!, style: const TextStyle(color: Colors.white54)),
        ],
      ),
    );
  }
}
