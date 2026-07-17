# Revendedor 지역 추천 — Plan C (vendedor 앱: 추천제품 + 지방 캡처) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** 판매원 앱(`mobile-sales-app`, Flutter)에 ① 기본 메뉴 아래 "추천제품" 버튼 → 그 매장 재고 있는 지역 베스트셀러를 손님에게 추천(장바구니 담기) ② 판매 시 구매자 provincia 스마트기본 캡처.

**Architecture:** Plan A 의 `GET /mobile/recommended-products`(user/vendedor JWT, 자기 매장 재고>0 지역 top) 소비. Riverpod `AsyncNotifierProvider` 로 추천 목록, 기존 판매/장바구니 흐름에 연결. provincia 는 판매 생성 payload 에 `provinceId` 추가(고객 province 프리필). Dio 인터셉터 JWT 재사용.

**Tech Stack:** Flutter + Riverpod + Dio + null-safety (dart 스타일 가이드).

**설계/의존:** `docs/superpowers/specs/2026-07-16-revendedor-zona-recomendacion-design.md`, Plan A(`/mobile/recommended-products`, 판매 create `provinceId` 완료 전제).

## Global Constraints

- **null-safety 준수**, Riverpod 상태관리, dart 스타일 가이드(effective_dart). 함수/변수명 영어, 주석 한국어, **사용자 노출 문자열 스페인어**.
- **에러 핸들링 항상 포함** — 네트워크 실패 시 인라인 메시지 + 재시도. 빈 목록/권한거부 graceful.
- 기존 Dio 클라이언트 + JWT 인터셉터 **재사용**(신규 인증 만들지 않음). 서버 URL 은 기존 설정(`SERVER_URL` 고정).
- **mobile-sales-app 은 별도 nested private repo**(gitlink). `cd mobile-sales-app` 후 커밋·푸시 별도(루트 서브모듈 bump 필요).
- 기존 feature 폴더 구조(`lib/features/...`) + 프로바이더 패턴을 **먼저 읽고 정합**. 아래 경로/클래스명은 제안 — 실제 구조에 맞춰 조정.
- 검증: `cd mobile-sales-app && flutter analyze`(0 issue) + `flutter test`(해당) + `flutter build apk --debug`(빌드 확인).

---

### Task 1: API 클라이언트 — 추천제품 조회 + 판매 provincia

**Files:**
- Modify: `mobile-sales-app/lib/core/api/api_client.dart` (or 기존 API 서비스 파일) — `getRecommendedProducts`, 판매 create 에 `provinceId`
- Create: `mobile-sales-app/lib/features/recommendations/data/recommended_product.dart` (모델)
- Test: `mobile-sales-app/test/features/recommendations/recommended_product_test.dart`

**Interfaces:**
- Consumes: Plan A `GET /mobile/recommended-products?provinceId`.
- Produces:
  ```dart
  class RecommendedProduct { int productId; String name; String sku; num price; int qty60d; num? trendPct; bool inStock; }
  Future<List<RecommendedProduct>> getRecommendedProducts({int? provinceId});
  ```

- [ ] **Step 1: 모델 파싱 실패 테스트**

Create `mobile-sales-app/test/features/recommendations/recommended_product_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sales_app/features/recommendations/data/recommended_product.dart';

void main() {
  test('RecommendedProduct.fromJson 파싱', () {
    final json = {
      'productId': 10,
      'name': 'Remera oversize',
      'sku': '26010001',
      'price': 12900,
      'qty60d': 96,
      'trendPct': 32.0,
      'inStock': true,
    };
    final p = RecommendedProduct.fromJson(json);
    expect(p.productId, 10);
    expect(p.name, 'Remera oversize');
    expect(p.inStock, true);
    expect(p.trendPct, 32.0);
  });

  test('trendPct null 허용', () {
    final p = RecommendedProduct.fromJson({
      'productId': 1, 'name': 'X', 'sku': 'S', 'price': 100, 'qty60d': 5, 'trendPct': null, 'inStock': false,
    });
    expect(p.trendPct, isNull);
  });
}
```

> **주의:** 패키지명(`mobile_sales_app`)을 `pubspec.yaml` 의 `name:` 으로 확인해 import 를 정합화.

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd mobile-sales-app && flutter test test/features/recommendations/recommended_product_test.dart`
Expected: FAIL — 모델 없음.

- [ ] **Step 3: 모델 구현**

Create `mobile-sales-app/lib/features/recommendations/data/recommended_product.dart`:

```dart
// vendedor "추천제품" 항목 — 매장 재고 있는 지역 베스트셀러.
class RecommendedProduct {
  final int productId;
  final String name;
  final String sku;
  final num price;
  final int qty60d;
  final num? trendPct;
  final bool inStock;

