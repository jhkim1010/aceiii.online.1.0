# Phase 69 Plan 06 — `store_id` 미보유 모델 전수 감사 (R4/WR-01)

**재현 명령:**
```bash
cd api-ventago && grep -rl "@Table" src | while read -r f; do grep -q "storeId" "$f" || echo "$f"; done | wc -l
```
결과: **63** (2026-08-01 기준). 아래 D+G+X+미결 합계는 이 숫자와 일치해야 한다.

각 행의 "근거"는 실제 모델 소스 파일:라인이다(추정 금지 — 미결 절 제외 D/G/X 표에 "아마도/추정" 0회).

---

## 집계

| 버킷 | 개수 |
|---|---|
| D — 파생 대상 (신규 등록) | 37 |
| D — 이미 등록됨(Phase 68, 이 플랜에서 유지/확장) | 3 (ProductBranch·Stocks·Price) |
| G — 전 매장 공용 | 14 |
| X — 요청 경로 밖 | 3 |
| 미결 | 6 |
| **합계** | **63** |

`DERIVED_SCOPE` 최종 항목 수 = D 전체(신규 37 + 기존 3) = **40**.

---

## D — 파생 대상 (부모 경유 격리 등록)

association alias 는 전부 모델 파일의 `@BelongsTo` **프로퍼티명**을 그대로 썼다(클래스명과
다른 경우가 다수 발견됨 — 예: `OnlineOrderItem.order`, `SharedFolderRoleAccess.folder`).
"부모가 store_id 보유?"가 "아니오"인 행은 `through` 2단계로 표기했다.

