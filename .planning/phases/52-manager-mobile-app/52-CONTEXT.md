# Phase 52 — Store Manager Mobile App (핸드폰·태블릿) (CONTEXT)

> **유형**: 신규 기능 — Flutter 모바일/태블릿 앱 (매장 *관리자/오너* 용)
> **선행**: Phase 33 권한(role: store_owner/admin/branch_manager), 대시보드/리포트 API, Phase 37 Flutter 인프라
> **구분 주의**: **Phase 37(Mobile Sales Shell)은 *판매자(vendedor/revendedor)* 용 판매 앱**. 본 Phase 52 는 *관리자(오너·지점장)* 용 **운영 관제/관리** 앱 — 청중·목적·UX 가 다르다.
> **작성일**: 2026-06-29
> **번호**: 51=Public Storefront 다음 → Manager App = **52**.

---

## 1. 왜 이 phase 인가

매장 오너·지점장이 **현장에 없어도 핸드폰/태블릿으로 매장을 관제·관리**한다: 실시간 매출·캐시 현황, 지점 비교, 재고/저재고 경보, 환불·할인·비용 *승인*, 온라인 주문/배송 모니터링, 알림. 데스크탑 POS 앞에 앉지 않고도 의사결정·승인이 가능해야 한다.

- Phase 37 은 "파는 사람"의 앱(BranchScope 판매). 본 phase 는 "관리하는 사람"의 앱(MultiBranch 관제·승인). 같은 모바일이지만 **다른 제품**.

## 2. 청중 & 스코프

- **store_owner / admin**: 매장 전체(N개 지점) 통합 가시성.
- **branch_manager**: 자기 지점 한정.
- 백엔드가 JWT claim 의 role/branch 로 스코프 강제(클라이언트 파라미터 조작 차단) — Phase 37 의 scope 강제 패턴 재사용.

## 3. 핵심 기능 영역 (후보)

1. **대시보드**: 오늘/기간 매출, 캐시(caja) 잔액, 지점별 비교, 결제수단 분해 — 기존 `dashboards/*`·`reports/*` API 재사용.
2. **재고**: 상품/지점 재고 조회, 저재고 경보, 빠른 조정, 가격 변경(권한 한정).
3. **캐시·금고 관제**: caja/control-de-caja 상태, 불일치 경보, 마감 확인.
4. **승인 워크플로우**: 환불·할인·비용·가격변경 승인(모바일 푸시 → 승인/반려).
5. **온라인 주문/배송**: online_orders despacho 보드 모니터링(Phase 42/27 연계).
6. **알림(FCM)**: 저재고, 대형 환불, 캐시 불일치, 신규 온라인 주문, 세션 이상.
7. **스태프/세션**: 누가 로그인했는지, 디바이스/세션 가시성(Phase 세션보안 연계).

## 4. 기술 — Flutter 인프라 재사용

- 기존 Flutter 앱 `talleres-vendor-app/`(Phase 17 Portal de Talleres) + Phase 37 패턴: **Dio + Riverpod + secure storage + FCM + JWT auth + 매장 탭**. (사용자 선호: null safety, Riverpod, dart 스타일가이드)
- 세션: 데스크탑 POS `active_sessions` 와 분리된 **`mobile_sessions`**(Phase 37) 재사용 — 오너가 데스크탑+모바일 동시 운영.
- 백엔드: 가능한 기존 엔드포인트 재사용, 모바일 전용은 `/admin-mobile/*`(또는 `/mobile/*` 확장)에서 role/scope 강제. **PostgreSQL pool 낭비 금지**(프로젝트 규약) — 모바일 폴링은 캐시/적정 주기.

## 5. 아키텍처 결정 (열림 — Wave 52-00 에서 확정)

- **별도 앱 vs Phase 37 3번째 모드?**
  - 별도 앱(권장 검토): 청중·UX(태블릿 master-detail 관제) 다름 → 별도 Flutter 워크스페이스, **공유 인프라 패키지** 재사용.
  - 또는 동일 앱의 `manager` 모드(Phase 37 듀얼모드 철학 확장).
- **태블릿 우선 레이아웃**: 관리자는 태블릿 사용 빈도 ↑ → master-detail/대시보드 그리드. 핸드폰은 카드 포커스.

## 6. 주의 / 리스크

- 권한 경계(IDOR): 지점장이 타 지점 데이터 접근 불가 — 서버 스코프 강제.
- 승인 액션은 **돈/재고 상태 변경** → 멱등·감사로그 필수.
- 모바일 폴링이 pool 잠식하지 않도록 주기·캐시 관리.
- Phase 37 과 코드 중복 최소화(공유 인프라/디자인 시스템).