  const RecommendedProduct({
    required this.productId,
    required this.name,
    required this.sku,
    required this.price,
    required this.qty60d,
    required this.trendPct,
    required this.inStock,
  });

  factory RecommendedProduct.fromJson(Map<String, dynamic> json) {
    return RecommendedProduct(
      productId: json['productId'] as int,
      name: json['name'] as String? ?? '',
      sku: json['sku'] as String? ?? '',
      price: json['price'] as num? ?? 0,
      qty60d: json['qty60d'] as int? ?? 0,
      trendPct: json['trendPct'] as num?,
      inStock: json['inStock'] as bool? ?? false,
    );
  }
}
```

- [ ] **Step 4: API 메서드 추가**

기존 API 클라이언트(Dio)에 추가(경로는 실제 파일에 맞춤):

```dart
// 자기 매장 재고 있는 지역 베스트셀러. provinceId 없으면 매장 전체 베스트셀러.
Future<List<RecommendedProduct>> getRecommendedProducts({int? provinceId}) async {
  final res = await _dio.get(
    '/mobile/recommended-products',
    queryParameters: provinceId != null ? {'provinceId': provinceId} : null,
  );
  final list = (res.data as List).cast<Map<String, dynamic>>();

  return list.map(RecommendedProduct.fromJson).toList();
}
```

판매 create 메서드(기존)에 `provinceId` 파라미터 추가 → payload 에 포함:
```dart
// 판매 생성 payload 에 provinceId(구매자 지방) 추가 — 지역 추천 데이터 소스.
if (provinceId != null) body['provinceId'] = provinceId;
```

- [ ] **Step 5: 테스트 통과 + analyze**

Run: `cd mobile-sales-app && flutter test test/features/recommendations/recommended_product_test.dart`
Expected: PASS — 2개.

Run: `cd mobile-sales-app && flutter analyze lib/features/recommendations`
Expected: No issues.

- [ ] **Step 6: 커밋**

```bash
cd mobile-sales-app
git add lib/features/recommendations/data/recommended_product.dart test/features/recommendations/ lib/core/api/api_client.dart
git commit -m "feat(recommendations): 추천제품 API + 판매 provincia payload

RecommendedProduct 모델 + getRecommendedProducts(자기 매장 재고 지역 top) +
판매 create provinceId 추가."
```

---

### Task 2: Riverpod 프로바이더 — 추천 목록 상태

**Files:**
- Create: `mobile-sales-app/lib/features/recommendations/providers/recommended_products_provider.dart`
- Test: `mobile-sales-app/test/features/recommendations/recommended_products_provider_test.dart`

**Interfaces:**
- Consumes: Task 1 API. 현재 세션 store + 선택된 고객 provinceId(있으면).
- Produces: `recommendedProductsProvider(int? provinceId)` → `AsyncValue<List<RecommendedProduct>>`.

- [ ] **Step 1: 프로바이더 실패 테스트**

Create `mobile-sales-app/test/features/recommendations/recommended_products_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_sales_app/features/recommendations/data/recommended_product.dart';
import 'package:mobile_sales_app/features/recommendations/providers/recommended_products_provider.dart';

void main() {
  test('프로바이더가 API 결과를 노출', () async {
    final fake = [
      const RecommendedProduct(productId: 1, name: 'X', sku: 'S', price: 100, qty60d: 5, trendPct: null, inStock: true),
    ];
    final container = ProviderContainer(overrides: [
      recommendedProductsRepoProvider.overrideWithValue(_FakeRepo(fake)),
    ]);
    addTearDown(container.dispose);

    final result = await container.read(recommendedProductsProvider(null).future);
    expect(result.length, 1);
    expect(result.first.productId, 1);
  });
}

class _FakeRepo implements RecommendedProductsRepo {
  _FakeRepo(this.data);
  final List<RecommendedProduct> data;
  @override
  Future<List<RecommendedProduct>> fetch({int? provinceId}) async => data;
}
```

- [ ] **Step 2: 테스트 실패 확인**

Run: `cd mobile-sales-app && flutter test test/features/recommendations/recommended_products_provider_test.dart`
Expected: FAIL — 프로바이더 없음.

- [ ] **Step 3: 프로바이더 구현**

Create `mobile-sales-app/lib/features/recommendations/providers/recommended_products_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/recommended_product.dart';