| modelName | tableName(대표) | 부모 association | 부모 modelName | 부모 store_id? | 근거 파일:라인 | 비고 |
|---|---|---|---|---|---|---|
| BoxOperation | box_operations | cashRegister | CashRegister | 예 | box-operation.model.ts:15-20 | user/terminal FK 도 있으나 cashRegister 만으로 충분해 단일 부모 채택 |
| Boxes | boxes | branch | Branch | 예 | boxes.model.ts:23-27 | userId 는 nullable, 부모로 미채택 |
| BranchPriceTypeDisabled | branch_price_types_disabled | branch + priceType | Branch, PriceType | 예/예 | branchPriceTypeDisabled.model.ts:18-29 | 복합 PK(branch_id,price_type_id) — ProductBranch 와 동형 공격면(한쪽만 자기매장으로 바꿔치기) → 다중 부모 채택 |
| CajaFuerteOperation | caja_fuerte_operations | cajaFuerte | CajaFuerte | 예 | caja-fuerte-operation.model.ts:23-27 | user/cashRegister FK 도 있으나 cajaFuerte 로 충분 |
| CampaignRecipient | campaign_recipients | campaign | Campaign | 예 | campaign-recipient.model.ts:41-45 | clientId nullable, 부모 미채택 |
| ExpenseCheque | expense_cheques | expense + cheque | Expenses, Cheque | 예/예 | expense-cheque.model.ts:15-27 | 두 FK 모두 allowNull:false — 서로 다른 매장의 gasto·cheque 를 잘못 링크하는 공격면 방지 위해 다중 부모 |
| ClientAccessAudit | client_access_audits | user | Users | 예(예외적으로 NULL 1행=superadmin) | client-access-audit.model.ts:46-48,110-111 | superadmin 이 자신의 owner-group 위반을 남긴 행은 storeId=null user 를 가리킬 수 있음 — 이 표는 superadmin 전용 감사 대시보드라 실사용 경로에서 영향 없음(아래 캐비어트 참조) |
| PaymentMethodsDiscount | payment_methods_discounts | discount | Discounts | 예 | payment-methods-discount.model.ts:24-25 | paymentMethod 쪽은 `payment_methods` 가 GLOBAL_ROW_TABLES 멤버(운영 NULL 13행, tenant-scope.registry.ts:21) 라 필수 INNER JOIN 시 전역 결제수단에 걸린 할인 행이 사라짐 → 그 부모는 제외 |
| ProductDiscount | product_discounts | product + discount | Product, Discounts | 예/예 | product-discount.model.ts:20-24 | 두 FK 모두 필수 — 다중 부모 |
| DiscountReason | discount_reasons | sale | Sale | 예 | discount-reason-model.ts:12-16 | |
| SubcategoryDiscount | subcategory_discounts | subcategory + discount | Subcategory, Discounts | 예/예 | subcategory-discount.model.ts:22-26 | 두 FK 모두 필수 — 다중 부모 |
| MpMovement | mp_movements | mpWallet | MpWallet | 예 | mp-movement.model.ts:17-21 | saleId 는 nullable |
| MpRefundAttempt | mp_refund_attempts | sale | Sale | 예 | mp-refund-attempt.model.ts:15-19 | |
| MpRefund | mp_refunds | sale | Sale | 예 | mp-refund.model.ts:15-19 | |
| MpTransfer | mp_transfers | mpWallet | MpWallet | 예 | mp-transfer.model.ts:17-21 | targetBoxId/userId 는 `@ForeignKey` 만 있고 `@BelongsTo` 미선언 — include 불가라 부모로 못 씀 |
| MobileSession | mobile_sessions | user | Users | 예(위 caveat 동일) | mobile-session.model.ts:43-48 | |
| Movements | movements | user | Users | 예(위 caveat 동일) | movements.model.ts:23-28 | box(Boxes) 경유 2단계도 가능하나 user 1단계로 충분 |
| OnlineOrderItem | online_order_items | order | OnlineOrder | 예 | online-order-item.model.ts:18-23 | alias 가 `order`(클래스명 아님) — 실제 프로퍼티명 확인 필수 사례 |
| OnlineReturn | online_returns | order | OnlineOrder | 예 | online-return.model.ts:34-39 | 위와 동일 |
| UserBranch | user_branches | user + branch | Users, Branch | 예(user 는 위 caveat)/예 | user-branch.model.ts:41-49,84-87 | grantedBy(Users)/mobileTerminalId(Terminal) 는 부모 미채택 |
| UserPermissionCache | user_permission_cache | user + branch | Users, Branch | 예(user 는 위 caveat)/예 | user-permission-cache.model.ts:44-51,66-69 | |
| BranchAgent | branch_agents | branch | Branch | 예 | branch-agent.model.ts:16-21 | |
| BranchPrinterConfig | branch_printer_configs | branch | Branch | 예 | branch-printer-config.model.ts:16-21 | |
| BomItem | mes_bom_items | bom | Bom | 예 | bom-item.model.ts:22-27 | material/subProduct 는 nullable, 부모 미채택 |
| ProductionResult | mes_production_results | workOrder | WorkOrder | 예 | production-result.model.ts:21-26 | PLAN 이 "workOrder 또는 bom" 으로 둘 다 후보였으나 실제 모델엔 bomId 컬럼 자체가 없음 — workOrder 로 확정 |
| ProductBranch | ProductBranch | product + branch | Product, Branch | 예/예 | products-branch.model.ts:20-32 | **Phase 68 기존 등록을 이 플랜에서 dual-parent 로 확장(R2/CR-02 실증 사례)** |
| ProductSubcategories | product_subcategories | subcategory | Subcategory | 예 | products-categories.model.ts:13-21 | PLAN 은 "ProductsCategories(product)" 로 표기했으나 실제 모델엔 `product` 방향 `@BelongsTo` 가 선언돼 있지 않다(FK 컬럼만 존재) — 실사용 가능한 유일한 association 은 `subcategory` |
| SaleDiscount | sale_discounts | sale | Sale | 예 | sale-discount.model.ts:12-22 | |
| SaleItem | sale_items | sale | Sale | 예 | sales-item.model.ts:14-18 | product 쪽도 있으나 sale 로 충분 |
| SalePaymentMethod | sale_payment_methods | sale | Sale | 예 | sales-payment-method.model.ts:14-29 | paymentMethod 쪽은 PaymentMethod 가 GLOBAL_ROW_TABLES 멤버라 제외 |
| SaleRecharge | sale_recharges | sale | Sale | 예 | sale-recharge.model.ts:12-22 | |
| SharedFolderRoleAccess | shared_folder_role_access | folder | SharedFolder | 예 | shared-folder-role-access.model.ts:15-29 | alias 가 `folder`(클래스명 SharedFolder 아님). role 쪽은 Role 이 GLOBAL_ROW_TABLES 멤버(전역 시스템 역할, storeId nullable) 라 제외 |
| Stocks | stocks | productBranch → product | ProductBranch → Product | 아니오 → 예 | stocks.model.ts:50-52,81 | **Phase 68 기존, 이 플랜에서 무변경** |
| Price | prices | product | Product | 예 | prices.model.ts:13-17 | **Phase 68 기존, 이 플랜에서 무변경** |
| EnvioMaterial | talleres_envio_materiales | envio | Envio | 예 | envio-material.model.ts:22-27 | material 은 nullable 아니지만 이미 envio 로 충분해 단일 부모 |
| SubconDefect | talleres_defects | subconDelivery → subconOrder | SubconDelivery → SubconOrder | 아니오 → 예 | subcon-defect.model.ts:26-31, subcon-delivery.model.ts:22-27 | 2단계 through |
| SubconDelivery | talleres_deliveries | subconOrder | SubconOrder | 예 | subcon-delivery.model.ts:22-27 | |
| SubconMaterialIssue | talleres_material_issues | subconOrder | SubconOrder | 예 | subcon-material-issue.model.ts:22-27 | material/product 는 nullable |
| VendorEtapa | talleres_vendor_etapas | vendor | Vendor | 예 | vendor-etapa.model.ts:26-31 | etapa 쪽도 store_id 보유(Etapa) 이나 vendor 로 충분(PLAN 표기와 일치) |
| UserFunctionAction | user_function_actions | userFunction | UserFunction | 예(NOT NULL — `user_functions` 는 GLOBAL_ROW_TABLES 미포함) | user-function-action.model.ts:31-44, user-function.model.ts:32-33 | RoleFunctionAction 과 대칭 구조이나 UserFunction.storeId 는 nullable 아님 — 안전 |

