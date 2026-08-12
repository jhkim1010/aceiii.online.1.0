import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/network/dio_client.dart';
import '../../shared/format.dart';

// Código madre 편집 — 웹(ProductsView / VariationPanel)과 **같은 API** 를 쓴다.
//   목록   GET  /products/by-parent?parent=false          (parent=false 가 부모 목록이다)
//   상세   GET  /products/:id/inventory-by-date-branch    (날짜 + 지점 기준 변형/수량)
//   저장   PUT  /products/:id/edit-madre-variants         (삭제/추가/수량수정 일괄)
//
// ★ 이 화면은 **특정 날짜 + 특정 지점**의 입고 변형을 다룬다. 날짜·지점이 바뀌면
//   보이는 수량도 저장 대상도 달라진다 — 화면 상단에 항상 노출한다.

// ── 모델 ──────────────────────────────────────────────────────────────

class MadreParent {
  final int id;
  final String sku;
  final String name;
  final int variantCount;

  MadreParent.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        sku = (j['sku'] ?? '').toString(),
        name = (j['name'] ?? '').toString(),
        variantCount = j['variants'] is List
            ? (j['variants'] as List).length
            : asInt(j['variantCount']);
}

class MadreVariant {
  final int id; // products.id (updateVariants 의 variantId)
  final int colorId;
  final String colorName;
  final int sizeId;
  final String sizeName;
  final int stock;

  MadreVariant.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id'] ?? j['productId']),
        colorId = asInt(j['color'] is Map ? j['color']['id'] : j['colorId']),
        colorName = (j['color'] is Map ? j['color']['name'] : j['colorName'] ?? '')
            .toString(),
        sizeId = asInt(j['size'] is Map ? j['size']['id'] : j['sizeId']),
        sizeName =
            (j['size'] is Map ? j['size']['name'] : j['sizeName'] ?? '').toString(),
        stock = asInt(j['stock']);
}

class MadreInventory {
  final String parentName;
  final String parentSku;
  final List<MadreVariant> variants;

  const MadreInventory({
    required this.parentName,
    required this.parentSku,
    required this.variants,
  });
}

// 변형 추가용 마스터 (색상 / 사이즈)
class NamedRef {
  final int id;
  final String name;
  NamedRef.fromJson(Map<String, dynamic> j)
      : id = asInt(j['id']),
        name = (j['name'] ?? '').toString();
}

// 저장 페이로드 — 웹 handleMadreSave 와 같은 모양.
class MadreSavePayload {
  final String date; // YYYY-MM-DD
  final List<int> branchIds;
  final List<int> deleteColorIds;
  final List<({int colorId, int sizeId, int stock})> addVariants;
  final List<({int variantId, int newStock})> updateVariants;

  const MadreSavePayload({
    required this.date,
    required this.branchIds,
    required this.deleteColorIds,
    required this.addVariants,
    required this.updateVariants,
  });

  bool get isEmpty =>
      deleteColorIds.isEmpty && addVariants.isEmpty && updateVariants.isEmpty;

  Map<String, dynamic> toJson() => {
        'date': date,
        'branchIds': branchIds,
        'deleteColorIds': deleteColorIds,
        'addVariants': [
          for (final a in addVariants)
            {'colorId': a.colorId, 'sizeId': a.sizeId, 'stock': a.stock},
        ],
        'updateVariants': [
          for (final u in updateVariants)
            {'variantId': u.variantId, 'newStock': u.newStock},
        ],
      };
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

  Future<MadreInventory> getInventory({
    required int parentId,
    required String date,
    required int branchId,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/products/$parentId/inventory-by-date-branch',
      queryParameters: {'date': date, 'branchId': branchId},
    );

    final body = res.data ?? const <String, dynamic>{};
    final data = (body['data'] is Map<String, dynamic>)
        ? body['data'] as Map<String, dynamic>
        : body;
    final parent = (data['parent'] is Map<String, dynamic>)
        ? data['parent'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final variants = (data['variants'] as List<dynamic>? ?? const []);

    return MadreInventory(
      parentName: (parent['name'] ?? '').toString(),
      parentSku: (parent['sku'] ?? '').toString(),
      variants: variants
          .map((e) => MadreVariant.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Future<void> save(int parentId, MadreSavePayload payload) async {
    await _dio.put<dynamic>(
      '/products/$parentId/edit-madre-variants',
      data: payload.toJson(),
    );
  }

  Future<List<NamedRef>> getColors() => _named('/colors/by-store');
  Future<List<NamedRef>> getSizes() => _named('/sizes/by-store');

  Future<List<NamedRef>> _named(String path) async {
    final res = await _dio.get<dynamic>(path);
    final body = res.data;
    final rows = body is Map<String, dynamic>
        ? (body['data'] as List<dynamic>? ?? const [])
        : (body as List<dynamic>? ?? const []);

    return rows.map((e) => NamedRef.fromJson(e as Map<String, dynamic>)).toList();
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

typedef MadreScope = ({int parentId, String date, int branchId});

final madreInventoryProvider =
    FutureProvider.autoDispose.family<MadreInventory, MadreScope>((ref, s) {
  return ref.read(codigoMadreRepositoryProvider).getInventory(
        parentId: s.parentId,
        date: s.date,
        branchId: s.branchId,
      );
});

final madreColorsProvider = FutureProvider.autoDispose<List<NamedRef>>(
  (ref) => ref.read(codigoMadreRepositoryProvider).getColors(),
);

final madreSizesProvider = FutureProvider.autoDispose<List<NamedRef>>(
  (ref) => ref.read(codigoMadreRepositoryProvider).getSizes(),
);