// API 를 감싸는 repo (테스트 override 지점). 실제 구현은 기존 api_client 주입.
abstract class RecommendedProductsRepo {
  Future<List<RecommendedProduct>> fetch({int? provinceId});
}

// 실제 repo — 기존 apiClientProvider 를 주입해 구현(경로 정합).
final recommendedProductsRepoProvider = Provider<RecommendedProductsRepo>((ref) {
  // 예: final api = ref.watch(apiClientProvider);
  //     return _ApiRecommendedProductsRepo(api);
  throw UnimplementedError('apiClientProvider 주입으로 교체');
});

// 추천 목록 — provinceId(선택된 고객 지방)별. family.
final recommendedProductsProvider =
    FutureProvider.family<List<RecommendedProduct>, int?>((ref, provinceId) async {
  final repo = ref.watch(recommendedProductsRepoProvider);

  return repo.fetch(provinceId: provinceId);
});
```

실제 repo 구현(같은 파일 하단 or 별도):
```dart
class ApiRecommendedProductsRepo implements RecommendedProductsRepo {
  ApiRecommendedProductsRepo(this._api);
  final dynamic _api; // 기존 ApiClient 타입으로 교체

  @override
  Future<List<RecommendedProduct>> fetch({int? provinceId}) {
    return _api.getRecommendedProducts(provinceId: provinceId);
  }
}
```
그리고 `recommendedProductsRepoProvider` 를 `ApiRecommendedProductsRepo(ref.watch(apiClientProvider))` 로 교체.

> **주의:** `apiClientProvider`(기존 Dio 클라이언트 프로바이더) 실제 이름 확인 후 주입.

- [ ] **Step 4: 테스트 통과 + analyze**

Run: `cd mobile-sales-app && flutter test test/features/recommendations/recommended_products_provider_test.dart`
Expected: PASS — 1개.

Run: `cd mobile-sales-app && flutter analyze lib/features/recommendations`
Expected: No issues.

- [ ] **Step 5: 커밋**

```bash
cd mobile-sales-app
git add lib/features/recommendations/providers/ test/features/recommendations/recommended_products_provider_test.dart
git commit -m "feat(recommendations): Riverpod 프로바이더 — 추천 목록 상태

recommendedProductsProvider(provinceId) family + repo override 지점(테스트)."
```

---

### Task 3: "추천제품" 버튼 + 추천 화면

**Files:**
- Modify: `mobile-sales-app/lib/features/home/...` (기본 메뉴 화면 — 버튼 2개 아래 "추천제품" 추가)
- Create: `mobile-sales-app/lib/features/recommendations/screens/recommended_products_screen.dart`
- Modify: 라우터(기존 `app_router.dart` 등) — 경로 추가

**Interfaces:**
- Consumes: Task 2 프로바이더, 현재 세션 store(자동), 선택 고객 provinceId(있으면).
- Produces: 추천 화면. 항목 → 장바구니 담기(Task 4).

- [ ] **Step 1: 추천 화면 위젯**

Create `mobile-sales-app/lib/features/recommendations/screens/recommended_products_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/recommended_products_provider.dart';

// vendedor 손님 추천 화면 — 매장 재고 있는 지역 베스트셀러
class RecommendedProductsScreen extends ConsumerWidget {
  const RecommendedProductsScreen({super.key, this.provinceId});

