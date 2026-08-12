import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../shared/format.dart';

// Códigos madre — 부모 상품의 **마스터 정보** 편집: 이름 / 가격유형별 가격 / 공개몰 게시.
//
//   목록   GET  /products/by-parent?parent=false   (parent=false 가 부모다)
//   이름   PUT  /products/:id                      권한 editar-un-producto
//   가격   POST /products/bulk-update-prices       권한 cambiar-precio-individual
//   공개몰 PUT  /products/publish-shop             권한 publicar-o-no-publicar-producto
//   가격유형 GET /price-types
//
// ★ 가격은 반드시 `bulk-update-prices` 로 보낸다. 이 라우트만 부모 편집 시
//   [부모 + 자식 전부] 의 prices 행을 갱신하고 base 가격유형이면 products.price 도 맞춘다.
//   - `bulk-update-explicit` 은 부모가 대상이면 **자식만** 고치고 부모 행은 그대로 둬서
//     다시 열었을 때 옛 값이 보인다.
//   - `PUT /prices/:id` 는 그 행 하나뿐이라 **정작 POS 가 파는 자식 가격이 안 바뀐다**.
//   웹(CodigoVistaView)도 같은 라우트를 쓴다 — 두 화면이 갈라지지 않게 맞춰 둔다.

// ── 모델 ──────────────────────────────────────────────────────────────

class PriceTypeRef {
  final int id;
  final String name;
  final bool isBase;

  const PriceTypeRef({
    required this.id,
    required this.name,
    required this.isBase,
  });
}

class MadreParent {
  final int id;
  final String sku;
  final String name;
  final int variantCount;
  final bool isPublishedShop;

  /// products.price 컬럼 (base 가격 폴백 — prices 행이 없는 제품이 많다)
  final num basePrice;

  /// 부모 자신의 prices 행: priceTypeId → amount
  final Map<int, num> parentPrices;

  /// 자식들의 prices: priceTypeId → 자식들이 가진 서로 다른 금액 집합.
  /// 원소가 2개 이상이면 그 가격유형은 자식끼리 값이 갈려 있다는 뜻이다.
  final Map<int, Set<num>> variantPrices;

  const MadreParent({
    required this.id,
    required this.sku,
    required this.name,
    required this.variantCount,
    required this.isPublishedShop,
    required this.basePrice,
    required this.parentPrices,
    required this.variantPrices,
  });

