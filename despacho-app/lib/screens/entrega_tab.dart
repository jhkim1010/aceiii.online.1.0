import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/order.dart';
import '../providers/app_providers.dart';

/// Entrega 탭(body 전용) — enviado(발송됨) 주문의 배송 완료(Entregado) 확인.
/// 주문의 "Entregar" 버튼 → 확인 다이얼로그 → deliver.
class EntregaTab extends ConsumerStatefulWidget {
  const EntregaTab({super.key});

  @override
  ConsumerState<EntregaTab> createState() => _EntregaTabState();
}

class _EntregaTabState extends ConsumerState<EntregaTab> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(enviadoOrdersProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _refresh() => ref.invalidate(enviadoOrdersProvider);

  Future<void> _confirmDeliver(OnlineOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Entregar ${order.displayNumber}'),
        content: Text(
          '¿Confirmás la entrega${order.clientName != null ? ' a ${order.clientName}' : ''}? '
          'Se registrará la venta y el descuento de stock.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2E7D32)),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.check),
            label: const Text('Confirmar entrega'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No autenticado');
      await api.deliver(order.id);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${order.displayNumber} entregado')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  /// P2 되돌리기 — en_transito → Listo(un-ship). 판매가 역처리된다는 경고 포함.
  /// 외상 발송이면 서버가 400 으로 차단 → 에러 스낵바로 안내.
  Future<void> _confirmRevert(OnlineOrder order) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revertir ${order.displayNumber}'),
        content: const Text(
          'Al revertir el envío se anula la venta registrada (contra-asiento en Ventas) '
          'y el pedido vuelve a "Listo p/ despacho". ¿Continuar?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFB26A00)),
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.undo),
            label: const Text('Revertir'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No autenticado');
      await api.revert(order.id);
      _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${order.displayNumber} revertido a Listo')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(enviadoOrdersProvider);

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
                Icon(Icons.check_circle_outline, size: 56, color: Colors.black26),
                SizedBox(height: 8),
                Center(child: Text('No hay pedidos enviados pendientes de entrega')),
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
                    backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.assignment_turned_in, color: Color(0xFF2E7D32)),
                  ),
                  title: Text(o.displayNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    [
                      if (o.clientName != null) o.clientName!,
                      if (o.address != null) o.address!,
                    ].join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // P2 되돌리기 — Listo 로 un-ship (판매 역처리 경고 다이얼로그).
                      IconButton(
                        tooltip: 'Revertir a Listo',
                        onPressed: () => _confirmRevert(o),
                        icon: const Icon(Icons.undo, color: Color(0xFFB26A00)),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF2E7D32),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () => _confirmDeliver(o),
                        icon: const Icon(Icons.check, size: 18),
                        label: const Text('Entregar'),
                      ),
                    ],
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
