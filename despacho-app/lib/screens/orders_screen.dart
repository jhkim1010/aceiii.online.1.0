import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import 'order_detail_screen.dart';

/// Preparación 탭(body 전용) — preparando 주문 목록.
/// 자동 폴링(15초) + 상세(picking 매트릭스)로 이동. HomeShell 이 상단 토글/AppBar 제공.
class PreparacionTab extends ConsumerStatefulWidget {
  const PreparacionTab({super.key});

  @override
  ConsumerState<PreparacionTab> createState() => _PreparacionTabState();
}

class _PreparacionTabState extends ConsumerState<PreparacionTab> {
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) ref.invalidate(preparingOrdersProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  void _refresh() => ref.invalidate(preparingOrdersProvider);

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(preparingOrdersProvider);

    return RefreshIndicator(
      onRefresh: () async => _refresh(),
      child: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorView(message: '$e', onRetry: _refresh),
        data: (orders) {
          if (orders.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                Icon(Icons.inbox_outlined, size: 56, color: Colors.black26),
                SizedBox(height: 8),
                Center(child: Text('No hay pedidos para preparar')),
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
                    backgroundColor: Color(0xFFFDEBD0),
                    child: Icon(Icons.inventory_2, color: Color(0xFFF5A623)),
                  ),
                  title: Text(o.displayNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    [
                      if (o.clientName != null) o.clientName!,
                      if (o.channel != null) o.channel!,
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => OrderDetailScreen(orderId: o.id),
                      ),
                    );
                    _refresh();
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 100),
        const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(message, textAlign: TextAlign.center),
        ),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ),
      ],
    );
  }
}
