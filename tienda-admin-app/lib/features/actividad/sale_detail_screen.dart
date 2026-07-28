import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/format.dart';

// ── 모델 (GET /sales/:id — detalle-de-venta) ──

class SaleItemDetail {
  final num quantity;
  final num price;
  final num subtotal;
  final num discountAmount;
  final String name; // customName > product.name > parent.name
  final String? sku;
  final String? color;
  final String? size;

  SaleItemDetail.fromJson(Map<String, dynamic> j)
      : quantity = asNum(j['quantity']),
        price = asNum(j['price']),
        subtotal = asNum(j['subtotal']),
        discountAmount = asNum(j['discountAmount']),
        name = _itemName(j),
        sku = (j['product'] is Map) ? j['product']['sku'] as String? : null,
        color = _nested(j, 'color'),
        size = _nested(j, 'size');

  static String _itemName(Map<String, dynamic> j) {
    final custom = j['customName'];
    if (custom != null && '$custom'.isNotEmpty) return '$custom';
    final p = j['product'];
    if (p is Map) {
      final parent = p['parent'];
      if (parent is Map && parent['name'] != null) return '${parent['name']}';
      if (p['name'] != null) return '${p['name']}';
    }

    return 'Artículo';
  }

  static String? _nested(Map<String, dynamic> j, String key) {
    final p = j['product'];
    if (p is Map && p[key] is Map) return p[key]['name'] as String?;

    return null;
  }
}

class SalePayment {
  final num amount;
  final String method; // paymentMethod.title (+ option)

  SalePayment.fromJson(Map<String, dynamic> j)
      : amount = asNum(j['amount']),
        method = _method(j);

  static String _method(Map<String, dynamic> j) {
    final base = (j['paymentMethod'] is Map)
        ? (j['paymentMethod']['title'] ?? '').toString()
        : '';
    final opt = (j['paymentMethodsOption'] is Map)
        ? (j['paymentMethodsOption']['title'] ?? '').toString()
        : '';
    if (base.isEmpty) return opt.isEmpty ? 'Pago' : opt;

    return opt.isEmpty ? base : '$base · $opt';
  }
}

class SaleDetail {
  final int id;
  final int dailyNumber;
  final String saleDate;
  final String status;
  final num subtotal;
  final num discountAmount;
  final num totalAmount;
  final String? notes;
  final String? clientName;
  final String? clientDocument;
  final String? sellerName;
  final List<SaleItemDetail> items;
  final List<SalePayment> payments;

  SaleDetail.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        dailyNumber = asInt(j['dailyNumber']),
        saleDate = (j['saleDate'] ?? '').toString(),
        status = (j['status'] ?? '').toString(),
        subtotal = asNum(j['subtotal']),
        discountAmount = asNum(j['discountAmount']),
        totalAmount = asNum(j['totalAmount']),
        notes = j['notes'] as String?,
        clientName = (j['client'] is Map)
            ? j['client']['fullname'] as String?
            : null,
        clientDocument = (j['client'] is Map)
            ? j['client']['document'] as String?
            : null,
        sellerName = _seller(j),
        items = ((j['saleItems'] as List?) ?? const [])
            .map((e) => SaleItemDetail.fromJson(e as Map<String, dynamic>))
            .toList(),
        payments = ((j['salePaymentMethods'] as List?) ?? const [])
            .map((e) => SalePayment.fromJson(e as Map<String, dynamic>))
            .toList();

  static String? _seller(Map<String, dynamic> j) {
    for (final key in ['seller', 'user']) {
      final m = j[key];
      if (m is Map) {
        final full = [m['name'], m['lastName']]
            .where((e) => e != null && '$e'.isNotEmpty)
            .join(' ')
            .trim();
        if (full.isNotEmpty) return full;
      }
    }

    return null;
  }
}

// ── Provider ──

final saleDetailProvider =
    FutureProvider.autoDispose.family<SaleDetail, int>((ref, id) async {
  final dio = ref.read(dioClientProvider);
  final res = await dio.get<Map<String, dynamic>>('/sales/$id');

  return SaleDetail.fromJson(res.data ?? const {});
});

// ── 화면 ──

