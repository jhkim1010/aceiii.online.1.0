# Phase 15: Materia Prima Control — 원자재 관리 시스템

## Goal
의류 소형 생산업자를 위한 원자재(Materia Prima) 입고·사용·잔고 관리 + 공급자 대금 관리 시스템.
기존 `mes_materials` 모델을 확장하고 새 앱("Materia Prima")으로 사이드바에 독립 메뉴 추가.

## Depends on
- Phase 14 (Permisos Control — 권한 시스템 활용)
- 기존 production 모듈 (mes_materials, mes_bom, mes_bom_items)

## Requirements
- MPRIMA-01: 원자재 카테고리 관리 (기본 5종 + 커스텀)
- MPRIMA-02: 원자재 CRUD + 재고 추적 (입고/출고/잔고)
- MPRIMA-03: 공급자(Proveedor) 관리 + 대금 장부
- MPRIMA-04: 입출고 이동 내역 (Movimientos)
- MPRIMA-05: 알림/리오더 포인트 (최소재고 부족 시 알림)
- MPRIMA-06: 원가 계산 연동 (BOM 기반)
- MPRIMA-07: 대시보드 (카드형 KPI + 카테고리 분포 + 알림)

## Success Criteria
1. 사이드바에 "Materia Prima" 앱 그룹 표시 (권한 있는 사용자만)
2. Dashboard에서 KPI(총 원자재, 재고부족, 재고총액, 미지급잔액) 한눈에 파악
3. 원자재 등록 시 카테고리(tela/boton/cierre/hilo/accesorio + 커스텀) 선택 가능
4. 원단(tela)은 색상·원산지·품질 추가 속성 관리
5. 입고 시 공급자 연결 + 대금 처리(외상/즉시결제/부분결제) 선택
6. 출고 시 작업지시(WorkOrder) 또는 참조번호 연결
7. 공급자별 미지급 잔액 + 결제 이력 조회
8. 최소재고 이하 시 알림 배지 표시
9. BOM과 연동하여 제품별 원자재 소요량 기반 원가 계산
10. 허가된 사용자만 접근 가능 (Phase 14 권한 시스템 활용)

## DB Schema Changes

### 새 테이블
- `mes_material_categories` — 원자재 카테고리 (기본 seed + 커스텀)
- `mes_material_movements` — 입출고 이동 내역
- `mes_material_supplier_payments` — 공급자 대금 결제 내역

### 기존 테이블 확장
- `mes_materials` 컬럼 추가:
  - `category_id` (FK → mes_material_categories)
  - `supplier_id` (FK → suppliers)
  - `current_stock` (DECIMAL 10,3)
  - `min_stock` (DECIMAL 10,3)
  - `color` (STRING, nullable)
  - `origin` (STRING, nullable)
  - `quality` (STRING, nullable)
  - `image_url` (STRING, nullable)
  - `last_entry_date` (DATE, nullable)

## UI Structure (5 탭)

### 1. Dashboard (/materia-prima/dashboard)
- KPI 4카드: 총 원자재 수, 재고부족 수, 재고총액, 공급자 미지급잔액
- 알림 섹션: 재고 부족/소진 원자재 리스트
- 최근 입출고 내역 (최근 5건)
- 카테고리별 재고 분포
- 공급자별 채무 요약

### 2. Inventario (/materia-prima/inventario)
- 카테고리 필터 칩 (Todos/Tela/Botón/Cierre/Hilo/Accesorio)
- 검색바 + 신규 등록 버튼
- 카드 그리드 (재고바, 상태 배지, 단가, 공급자)

### 3. Proveedores (/materia-prima/proveedores)
- 공급자 카드 (연락처, 평점, 미지급잔액, 총결제액)
- "Registrar pago" 빠른 결제 버튼
- 신규 공급자 등록

### 4. Movimientos (/materia-prima/movimientos)
- 입고(Entrada) / 출고(Salida) 버튼
- 이동 내역 테이블 (날짜, 유형, 재료, 수량, 참조, 금액)

### 5. Pagos (/materia-prima/pagos)
- 대금 KPI (총 미지급, 이번 달 결제, 다음 만기)
- 결제 이력 테이블 (날짜, 공급자, 금액, 방법, 참조, 메모)

## Plans

### Plan 15-01: DB 스키마 + 백엔드 모델 + 시더 (App/Module/Function)
- mes_material_categories 모델 + 기본 seed (5종)
- mes_materials 모델 확장 (카테고리, 공급자, 재고, 속성)
- mes_material_movements 모델
- mes_material_supplier_payments 모델
- App "Materia Prima" seed + Module seed (5개) + Function seed
- Production 모듈 app.module.ts import

### Plan 15-02: 백엔드 서비스 + API 엔드포인트
- Material 확장 CRUD + 재고 관리 API
- Category CRUD API
- Movement 입고/출고 API (재고 자동 갱신)
- Supplier Payment CRUD API
- Dashboard 통계 API
- 알림 API (최소재고 이하 원자재 목록)

### Plan 15-03: 프론트엔드 — Dashboard + Inventario 화면
- /materia-prima/dashboard 페이지
- /materia-prima/inventario 페이지
- 카드 컴포넌트, KPI 카드, 카테고리 필터

### Plan 15-04: 프론트엔드 — Proveedores + Movimientos + Pagos 화면
- /materia-prima/proveedores 페이지
- /materia-prima/movimientos 페이지
- /materia-prima/pagos 페이지
- 입고 모달, 결제 등록 모달