  factory MadreParent.fromJson(Map<String, dynamic> j) {
    final parentPrices = _pricesOf(j['prices']);

    final variants = (j['stockByVariant'] as List<dynamic>? ?? const []);
    final variantPrices = <int, Set<num>>{};
    for (final v in variants) {
      if (v is! Map<String, dynamic>) continue;
      _pricesOf(v['prices']).forEach((ptId, amount) {
        variantPrices.putIfAbsent(ptId, () => <num>{}).add(amount);
      });
    }

    return MadreParent(
      id: asInt(j['id']),
      sku: (j['sku'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      variantCount: variants.length,
      isPublishedShop: j['isPublishedShop'] == true,
      basePrice: asNum(j['price']),
      parentPrices: parentPrices,
      variantPrices: variantPrices,
    );
  }

  /// `prices: [{amount, priceType: {id}}]` → `{priceTypeId: amount}`
  static Map<int, num> _pricesOf(dynamic raw) {
    final out = <int, num>{};
    if (raw is! List) return out;
    for (final p in raw) {
      if (p is! Map) continue;
      final pt = p['priceType'];
      final ptId = asInt(pt is Map ? pt['id'] : p['priceTypeId']);
      if (ptId == 0) continue;
      out[ptId] = asNum(p['amount']);
    }

    return out;
  }

  /// 화면에 보여줄 금액 — 부모 행 → 자식 공통값 → base 폴백 순.
  num amountFor(PriceTypeRef pt) {
    final own = parentPrices[pt.id];
    if (own != null) return own;

    final fromVariants = variantPrices[pt.id];
    if (fromVariants != null && fromVariants.isNotEmpty) {
      return fromVariants.first;
    }

    return pt.isBase ? basePrice : 0;
  }

  /// 이 가격유형이 부모/자식 사이에서 값이 갈려 있는가.
  /// 저장하면 전부 한 값으로 통일되므로 **저장 전에** 사용자에게 알려야 한다.
  bool isMixed(PriceTypeRef pt) {
    final distinct = <num>{};
    final own = parentPrices[pt.id];
    if (own != null) distinct.add(own);
    distinct.addAll(variantPrices[pt.id] ?? const <num>{});

    // 자식이 있는데 그 가격유형 행이 아예 없는 자식이 섞여 있어도 "갈림"이다
    final withRow = variantPrices[pt.id]?.length ?? 0;
    final missingSomeChild = variantCount > 0 && withRow == 0 && own != null;

    return distinct.length > 1 || missingSomeChild;
  }
}

// ── 리포지토리 ────────────────────────────────────────────────────────

class CodigoMadreRepository {
  final Dio _dio;
  CodigoMadreRepository(this._dio);

  // 부모 목록. ★ parent=false 가 부모(padres)다 — true 는 변형(codigo hijito)을 준다
  // (`findByParentFlag` 의 플래그는 "parentId 가 있는가" 이므로 뜻이 뒤집혀 보인다).
  Future<List<MadreParent>> searchParents({String? query, int limit = 60}) async {
    final res = await _dio.get<dynamic>('/products/by-parent', queryParameters: {
      'parent': 'false',
      'page': 0,
      'pageSize': limit,
      if (query != null && query.trim().isNotEmpty) 'query': query.trim(),
    });

    final body = res.data;
    final rows = body is Map<String, dynamic>
        ? (body['data'] as List<dynamic>? ?? const [])
        : (body as List<dynamic>? ?? const []);

    return rows
        .map((e) => MadreParent.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  // 가격유형. 웹과 같은 규칙으로 거른다:
  //   status 는 INTEGER(1=ACTIVE) — 'ACTIVE' 문자열 비교는 항상 false 였다(웹 주석 참조).
  //   이름에 'PRECIO' 가 든 것이 base 이고 항상 맨 앞에 온다.
  Future<List<PriceTypeRef>> getPriceTypes() async {
    final res = await _dio.get<dynamic>('/price-types');
    final body = res.data;
    final rows = body is Map<String, dynamic>
        ? (body['data'] as List<dynamic>? ?? const [])
        : (body as List<dynamic>? ?? const []);

    final active = rows.whereType<Map<String, dynamic>>().where((j) {
      final s = j['status'];

      return s == null || asInt(s) == 1;
    }).toList();

    final baseRe = RegExp('precio', caseSensitive: false);
    final baseIdx = active.indexWhere(
      (j) => baseRe.hasMatch((j['name'] ?? '').toString()),
    );

    final list = [
      for (var i = 0; i < active.length; i++)
        PriceTypeRef(
          id: asInt(active[i]['id']),
          name: (active[i]['name'] ?? '').toString(),
          // base 미검출이면 첫 번째를 base 로 본다 (웹 levels 규칙과 동일)
          isBase: i == (baseIdx >= 0 ? baseIdx : 0),
        ),
    ];

    // base 를 맨 앞으로 — 나머지는 원래 순서 유지
    list.sort((a, b) => (b.isBase ? 1 : 0) - (a.isBase ? 1 : 0));

    return list;
  }

  Future<void> updateName(int productId, String name) async {
    await _dio.put<dynamic>('/products/$productId', data: {'name': name});
  }

  // 일괄 토글 라우트라 단건도 배열로 보낸다.
  Future<void> setPublishedShop(int productId, bool published) async {
    await _dio.put<dynamic>('/products/publish-shop', data: {
      'productIds': [productId],
      'published': published,
    });
  }

  // 부모 대상이면 서버가 부모 + 자식 전부에 같은 금액을 upsert 한다.
  Future<void> updatePrices(int productId, Map<int, num> byPriceType) async {
    if (byPriceType.isEmpty) return;
    await _dio.post<dynamic>('/products/bulk-update-prices', data: [
      {
        'productId': productId,
        'prices': [
          for (final e in byPriceType.entries)
            {'priceTypeId': e.key, 'newAmount': e.value},
        ],
      },
    ]);
  }
}

// ── 프로바이더 ────────────────────────────────────────────────────────

final codigoMadreRepositoryProvider = Provider<CodigoMadreRepository>(
  (ref) => CodigoMadreRepository(ref.read(dioClientProvider)),
);

final madreParentsProvider =
    FutureProvider.autoDispose.family<List<MadreParent>, String>((ref, query) {
  return ref.read(codigoMadreRepositoryProvider).searchParents(query: query);
});

final madrePriceTypesProvider = FutureProvider.autoDispose<List<PriceTypeRef>>(
  (ref) => ref.read(codigoMadreRepositoryProvider).getPriceTypes(),
);
