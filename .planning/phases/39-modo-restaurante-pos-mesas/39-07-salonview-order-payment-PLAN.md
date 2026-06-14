---
phase: 39-modo-restaurante-pos-mesas
plan: 07
type: execute
wave: 4
depends_on: [39-03, 39-05, 39-06]
files_modified:
  - ventago-app/src/pages/nueva-venta/index.tsx
  - ventago-app/src/views/restaurante/SalonView.tsx
  - ventago-app/src/views/restaurante/components/TableCard.tsx
  - ventago-app/src/views/restaurante/components/OrderModal.tsx
  - ventago-app/src/views/restaurante/components/RestaurantPaymentModal.tsx
autonomous: false
requirements: [REQ-4, REQ-6, REQ-7, REQ-8, REQ-9, REQ-10, REQ-11]
must_haves:
  truths:
    - "식당 매장 nueva-venta 진입 시 useRestaurantMode 분기로 SalonView 가 렌더된다 (소매는 VcontrolHome)"
    - "테이블이 DB 위치/형태/상태대로 렌더되고 상태별 색상 구분된다"
    - "테이블 클릭 → 웨이터 선택 → 메뉴(products+식당 카테고리 필터)·수량 → 주방 전달(comanda)"
    - "테이블 카드 버튼으로 served_at/closed_at 타이밍 마킹"
    - "결제 전 cuenta 출력 + 현금/카드/MP 수금 + split + merge + 결제 후 영수증"
  artifacts:
    - path: "ventago-app/src/views/restaurante/SalonView.tsx"
      provides: "배치도 판매 화면 (상태별 색상, 테이블 렌더)"
      contains: "useRestaurantTables"
    - path: "ventago-app/src/views/restaurante/components/OrderModal.tsx"
      provides: "웨이터 선택 + 메뉴/수량 + 주방 전달"
      contains: "restaurant-sale/order"
    - path: "ventago-app/src/views/restaurante/components/RestaurantPaymentModal.tsx"
      provides: "현금/카드/MP + split/merge + cuenta/영수증"
      contains: "pay-merge"
  key_links:
    - from: "ventago-app/src/pages/nueva-venta/index.tsx"
      to: "SalonView / VcontrolHome"
      via: "useStoreConfig().useRestaurantMode 분기 (next/dynamic ssr:false)"
      pattern: "useRestaurantMode"
    - from: "OrderModal 주방 전달"
      to: "POST /restaurant-sale/order"
      via: "apiConnector.post → 백엔드 comanda emit"
      pattern: "restaurant-sale/order"
---

<objective>
req4/6/7/8/9/10/11 프론트 절반: (1) nueva-venta 분기(useRestaurantMode → SalonView/VcontrolHome), (2) SalonView 배치도 렌더(상태별 색상), (3) OrderModal(웨이터+메뉴 필터+수량+주방 전달), (4) 타이밍 버튼, (5) RestaurantPaymentModal(cuenta+현금/카드/MP+split+merge+영수증). 39-05 백엔드 + 39-03 print_temp 핸들러를 소비.

Purpose: 식당 모드의 사용자 대면 전체 흐름. print_temp 핸들러(39-03) 없이는 comanda/resumen 출력이 무동작하므로 depends_on 필수.
Output: 분기 + SalonView + TableCard + OrderModal + RestaurantPaymentModal.

NOTE (wave 4): depends_on [39-03(wave 1), 39-05(wave 3), 39-06(wave 3)] 중 최대 wave 가 3 이므로 이 플랜은 wave 4. 39-05 백엔드 라우트 + 39-06 StoreConfigContext/useRestaurantTables + 39-03 print_temp 핸들러가 모두 산출된 뒤 실행.
</objective>

<execution_context>
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/workflows/execute-plan.md
@/Users/marcoskim/Trabajos_Programming/ACE_online_1.0/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/phases/39-modo-restaurante-pos-mesas/39-SPEC.md
@.planning/phases/39-modo-restaurante-pos-mesas/39-CONTEXT.md
@.planning/phases/39-modo-restaurante-pos-mesas/39-RESEARCH.md
@CLAUDE.md
@.claude/skills/sketch-findings-ace-online/SKILL.md