  final int? provinceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recommendedProductsProvider(provinceId));

    return Scaffold(
      appBar: AppBar(title: const Text('Productos recomendados')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _ErrorRetry(onRetry: () => ref.invalidate(recommendedProductsProvider(provinceId))),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('Aún no hay recomendaciones para esta zona.'));
          }

          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = items[i];

              return ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(p.name),
                subtitle: Text(
                  p.trendPct != null && p.trendPct! > 0
                      ? '\$${p.price}  ·  ▲ +${p.trendPct}%'
                      : '\$${p.price}',
                ),
                trailing: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(p), // Task 4: 장바구니 담기
                  child: const Text('Agregar'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('No se pudieron cargar las recomendaciones.'),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: onRetry, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 기본 메뉴에 "추천제품" 버튼**

기존 홈/메뉴 화면(버튼 2개 있는 곳)에 세 번째 버튼 추가. 실제 위젯 구조 확인 후 동일 스타일로:

```dart
// 기본 메뉴 버튼 2개 아래
_MenuButton(
  icon: Icons.local_fire_department,
  label: 'Productos recomendados',
  onTap: () {
    // 선택된 고객 provinceId 있으면 전달(없으면 매장 베스트셀러)
    final provinceId = ref.read(selectedClientProvinceProvider); // 기존 고객선택 상태서 도출
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecommendedProductsScreen(provinceId: provinceId)),
    );
  },
),
```

> **주의:** `_MenuButton` 위젯·기존 메뉴 파일·`selectedClientProvinceProvider`(고객 선택 상태) 실제 이름을 확인해 맞춘다. 고객 provinceId 상태가 없으면 null 전달(매장 베스트셀러 폴백).

- [ ] **Step 3: analyze + 커밋**

Run: `cd mobile-sales-app && flutter analyze lib/features/recommendations lib/features/home`
Expected: No issues.

```bash
cd mobile-sales-app
git add lib/features/recommendations/screens/ lib/features/home/
git commit -m "feat(recommendations): 추천제품 버튼 + 화면

기본 메뉴 아래 '추천제품' 버튼 → 매장 재고 지역 베스트셀러 목록(손님 추천).
로딩/에러/빈목록 처리."
```

---

### Task 4: 추천 → 장바구니 담기 + provincia 스마트기본 캡처

**Files:**
- Modify: 판매/장바구니 화면(추천 항목 pop 결과 → 장바구니 add)
- Modify: 판매 생성 호출부(provinceId 전달 — 고객 province 프리필)

**Interfaces:**
- Consumes: Task 3 화면 pop(선택 RecommendedProduct), Task 1 판매 create provinceId.
- Produces: 추천 상품 장바구니 추가 + 판매에 provincia 기록.

- [ ] **Step 1: 추천 결과 → 장바구니**

"추천제품" 버튼 onTap 을 결과 수신형으로:
```dart
final picked = await Navigator.of(context).push<RecommendedProduct?>(
  MaterialPageRoute(builder: (_) => RecommendedProductsScreen(provinceId: provinceId)),
);
if (picked != null) {
  // 기존 장바구니 add 로직 호출 (productId 로 상품 로드 후 add)
  await ref.read(cartProvider.notifier).addByProductId(picked.productId);
}
```

> **주의:** 기존 장바구니 프로바이더/메서드(`cartProvider.addByProductId` 등) 실제 API 확인. productId 만으로 add 가 안 되면 상품 상세 로드 후 add.

- [ ] **Step 2: 판매 생성 provincia 스마트기본**

판매 확정 호출부에서 provinceId 를 고객 province 로 프리필(비강제):
```dart
// 스마트기본: 선택 고객의 province, 없으면 null(캡처 안 함)
final provinceId = selectedClient?.provinceId;
await api.createSale(..., provinceId: provinceId);
```
고객 미선택/province 없음 → null(판매는 정상, province 만 비움). 강제 아님(Z-16).

> **주의:** 선택 고객 모델에 `provinceId` 가 있는지 확인. 없으면 고객 상세 응답에 province 포함되도록 기존 고객 조회를 확인(백엔드 clients.province_id 이미 존재).

- [ ] **Step 3: analyze + 빌드 확인 + 커밋**

Run: `cd mobile-sales-app && flutter analyze`
Expected: No issues.

Run: `cd mobile-sales-app && flutter build apk --debug`
Expected: BUILD SUCCESSFUL.

```bash
cd mobile-sales-app
git add lib/features/
git commit -m "feat(recommendations): 추천 → 장바구니 + 판매 provincia 스마트기본

추천 항목 선택 → 장바구니 담기. 판매 생성 시 고객 province 프리필(비강제)로
sales.province_id 캡처(데이터 플라이휠)."
```

- [ ] **Step 4: nested repo push + 루트 서브모듈 bump**

```bash
cd mobile-sales-app && git push origin <branch>
cd .. && git add mobile-sales-app && git commit -m "chore: bump mobile-sales-app — 추천제품 + provincia 캡처"
```

---

## Self-Review

**커버리지:** Z-14(추천제품 버튼 T3), Z-11/16(provincia 스마트기본 캡처 T4), 매장 재고 필터(T1 API + Plan A), 손님 추천→장바구니(T4). 에러/빈목록/재시도 처리(T3).

**미해결/주의(구현자):** 패키지명·apiClientProvider·홈 메뉴 위젯·cartProvider·selectedClient province 등 기존 구조 확인 후 정합. mobile-sales-app 은 nested repo 라 별도 push + 루트 bump. Plan A `/mobile/recommended-products` 배포 전제(구버전 앱은 이 기능만 미동작, 판매는 정상).

**전체 3-플랜 배포 순서:** Plan A 마이그레이션+백엔드 → (Cron 요약 채워짐) → Plan B 웹 → Plan C 모바일. 각 독립 배포 가능하나 A 가 API 선행.