**"user" 부모 공통 캐비어트:** `users` 는 `GLOBAL_ROW_TABLES` 멤버(superadmin 1행만 storeId NULL,
tenant-scope.registry.ts:20-23). 이론상 `ClientAccessAudit`/`MobileSession`/`Movements`/`UserBranch`/
`UserPermissionCache` 가 superadmin 소유 `Users` 행을 가리키는 극히 드문 케이스에서 `enforce` 전환 후
해당 행이 걸러질 수 있다. 그러나 superadmin 요청 자체는 `allowedStores()` 가 항상 `null` 을 반환해
훅이 no-op 이므로(tenant-hooks.ts:60-69) **일반 매장 사용자가 이 부모 체인을 타는 실사용 경로에서
superadmin 소유 행을 참조하는 사례가 실질적으로 없다.** 회귀 위험 낮음으로 accept, 69-07 승격 시
운영 로그로 실측 재확인 권장.

---

## G — 전 매장 공용

| modelName | 사유 |
|---|---|
| Apps | 시스템 앱 카탈로그(apps.model.ts) — FK/연관관계 없음, 매장 개념 자체가 없다 |
| Modules | 부모가 Apps(G) — 전역 모듈 카탈로그(modules.model.ts:46-50) |
| Functions | 부모가 Modules(G) — 권한 시스템의 전역 기능 정의(functions.model.ts:63-67) |
| Nation | 국가 마스터 — FK/연관관계 없음(nation.model.ts) |
| Province | 부모가 Nation(G) — 지역 마스터(province.model.ts:25-29) |
| CanonicalCategory | reseller 스키마의 표준 카테고리 — 매장 개념 없음, self-ref parentId 뿐(canonical-category.model.ts) |
| Reseller | 설계상 매장 소속 없음 — "여러 매장을 크로스 브라우징" 독립 주체, 별도 JWT(reseller.model.ts, schema='reseller') |
| ResellerDocument | 부모가 Reseller(G), schema='reseller' 로 메인 테넌트 스키마 밖(reseller-document.model.ts) |
| Revendedor | 설계상 매장 소속 없음(revendedor.model.ts:6-23 주석 — "재판매자는 매장 소속 없음, 여러 매장의 상품을 크로스 브라우징") — 별도 revendedor-jwt 전략 |
| RevendedorCategory | 부모가 Revendedor(G)/GlobalCategory(G) — 크로스매장 브릿지(revendedor-categories.model.ts:50-64) |
| GlobalCategory | 이름 그대로 전 매장 공용 참조 카탈로그. createdByStoreId 는 생성 감사용일 뿐 접근 스코프가 아님(global-categories.model.ts:83-92) |
| GlobalClient | 위와 동일한 전역 카탈로그 패턴(global-clients.model.ts:145-188) |
| GlobalSubcategory | 위와 동일(global-subcategories.model.ts:70-93) |
| SubscriptionConfig | 플랫폼 구독요금제 상수 — 단일 설정 테이블, FK 없음(subscription-config.model.ts) |

---

## X — 요청 경로 밖

| modelName | 사유 |
|---|---|
| PendingRegistration | 매장 승인 전 임시 가입폼 데이터 — 관리자 승인/시스템 워커 전용 경로, `@ForeignKey`/`@BelongsTo` 연관관계 자체가 없음(pending-registration.model.ts) |
| ReferralCredit | 승인 시 시스템이 생성하는 추천 크레딧 원장 — 매장 스코프 요청 경로 아님, 연관관계 없음(referral-credit.model.ts) |
| VerificationCode | OTP 코드 — onboarding 시스템 전용, 연관관계 없음(verification-code.model.ts) |

---

## 미결