<interfaces>
<!-- 재사용 컨트랙트 (코드베이스 + 39-05/39-06 산출) -->
nueva-venta/index.tsx (현재):
```typescript
const VcontrolHome = dynamic(() => import('src/views/homes/VcontrolHome'), { ssr: false })
// → useStoreConfig().useRestaurantMode 로 SalonView 분기 추가
```
StoreConfigContext (39-06): { useRestaurantMode, restaurantCategoryIds, loaded }.
useRestaurantTables (39-06): { tables: RestaurantTableRow[], mutate }. RestaurantTableRow={id,name,shape,seats,posX,posY,status,currentSaleId}.
백엔드 라우트 (39-05):
  POST  /restaurant-sale/order          { tableId, sellerId, sellerName, items:[{productId,qty,price}] }
  PATCH /restaurant-sale/:id/timing     { event: 'served'|'closed' }
  POST  /restaurant-sale/:id/cuenta     → cuenta 감열 출력 (DRAFT 유지)
  POST  /restaurant-sale/:id/pay        { payments:[{paymentMethodId, optionId?, amount}] }  // split=복수 행
  POST  /restaurant-sale/pay-merge      { saleIds:[], payments:[] }
useSellers (ventago-app/src/views/homes/hook/useSellers.tsx — 인자 없는 default export):
  const { sellers } = useSellers()  // 전체 /sellers SWR 반환. branchId 인자 없음 → 웨이터 필터는 호출처에서 (seller.branchId === branchId).
useCategoriesByStore + products SWR: 메뉴.
MP QR 결제: Phase 29 PaymentSummaryModal QR side-panel 패턴(sketch payment-modal-qr) 재사용.
apiConnector: get/post/put/remove (NOT delete). 정규화 좌표→픽셀: left=posX*containerW.
형태+좌석수 비례 크기(39-RESEARCH): BASE={circle:56,oval:72,square:56,rect:80}; scale=0.8+min(seats,12)/12*0.6.
테마: 다크 네이비+골드. 상태 색: libre(중립)/ocupada(골드)/por_cobrar(경고). MP cyan #00b1ea.
</interfaces>
</context>

<tasks>

<task type="auto">
  <name>Task 1: nueva-venta 분기 + SalonView + TableCard (배치도 렌더, 상태 색상, 타이밍 버튼)</name>
  <read_first>
    - ventago-app/src/pages/nueva-venta/index.tsx (현재 VcontrolHome dynamic 분기 지점 — 무변경 보존 + 분기 추가)
    - ventago-app/src/views/homes/VcontrolHome.tsx (SalonView 미러 대상 구조 — 레이아웃/SaleProductsProvider)
    - ventago-app/src/hooks/api/useRestaurantTables.ts (39-06 — tables + RestaurantTableRow)
    - .claude/skills/sketch-findings-ace-online/references/theme.md (다크 네이비+골드, 상태 색상)
    - 39-RESEARCH.md Pattern 5 (분기) + Code Examples (정규화 좌표→픽셀, 비례 크기) + 39-CONTEXT.md D-06 (상태 3색)
  </read_first>
  <action>
**nueva-venta/index.tsx 분기 추가** (기존 VcontrolHome 보존):
```typescript
const SalonView = dynamic(() => import('src/views/restaurante/SalonView'), { ssr: false })
const { useRestaurantMode, loaded } = useStoreConfig()
// loaded 전엔 스켈레톤 — FOUC(소매 뷰 깜빡임) 회피
if (!loaded) return <Skeleton/>

return useRestaurantMode ? <SalonView/> : <VcontrolHome/>
```
WithAccess + SaleProductsProvider 래핑 유지.

**views/restaurante/SalonView.tsx** — 배치도 판매 화면:
- branchId(selectedBranchId, BranchContext) → useRestaurantTables(branchId).
- containerRef 캔버스(다크 네이비 bg, position:relative). 각 테이블 = TableCard(절대 배치).
- 좌표→픽셀: left=posX*containerW, top=posY*containerH (정규화).
- 테이블 클릭 → OrderModal(Task 2) 또는 RestaurantPaymentModal(Task 3) 분기(status 기준: libre/ocupada→주문, por_cobrar→결제).
- **편집 진입점 없음**(req5 권한 분리 — 추가/드래그 버튼 미배치).
- 300ms: next/dynamic 이미 적용, 단일 SWR 조회(JOIN 없음).

