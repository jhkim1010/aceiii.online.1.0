import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/order.dart';
import '../providers/app_providers.dart';

/// 주문 상세 — 마스터-디테일:
///   좌측: código madre(상품) 리스트, 우측: 선택 상품의 color × talle 테이블.
/// 각 (color,talle) 셀을 탭해 준비 완료 표시. 모든 셀 체크 시에만 Listo 활성(오배송 방지).
class OrderDetailScreen extends ConsumerStatefulWidget {
  const OrderDetailScreen({required this.orderId, super.key});

  final int orderId;

  @override
  ConsumerState<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

// 상품 1종(código madre)의 color × talle 그룹.
class _ProductGroup {
  _ProductGroup(this.name);

  final String name;
  final List<String> colors = []; // '' = 색 정보 없음
  final List<String> sizes = []; //  '' = talle 정보 없음
  final Map<String, int> cellQty = {}; // 'color|size' -> 수량 합
  int totalQty = 0;

  Iterable<String> get cellKeys => cellQty.keys.map((k) => '$name::$k');
}

class _OrderDetailScreenState extends ConsumerState<OrderDetailScreen> {
  // 준비 완료 셀 키('name::color|size') 집합.
  final Set<String> _checked = <String>{};
  String? _selectedProduct;
  bool _submitting = false;

  List<_ProductGroup> _groupByProduct(List<OrderItem> items) {
    final byName = <String, _ProductGroup>{};
    for (final it in items) {
      final g = byName.putIfAbsent(it.productName, () => _ProductGroup(it.productName));
      final color = it.color ?? '';
      final size = it.size ?? '';
      if (!g.colors.contains(color)) g.colors.add(color);
      if (!g.sizes.contains(size)) g.sizes.add(size);
      final k = '$color|$size';
      g.cellQty[k] = (g.cellQty[k] ?? 0) + it.quantity;
      g.totalQty += it.quantity;
    }

    return byName.values.toList();
  }

  int _groupDone(_ProductGroup g) => g.cellKeys.where(_checked.contains).length;

  Future<void> _markReady() async {
    setState(() => _submitting = true);
    try {
      final api = ref.read(apiServiceProvider);
      if (api == null) throw Exception('No autenticado');
      await api.markReady(widget.orderId);
      ref.invalidate(preparingOrdersProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pedido listo para despacho')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
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
          child: Padding(padding: const EdgeInsets.all(24), child: Text('$e', textAlign: TextAlign.center)),
        ),
        data: _buildBody,
      ),
    );
  }

  Widget _buildBody(OnlineOrder order) {
    final groups = _groupByProduct(order.items);
    final allKeys = groups.expand((g) => g.cellKeys).toList();
    final total = allKeys.length;
    final done = _checked.where(allKeys.contains).length;
    final allChecked = total > 0 && done >= total;

    // 선택 상품 기본값 = 첫 상품.
    final selectedName = _selectedProduct ?? (groups.isNotEmpty ? groups.first.name : null);
    final selected = groups.where((g) => g.name == selectedName).cast<_ProductGroup?>().firstWhere(
          (g) => true,
          orElse: () => null,
        );

    return Column(
      children: [
        _header(order),
        Expanded(
          child: total == 0
              ? const Center(child: Text('Sin items en el pedido'))
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── 좌: código madre 리스트 ──
                    SizedBox(
                      width: 260,
                      child: _productList(groups, selectedName),
                    ),
                    const VerticalDivider(width: 1),
                    // ── 우: 색 × talle 테이블 ──
                    Expanded(child: selected == null ? const SizedBox() : _detailPane(selected)),
                  ],
                ),
        ),
        _footer(done, total, allChecked),
      ],
    );
  }

  Widget _productList(List<_ProductGroup> groups, String? selectedName) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: groups.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final g = groups[i];
        final done = _groupDone(g);
        final total = g.cellQty.length;
        final complete = total > 0 && done >= total;
        final isSel = g.name == selectedName;

        return Container(
          color: isSel ? const Color(0xFFFDEBD0) : null,
          child: ListTile(
            dense: true,
            selected: isSel,
            title: Text(g.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text('Total ${g.totalQty} · $done/$total'),
            trailing: complete
                ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32), size: 20)
                : const Icon(Icons.chevron_right, size: 18),
            onTap: () => setState(() => _selectedProduct = g.name),
          ),
        );
      },
    );
  }

  Widget _detailPane(_ProductGroup g) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(g.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              Text('Total ${g.totalQty}', style: const TextStyle(color: Colors.black54)),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Tocá cada casillero a medida que lo preparás.',
            style: TextStyle(color: Colors.black45, fontSize: 12),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: _matrix(g),
            ),
          ),
        ),
      ],
    );
  }

  // color(행) × talle(열) 매트릭스. 셀 = 수량 + 탭 시 준비완료 표시.
  Widget _matrix(_ProductGroup g) {
    const headerStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 13);

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(color: const Color(0xFFE0E0E0)),
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF3F3F7)),
          children: [
            _cellPad(const Text('Color / Talle', style: headerStyle)),
            ...g.sizes.map((s) => _cellPad(Text(s.isEmpty ? '—' : s, style: headerStyle, textAlign: TextAlign.center))),
          ],
        ),
        ...g.colors.map((c) {
          return TableRow(
            children: [
              _cellPad(Text(c.isEmpty ? '—' : c, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
              ...g.sizes.map((s) {
                final k = '$c|$s';
                final qty = g.cellQty[k];
                if (qty == null) {
                  return _cellPad(const Center(child: Text('·', style: TextStyle(color: Colors.black26))));
                }
                final key = '${g.name}::$k';
                final checked = _checked.contains(key);

                return TableCell(
                  child: InkWell(
                    onTap: () => _toggle(key),
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 56, minHeight: 48),
                      color: checked ? const Color(0xFF2E7D32) : Colors.transparent,
                      alignment: Alignment.center,
                      child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$qty',
                            style: TextStyle(
                              color: checked ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            )),
                        Icon(
                          checked ? Icons.check_circle : Icons.radio_button_unchecked,
                          size: 16,
                          color: checked ? Colors.white : Colors.black38,
                        ),
                      ],
                    ),
                    ),
                  ),
                );
              }),
            ],
          );
        }),
      ],
    );
  }

  Widget _cellPad(Widget child) =>
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), child: child);

  void _toggle(String key) => setState(() {
        if (_checked.contains(key)) {
          _checked.remove(key);
        } else {
          _checked.add(key);
        }
      });

  Widget _footer(int done, int total, bool allChecked) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE0E0E0)))),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Text('$done / $total preparados', style: const TextStyle(color: Colors.black54)),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: allChecked ? const Color(0xFFF5A623) : Colors.grey.shade400,
                  foregroundColor: const Color(0xFF0F0F1E),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: (!allChecked || _submitting) ? null : _markReady,
                icon: _submitting
                    ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_circle),
                label: const Text('Listo para despacho', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(OnlineOrder order) {
    return Container(
      width: double.infinity,
      color: const Color(0xFF1A1A2E),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(order.displayNumber,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          if (order.clientName != null)
            Text(order.clientName!, style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}