class SaleDetailScreen extends ConsumerWidget {
  final int saleId;
  const SaleDetailScreen({super.key, required this.saleId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(saleDetailProvider(saleId));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.navy2,
        title: Text('Venta #$saleId',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(saleDetailProvider(saleId));
          await ref.read(saleDetailProvider(saleId).future);
        },
        child: async.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                    'No se pudo cargar el detalle.\n${e is DioException ? (e.response?.statusCode ?? '') : ''} $e',
                    style:
                        const TextStyle(color: AppColors.red, fontSize: 12)),
              ),
            ],
          ),
          data: (s) => _body(s),
        ),
      ),
    );
  }

  Widget _body(SaleDetail s) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
      children: [
        // 헤더 카드: 총액 + 메타
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('TOTAL',
                      style: TextStyle(
                          fontSize: 9.5,
                          letterSpacing: 0.6,
                          fontWeight: FontWeight.w700,
                          color: AppColors.dim)),
                  const Spacer(),
                  if (s.status.isNotEmpty)
                    Text(s.status.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.dim)),
                ],
              ),
              const SizedBox(height: 5),
              Text(money(s.totalAmount),
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.gold)),
              const SizedBox(height: 7),
              Text(
                [
                  fullDate(s.saleDate),
                  if (s.dailyNumber > 0) 'Nº del día ${s.dailyNumber}',
                  if (s.sellerName != null) s.sellerName!,
                ].join(' · '),
                style: const TextStyle(fontSize: 11, color: AppColors.dim),
              ),
              Text(
                [
                  s.clientName ?? 'Consumidor final',
                  if (s.clientDocument != null &&
                      s.clientDocument!.isNotEmpty)
                    'Doc ${s.clientDocument}',
                ].join(' · '),
                style: const TextStyle(fontSize: 11.5, color: AppColors.txt),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle('ARTÍCULOS (${s.items.length})'),
        _card(
          child: Column(
            children: [
              for (var i = 0; i < s.items.length; i++) ...[
                if (i > 0) const Divider(height: 14, color: AppColors.line),
                _itemRow(s.items[i]),
              ],
              if (s.items.isEmpty)
                const Text('Sin artículos',
                    style: TextStyle(color: AppColors.dim, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle('PAGOS'),
        _card(
          child: Column(
            children: [
              for (var i = 0; i < s.payments.length; i++) ...[
                if (i > 0) const Divider(height: 14, color: AppColors.line),
                Row(
                  children: [
                    Expanded(
                      child: Text(s.payments[i].method,
                          style: const TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w700)),
                    ),
                    Text(money(s.payments[i].amount),
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: AppColors.green)),
                  ],
                ),
              ],
              if (s.payments.isEmpty)
                const Text('Sin pagos registrados',
                    style: TextStyle(color: AppColors.dim, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _sectionTitle('RESUMEN'),
        _card(
          child: Column(
            children: [
              _amtRow('Subtotal', s.subtotal, AppColors.txt),
              const Divider(height: 16, color: AppColors.line),
              _amtRow('Descuentos', -s.discountAmount, AppColors.red),
              const Divider(height: 16, color: AppColors.line),
              _amtRow('Total', s.totalAmount, AppColors.gold),
            ],
          ),
        ),
        if (s.notes != null && s.notes!.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionTitle('NOTAS'),
          _card(
            child: Text(s.notes!,
                style: const TextStyle(fontSize: 12, color: AppColors.txt)),
          ),
        ],
      ],
    );
  }

  Widget _itemRow(SaleItemDetail it) {
    final variant = [
      if (it.color != null) it.color!,
      if (it.size != null) it.size!,
    ].join(' / ');

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.navy2,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(_trimQty(it.quantity),
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.cyan)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(it.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w700)),
              Text(
                [
                  if (it.sku != null && it.sku!.isNotEmpty) it.sku!,
                  if (variant.isNotEmpty) variant,
                  '${_trimQty(it.quantity)} × ${money(it.price)}',
                ].join(' · '),
                style: const TextStyle(fontSize: 10.5, color: AppColors.dim),
              ),
            ],
          ),
        ),
        Text(money(it.subtotal),
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w800)),
      ],
    );
  }

  Widget _amtRow(String label, num value, Color color) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(money(value),
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Text(t,
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.5,
                fontWeight: FontWeight.w800,
                color: AppColors.dim)),
      );

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
  }

  // 3.0 → 3, 2.5 → 2.5
  String _trimQty(num q) =>
      q == q.roundToDouble() ? q.toInt().toString() : q.toString();
}

// dd/MM HH:mm
String fullDate(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  final l = d.toLocal();

  return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')}/${l.year} '
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