| modelName | 이유 |
|---|---|
| QrPrintLog | `@ForeignKey`/`@BelongsTo` 자체를 선언하지 않음 — 파일 주석에 "조인은 서비스 레벨에서 in-memory 로 수행"이라 명시(qr-print-log.model.ts:6). `DerivedScopeRule.as` 는 Sequelize include 에 쓸 association 이 필요한데 이 모델엔 그게 없어 이 플랜의 방식으로 등록 불가 — 모델에 `@BelongsTo(() => Branch)` 를 추가하는 것 자체가 스키마 변경은 아니지만 모델 구조 변경이라 이 플랜 범위(레지스트리/훅) 밖으로 판단, 별도 후속 작업 필요 |
| UserRole | `userId` FK 컬럼은 있으나 `@BelongsTo(() => Users)` 가 선언돼 있지 않다(user-role.model.ts 전체 확인, Role 방향만 `@BelongsTo(() => Role,'roleId')` 존재). 유일하게 쓸 수 있는 `role` 방향도 `Role.storeId` 가 nullable(전역 시스템 역할, role.model.ts:26)이라 `buildDerivedInclude` 가 하드코딩한 `allowGlobalRows:false`(tenant-hooks.ts:190-194) 와 충돌 — enforce 전환 시 전역 역할이 배정된 사용자의 UserRole 행이 통째로 사라진다. 두 가지 독립적 이유로 이 플랜의 규칙 엔진으로는 안전하게 등록 불가 |
| RoleFunctionAction | 유일한 부모 RoleFunction 이 `role_functions` 테이블(GLOBAL_ROW_TABLES 멤버, 운영 NULL 24행 실측 — tenant-scope.registry.ts:21)이라 위 UserRole 과 동일한 `allowGlobalRows` 충돌. 전역 권한 프리셋에 연결된 액션 행이 enforce 시 사라짐 |
| PaymentMethodsOption | 유일한 부모 PaymentMethod 가 `payment_methods` 테이블(GLOBAL_ROW_TABLES 멤버, 운영 NULL 13행 실측 — tenant-scope.registry.ts:20-21)이라 동일 충돌. 대체 부모 없음(payment-methods-option.model.ts 전체에 다른 FK 없음) |
| SubconSettlement | `subconOrderId`/`vendorId` 둘 다 nullable 이고 상호배타(OR) 관계 — 모델 주석이 명시("Wave 7: nullable 로 완화(vendor 기반 정산은 subconOrderId 없음)", subcon-settlement.model.ts:49). 이 플랜의 규칙 엔진은 **AND-of-필수-부모**(ProductBranch 형)와 **단일 through 2단계**만 지원하며 "둘 중 하나"(OR) 는 표현할 방법이 없다 — 한쪽을 필수로 고르면 다른 한쪽만 채워진 정상 행이 enforce 시 사라진다 |
| SubconPayment | 유일한 부모 SubconSettlement 자체가 미결이라 2단계 through 체인을 구성할 수 없음 |

**미결 처리 방침:** 이 6개는 `DERIVED_SCOPE` 에 등록하지 않는다(observe 로그도 없음 — 기존과
동일하게 여전히 사각지대). 69-07 승격 전에 반드시 재검토해야 한다:
- `QrPrintLog` — 모델에 `@BelongsTo(() => Branch)` 추가(스키마 변경 아님, 모델 코드 변경) 후 재분류
- `UserRole`/`RoleFunctionAction`/`PaymentMethodsOption` — `DerivedScopeRule` 에 `allowGlobalRows` 필드를
  추가해 `buildDerivedInclude` 가 부모의 글로벌 행을 union 하도록 레지스트리 엔진 자체를 보강해야
  안전하게 등록 가능(현재 하드코딩된 `allowGlobalRows:false` 가 근본 원인)
- `SubconSettlement`/`SubconPayment` — OR-of-parents 를 표현하려면 `DerivedScopeRule` 에 배타적
  다중 후보(`anyOf`) 개념이 필요하거나, DB 레벨에서 `subcon_settlements.store_id` 파생 컬럼을 두는
  대안을 검토(단, tenant-scope.registry.ts:70-75 의 "컬럼 추가는 진실의 원천을 흐린다" 원칙과 상충 —
  트레이드오프 논의 필요)

---

## `TENANT_DERIVED_MODE=enforce` 승격(69-07) 전 필수 확인 사항 요약

1. 위 미결 6개는 여전히 무방비 — enforce 로 막히지 않는다(observe 로그도 없다).
2. 아래 D 40개는 observe 모드에서 이 플랜 배포 후 처음으로 로그가 남기 시작한다.
   `logThrottled` 키 형태: `${modelName}:derived:${callerHint()}` (tenant-hooks.ts:268-269).
   69-07 은 배포 후 최소 1영업일 이상 이 로그를 수집해 실제로 걸리는 호출부 목록을 확보해야 한다.
3. `user`/`Role`/`PaymentMethod`/`RoleFunction` 계열 글로벌 행 caveat(위 참조)은 enforce 전환 직후
   운영 로그에서 "예상 밖 필터링"이 없는지 별도로 확인 대상이다.
