# SPEC: 제품별 라우팅 템플릿 (A: Cut Ticket 저장 + B: 제품 편집 + 자동 불러오기)

생성일: 2026-06-29

## 목표
제품(products)에 기본 공정 경로(routing_template)를 저장하고, Cut Ticket 생성 시
자동으로 RutaConfigDialog 초기값으로 불러온다. 저장 진입점은 두 곳(A: Cut Ticket
다이얼로그 체크박스 / B: 제품 편집 섹션) — 둘 다 같은 컬럼을 읽고 써서 언제든 양쪽에서 변경 가능.

## 배경 및 컨텍스트
- 단일 진실 공급원: products.routing_template (jsonb). A/B 가 같은 데이터 공유.
- 템플릿 형식 = vendorAssignments 와 동일: [{ etapaId, vendorId, order }]
  (RoutingStep 의 etapaName/vendorName 은 저장 안 함 — 조회 시 조인/빌드. 이름 변경 대응.)
- 라우팅 편집 UI 는 이미 RutaConfigDialog 에 존재 → 재사용.
  파일: ventago-app/src/views/talleres/cut-ticket/components/RutaConfigDialog.tsx
- Cut Ticket 생성: api lote.service.ts generateCutTicket → buildRoutingPath(vendorAssignments).
- 자동 불러오기: RutaConfigDialog initialAssignments prop 이 이미 있음(편집 모드용).
  create 모드에서 제품 템플릿을 initialAssignments 로 주입하면 자동 채움.
- 제품 모델: api-ventago/src/app/products/products.model.ts (jsonb 컬럼 imageUrls 선례 있음).
- 제품 편집 폼: ventago-app/src/views/products/list/components/BasicDataCard.tsx (복잡 → 별도 섹션/다이얼로그).

## 기술 스택
- 백엔드: NestJS + Sequelize. DB PostgreSQL (PG10 운영/PG15·18 로컬). 마이그레이션 SQL.
- 프론트: Next.js + MUI. apiConnector. SWR.
- ESLint: newline-before-return, lines-around-comment 빌드 차단.

## 태스크 목록
- [ ] TASK-1: 마이그레이션 — products 에 routing_template jsonb 추가 (NULL 허용). 양 DB.
       파일: api-ventago/migrations/add-products-routing-template.sql
- [ ] TASK-2: (백엔드 모델) Product 에 routingTemplate 컬럼 추가. 파일: products.model.ts
- [ ] TASK-3: (백엔드 API) 제품 routing_template GET/PUT 엔드포인트
       (B 진입점 + 조회용). 기존 products 컨트롤러/서비스 확장. 파일: products.*.ts
- [ ] TASK-4: (백엔드) generateCutTicket — vendorAssignments 미전달 시 제품 템플릿 사용,
       그리고 'saveAsTemplate' 플래그 받으면 제품에 템플릿 저장(A). 파일: lote.service.ts/controller.ts
- [ ] TASK-5: (백엔드) Cut Ticket 미발급 조회 응답에 제품 템플릿 포함(프론트 자동채움용)
       또는 별도 GET /products/:id/routing-template 로 프론트가 직접 조회. (더 단순한 후자 채택)
- [ ] TASK-6: (프론트 A) RutaConfigDialog 에 "제품 기본 경로로 저장" 체크박스 +
       create 모드 진입 시 제품 템플릿을 initialAssignments 로 자동 로드.
       파일: RutaConfigDialog.tsx, CutTicketEmptyState.tsx
- [ ] TASK-7: (프론트 B) 제품 편집에서 "Ruta de producción" 편집 진입 — RutaConfigDialog
       를 template 모드로 재사용(또는 경량 래퍼). 파일: BasicDataCard.tsx (+ 신규 RoutingTemplateSection)
- [ ] TASK-8: ESLint + tsc 검증 (front/api)

## 완료 기준
- products.routing_template 저장/조회 동작 (양 진입점 동일 데이터)
- Cut Ticket 생성 시 제품 템플릿이 있으면 자동 채움, 없으면 기존 etapa.order 기본
- A 에서 저장 체크 시 제품 템플릿 갱신 / B 에서 편집 시 동일 컬럼 갱신
- ESLint 0, 타입 0, pool 누수 없음(콜백형 tx / pool.query)

## 금지사항 / 주의사항
- 템플릿엔 etapaName/vendorName 저장 금지(이름 변경 대응 — id 만). 표시용 이름은 조회 시 빌드.
- 비활성 etapa/없는 vendor 가 템플릿에 있어도 buildRoutingPath 가 자동 필터(기존 로직 활용).
- 운영 PG10 마이그레이션 호환(jsonb 는 PG10 지원).
- 한국어 주석, 영어 식별자, 스페인어 UI.
- RutaConfigDialog 재사용 시 기존 create/edit 모드 동작 깨지 않게 — 'template' 모드 추가 또는 분기.
