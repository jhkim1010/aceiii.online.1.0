// 창고 준비(despacho) 도메인 모델 — null safety 준수.
// 백엔드 online_orders / online_order_items 응답을 방어적으로 파싱한다.

/// 주문 1건의 준비 항목(picking line).
class OrderItem {
  final int? productId;
  final String productName;
  final String? size;
  final String? color;
  final int quantity;

  const OrderItem({
    required this.productName,
    required this.quantity,
    this.productId,
    this.size,
    this.color,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      productId: _asInt(json['productId'] ?? json['product_id']),
      productName:
          (json['productName'] ?? json['product_name'] ?? 'Producto').toString(),
      size: (json['size'] as Object?)?.toString(),
      color: (json['color'] as Object?)?.toString(),
      quantity: _asInt(json['quantity']) ?? 1,
    );
  }

  /// 색/사이즈 표시용 문자열 (없으면 빈 문자열).
  String get variantLabel {
    final parts = <String>[];
    if (color != null && color!.isNotEmpty) parts.add(color!);
    if (size != null && size!.isNotEmpty) parts.add(size!);

    return parts.join(' · ');
  }
}

/// preparing 목록/상세 주문.
class OnlineOrder {
  final int id;
  final int? orderNumber;
  final String? externalOrderNumber;
  final String? channel;
  final String? status;
  final String? columnKey; // 'preparando' | 'listo' 등 (백엔드 파생)
  final String? clientName;
  final String? address;
  final String? branchName;
  final num? total;
  final List<OrderItem> items;

  const OnlineOrder({
    required this.id,
    required this.items,
    this.orderNumber,
    this.externalOrderNumber,
    this.channel,
    this.status,
    this.columnKey,
    this.clientName,
    this.address,
    this.branchName,
    this.total,
  });

  /// 표시용 주문번호 — external 우선, 없으면 내부 orderNumber.
  String get displayNumber {
    if (externalOrderNumber != null && externalOrderNumber!.isNotEmpty) {
      return externalOrderNumber!;
    }

    return orderNumber != null ? '#$orderNumber' : '#$id';
  }

  factory OnlineOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = (json['items'] ?? json['orderItems'] ?? json['online_order_items']) as List<dynamic>?;

    return OnlineOrder(
      id: _asInt(json['id']) ?? 0,
      orderNumber: _asInt(json['orderNumber'] ?? json['order_number']),
      externalOrderNumber:
          (json['externalOrderNumber'] ?? json['external_order_number'])?.toString(),
      channel: (json['channel'] as Object?)?.toString(),
      status: (json['status'] as Object?)?.toString(),
      columnKey: (json['columnKey'] ?? json['column_key'])?.toString(),
      clientName: (json['clientName'] ?? json['client_name'])?.toString(),
      address: (json['address'] as Object?)?.toString(),
      branchName: (json['branchName'] ?? json['branch_name'])?.toString(),
      total: json['total'] is num ? json['total'] as num : num.tryParse('${json['total']}'),
      items: rawItems == null
          ? const <OrderItem>[]
          : rawItems
              .whereType<Map<String, dynamic>>()
              .map(OrderItem.fromJson)
              .toList(),
    );
  }
}

/// 숫자 방어 파서 — 문자열/숫자 혼재 응답 대응.
int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();

  return int.tryParse(v.toString());
}