**views/restaurante/components/TableCard.tsx** — 테이블 1개:
- 형태+좌석수 비례 크기(BASE+scale). shape 별 borderRadius(circle=50%, oval=40%/긴, square=8px, rect=8px+가로 길게).
- 상태 색상: libre=중립 surface, ocupada=골드 보더/틴트, por_cobrar=경고 골드 강조 (sketch theme).
- 테이블명 + 좌석수 + (점유 시) 경과 시간/금액 요약.
- 타이밍 버튼(점유 테이블): "음식 나옴"(served) / "소비 완료"(closed) → PATCH /restaurant-sale/${currentSaleId}/timing { event }. 에러 인라인 Alert+토스트.
ESLint(return 위 빈 줄, 미사용 import 0). apiConnector.remove(). 한국어 주석.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app && npx eslint src/pages/nueva-venta/index.tsx src/views/restaurante/SalonView.tsx src/views/restaurante/components/TableCard.tsx 2>&1 | tail -20; echo "LINT_DONE"</automated>
  </verify>
  <acceptance_criteria>
    - nueva-venta/index.tsx 에 `useRestaurantMode` 분기 + SalonView dynamic(ssr:false) + VcontrolHome 보존
    - SalonView.tsx 에 useRestaurantTables + 정규화 좌표→픽셀(posX * ) 변환 존재
    - SalonView.tsx 에 테이블 추가/드래그 편집 버튼 0 (권한 분리 — req5)
    - TableCard.tsx 에 상태 3색(libre/ocupada/por_cobrar) 분기 + 형태별 borderRadius
    - TableCard.tsx 에 타이밍 버튼 → PATCH `/restaurant-sale/${...}/timing` { event:'served'|'closed' }
    - npx eslint 3파일 에러 0
  </acceptance_criteria>
  <done>분기 + SalonView 배치도 렌더(상태 색상, 비례 크기) + 타이밍 버튼 완성, ESLint 0. 편집 진입점 없음.</done>
</task>

<task type="auto">
  <name>Task 2: OrderModal (웨이터 선택 + 메뉴 products+카테고리 필터 + 수량 + 주방 전달 comanda)</name>
  <read_first>
    - ventago-app/src/views/restaurante/SalonView.tsx (Task 1 — 모달 호출 + tableId/currentSaleId 전달)
    - ventago-app/src/views/homes/VcontrolHome.tsx (기존 메뉴/상품 선택 UI — products SWR + 수량 입력 패턴 모방)
    - ventago-app/src/hooks/api/useCategoriesByStore.ts (메뉴 카테고리)
    - ventago-app/src/views/homes/hook/useSellers.tsx (웨이터 — 인자 없는 default export, const { sellers } = useSellers() 전체 /sellers 반환. branchId 필터는 호출처에서)
    - ventago-app/src/context/StoreConfigContext.tsx (39-06 — restaurantCategoryIds 필터)
    - 39-CONTEXT.md Claude's Discretion (comanda 증분, 식당 카테고리 필터) + 39-SPEC req6/req11
  </read_first>
  <action>
**views/restaurante/components/OrderModal.tsx** — MUI Dialog (다크 네이비+골드):
- 웨이터 선택: `const { sellers } = useSellers()` (인자 없음 — 전체 /sellers) → 프론트에서 현재 branchId 와 일치하는 seller 만 필터(`sellers.filter((s) => s.branchId === branchId)`) → Select.
- 메뉴: products SWR, **restaurantCategoryIds(StoreConfigContext) 필터** — 이 목록의 categoría 만 표시(req11 비식당 상품 제외). 카테고리 탭 + 상품 그리드.
- 수량: 상품 클릭 → cart 누적 + 수량 +/- (VcontrolHome 패턴 재사용).
- "주방으로 전달"(comanda) 버튼 → apiConnector.post('/restaurant-sale/order', { tableId, sellerId, sellerName, items: cart.map(...) }) → 성공 시 SalonView mutate() (테이블 ocupada 갱신) + 모달 닫기.
  - 백엔드(39-05)가 새 items 만 comanda emit → print_temp 핸들러(39-03)가 인쇄. 프론트는 호출만.
