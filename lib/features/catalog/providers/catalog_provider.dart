// 카탈로그 Provider — 검색어 상태 + 상품 목록 로드 + in-memory lastFetch 캐시.
// 캐시는 메모리 전용(criterion #11 오프라인 브라우징 보조). QR 스캔 경로에서 상품 hero
// 정보(name/price)를 productId 로 역참조하는 소스로도 재사용된다.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/catalog_dto.dart';
import '../data/catalog_repository.dart';

// 현재 검색어 (디바운스는 화면에서 처리)
final catalogSearchProvider =
    NotifierProvider<CatalogSearchNotifier, String>(CatalogSearchNotifier.new);

class CatalogSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

// lastFetch 캐시 — productId → CatalogItem (오프라인/QR hero 역참조)
final _catalogCache = <int, CatalogItem>{};

// productId 로 캐시된 카탈로그 상품 조회 (QR 스캔 경로 hero/price 소스)
CatalogItem? cachedCatalogItem(int productId) => _catalogCache[productId];

// 상품 목록 로드 (검색어 변화 시 자동 재조회). 성공분은 in-memory 캐시에 병합.
final catalogListProvider =
    FutureProvider.autoDispose<List<CatalogItem>>((ref) async {
  final search = ref.watch(catalogSearchProvider);
  final repo = ref.read(catalogRepositoryProvider);
  final result = await repo.fetchCatalog(search: search, limit: 50);

  // lastFetch 캐시 병합 (역참조 소스 유지)
  for (final item in result.items) {
    _catalogCache[item.productId] = item;
  }

  return result.items;
});