- 추가 주문: 이미 점유 테이블이면 동일 order 라우트(백엔드가 currentSaleId 누적 — req8).
- 에러: 인라인 Alert + 글로벌 토스트 더블.
ESLint(return 위 빈 줄, // 위 빈 줄, 미사용 import 0). apiConnector.remove(). 한국어 주석.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app && npx eslint src/views/restaurante/components/OrderModal.tsx 2>&1 | tail -15; echo "LINT_DONE"</automated>
  </verify>
  <acceptance_criteria>
    - OrderModal.tsx 에 useSellers (인자 없는 `const { sellers } = useSellers()`) + 프론트 branchId 필터(seller.branchId === branchId) + products SWR + restaurantCategoryIds 필터 존재
    - 메뉴가 restaurantCategoryIds 에 포함된 카테고리만 표시(필터 로직) — grep "restaurantCategoryIds"
    - "주방 전달" → apiConnector.post('/restaurant-sale/order', ...) { tableId, sellerId, items } 호출
    - 성공 후 mutate() 호출 (테이블 상태 갱신)
    - 에러 인라인 Alert + 토스트 더블
    - grep ".delete(" 결과 0. npx eslint OrderModal.tsx 에러 0
  </acceptance_criteria>
  <done>OrderModal 완성 — 웨이터(전체 sellers + branchId 필터)+메뉴 필터+수량+주방 전달(comanda 트리거), ESLint 0.</done>
</task>

<task type="auto">
  <name>Task 3: RestaurantPaymentModal (cuenta + 현금/카드/MP + split + merge + 영수증)</name>
  <read_first>
    - ventago-app/src/views/restaurante/SalonView.tsx (Task 1 — por_cobrar/결제 진입 + saleId)
    - ventago-app/src/views/mercadopago/ 또는 PaymentSummaryModal (Phase 29 MP QR side-panel + processedIntentRef guard 패턴)
    - .claude/skills/sketch-findings-ace-online/references/payment-modal-qr.md (모달 1fr+320px QR side-panel, sandbox borde)
    - 39-CONTEXT.md D-01~D-04 (split=N등분/임의금액, merge=복수 테이블 선택 일회성)
    - 39-SPEC req9/req10
  </read_first>
  <action>
**views/restaurante/components/RestaurantPaymentModal.tsx** — MUI Dialog (sketch payment-modal-qr: 1fr + 320px QR panel):
- 합산 표시: sale items + total (mono font 금액).
- **cuenta(사전 출력)** 버튼 → apiConnector.post(`/restaurant-sale/${saleId}/cuenta`) → 감열 cuenta 출력(DRAFT 유지, req9). 상태 변경 없음.
- **결제 수단**: 현금/카드/MP(QR). 복수 입력 가능(split — sketch 가로 확장 layout).
  - **split**: "N등분" 버튼(자동 균등) + 결제수단별 임의 금액 입력 둘 다(D-02). payments 배열 누적. 합계 = total 검증(클라이언트 1차, 백엔드 최종).
  - 결제 확정 → apiConnector.post(`/restaurant-sale/${saleId}/pay`, { payments }) → DRAFT→PAID + 영수증 출력 + SalonView mutate(테이블 libre).
- **merge**: "여러 테이블 합산" 토글 → por_cobrar 테이블 다중 선택 → apiConnector.post('/restaurant-sale/pay-merge', { saleIds, payments }) (D-03 각 sale 유지·금액 배분). 결제 시점 일회성(D-04 — 영속 그룹 없음).
- **MP QR**: Phase 29 패턴 — QR side-panel + webhook/polling + processedIntentRef double-trigger guard(필수). sandbox borde(골드 2px).
- 에러: 인라인 Alert + 토스트 더블 + (MP 실패 시) refund-failure-ux 패턴.
ESLint 준수. apiConnector.remove(). 한국어 주석.
  </action>
  <verify>
    <automated>cd /Users/marcoskim/Trabajos_Programming/ACE_online_1.0/ventago-app && npx eslint src/views/restaurante/components/RestaurantPaymentModal.tsx 2>&1 | tail -15; echo "LINT_DONE"</automated>
  </verify>
  <acceptance_criteria>
    - RestaurantPaymentModal.tsx 에 cuenta POST(`/restaurant-sale/${...}/cuenta`) + pay POST(`/restaurant-sale/${...}/pay`) + pay-merge POST('/restaurant-sale/pay-merge')
    - split: "N등분" 자동 균등 + 결제수단별 임의 금액 입력 둘 다 존재(D-02), payments 복수 행
    - merge: por_cobrar 테이블 다중 선택 + saleIds 배열 전송
    - MP QR: processedIntentRef double-trigger guard 존재 (Phase 29 패턴)
    - 결제 성공 후 mutate() (테이블 libre 갱신)
    - grep ".delete(" 결과 0. npx eslint 에러 0
  </acceptance_criteria>
  <done>RestaurantPaymentModal 완성 — cuenta/현금·카드·MP/split/merge/영수증, ESLint 0.</done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <name>Task 4: 식당 모드 전체 흐름 + 소매 회귀 0 브라우저 검증 (사용자)</name>
  <action>dev + print-agent 로 분기/주문/comanda/타이밍/cuenta/split/merge/영수증을 검증하고, 소매 매장 sale/통계 회귀 0 을 확인한다.</action>
  <what-built>식당 모드 전체 사용자 흐름 완성: nueva-venta 분기 → SalonView 배치도 → 주문/comanda → 타이밍 → cuenta/결제(split/merge)/영수증. 39-03 print_temp 핸들러 + 39-05 백엔드 소비.</what-built>
  <how-to-verify>
    1. `./dev.sh` + print-agent(`npm run dev:print`) 실행
    2. 식당 매장(useRestaurantMode ON) 로그인 → nueva-venta → SalonView 배치도 표시 확인 (소매 매장은 VcontrolHome — 매장별 혼용 확인)
    3. 테이블 클릭 → 웨이터 선택 → 식당 카테고리 메뉴만 표시 확인 → 상품·수량 → "주방 전달" → ~/Desktop/print-debug-*.png 에 comanda PNG 생성(테이블명/웨이터/품목/수량)
    4. 같은 테이블 2회 주문 → 단일 sale items 누적 확인(DB SELECT)
    5. "음식 나옴"/"소비 완료" 버튼 → served_at/closed_at 기록 확인(DB)
    6. cuenta 버튼 → cuenta PNG 출력 + sale 여전히 DRAFT
    7. 결제: 현금 단일 + split(N등분) → sale_payment_methods 복수 행, DRAFT→PAID, 테이블 libre, 영수증 PNG
    8. merge: 2 테이블 por_cobrar → 합산 결제 → 각 sale PAID(reparent 안 됨, 각자 table_id 유지)
    9. 소매 매장 sale 생성/통계 회귀 0 확인 (기존 ventaVista 정상)
  </how-to-verify>
  <resume-signal>분기/주문/comanda/타이밍/cuenta/split/merge/영수증/소매 회귀0 모두 정상이면 "approved", 문제 시 단계+화면 설명.</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries
| Boundary | Description |
|----------|-------------|
| seller(웨이터) → 식당 sale API | 주문/결제 입력, split 금액 조작 |

## STRIDE Threat Register
| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-39-16 | Tampering | split 금액 입력 | mitigate | 클라이언트 합계=total 1차 검증 + 백엔드(39-05) 최종 검증(integer 정확 비교) |
| T-39-17 | Info | MP QR 중복 트리거 | mitigate | processedIntentRef double-trigger guard (Phase 29 패턴 재사용) |
| T-39-18 | Elevation | SalonView 편집 진입 | mitigate | SalonView 에 편집 버튼 미배치 (req5) — 편집은 39-06 configuración 전용 |
</threat_model>

<verification>
- npx eslint 5파일 에러 0
- dev 브라우저+print-agent: 분기/주문/comanda/타이밍/cuenta/split/merge/영수증 manual
- DB: 단일 DRAFT 누적 / sale_payment_methods 복수 / 소매 회귀 0
</verification>

<success_criteria>
- 식당 매장 SalonView 분기 + 배치도 렌더(상태 색상)
- 주문→comanda 출력, 타이밍 마킹, cuenta/영수증, split/merge 결제
- 메뉴 products+식당 카테고리 필터, 매상 통계 통합, 소매 회귀 0
</success_criteria>

<output>
완료 후 `.planning/phases/39-modo-restaurante-pos-mesas/39-07-SUMMARY.md` 작성.
</output>
