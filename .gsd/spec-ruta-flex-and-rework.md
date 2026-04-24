# SPEC: Ruta flexibilización (DnD) + Rework (재작업 플로우) — 범위 C

생성일: 2026-04-23
이 세션: 단계 1 전체 + 단계 2 백엔드
다음 세션: 단계 2 프론트 UI

## 목표

중소 봉제 공장의 현실적 유연성을 반영하는 두 가지 개선을 연속 구현한다.

**단계 1 — Ruta 유연성**: cut_date 후에도 routing의 **미시작(FREE) 단계는 드래그로 순서 변경**, **진행 중(IN_PROGRESS) 단계는 vendor 재배정만** 허용, **완료(COMPLETED) 단계는 잠금**. 중간에 **새 etapa 추가**도 가능.

**단계 2 — Rework 플로우**: 수령(Recepción) 시 불량 발견되면 해당 수량을 **원래 routing의 이전 공정으로 되돌려 재작업**할 수 있게 한다. routing_path 자체는 건드리지 않고 `talleres_rework_orders` 테이블 + 새 Envío(with `rework_order_id`)로 이력화한다.

## 배경 및 현재 구조

- `routing_path` = 순차 JSONB 배열 `[{order, etapaId, vendorId, vendorName}]`
- `talleres_envios` 이미 존재: `{etapaId, vendorId, quantity, pendingQuantity, status: PENDING|PARTIAL|COMPLETED|CANCELLED, sourceRecepcionId}`
- `talleres_recepciones`에 `defectQuantity` 있음 (Wave 6 QC 구조)
- `defect-codes` 모듈 이미 있음
- 프론트 `@dnd-kit/core@6.3.1`, `@dnd-kit/sortable@8.0.0` 이미 설치됨

## 단계 1 — 기술적 결정

### 1-1. Routing 단계 상태 판정

각 etapa의 "상태"는 envios를 집계해서 계산:
- **COMPLETED**: 해당 etapaId의 모든 envios가 COMPLETED 상태
- **IN_PROGRESS**: 하나라도 PENDING/PARTIAL 상태
- **FREE**: envios가 아예 없음 (아직 발송 안 됨)

백엔드에 `getRoutingStatus(loteId, storeId)` helper 신설 → `[{etapaId, status: 'COMPLETED'|'IN_PROGRESS'|'FREE'}]` 반환 → 프론트가 DnD 잠금 규칙 판단에 사용.

### 1-2. 서버 측 가드 규칙

`updateRoutingPath` 재작성:
- COMPLETED etapa는 기존 routing에서 **제거 금지** + **순서 변경 금지** + **vendorId 변경 금지**
- IN_PROGRESS etapa는 **순서 변경 금지** + **제거 금지**, **vendorId만 변경 허용** (단, 진행 중 envio가 해당 vendor면 경고)
- FREE etapa는 자유 (순서 변경/제거/vendor 변경)
- 새 etapa 삽입 가능 (status는 자동으로 FREE)
- cut_date 잠금은 해제 (이제 상태별 잠금으로 대체)

### 1-3. Order 계산 방식

현재 `buildRoutingPath`는 `etapa.order ASC`로 정렬. 사용자가 DnD로 순서 바꿨다면 그걸 존중해야 함 → assignments에 `order: 1,2,3,...` 포함해서 전달하고, service는 **입력된 order를 그대로 사용**.

변경 대상: `buildRoutingPath(storeId, assignments: Array<{etapaId, vendorId, order?}>, tx)`
- assignments에 order가 있으면 그 순서로 정렬
- 없으면 기존처럼 etapa.order ASC로 fallback

## 단계 2 — Rework 데이터 모델

### 2-1. 새 테이블 `talleres_rework_orders`

```sql
CREATE TABLE talleres_rework_orders (
  id SERIAL PRIMARY KEY,
  store_id INTEGER NOT NULL REFERENCES stores(id),
  lote_id INTEGER NOT NULL REFERENCES talleres_lotes(id),
  cut_ticket_number VARCHAR(20),
  source_envio_id INTEGER NOT NULL REFERENCES talleres_envios(id),
  source_recepcion_id INTEGER REFERENCES talleres_recepciones(id),
  target_etapa_id INTEGER NOT NULL REFERENCES talleres_etapas(id),
  target_vendor_id INTEGER REFERENCES talleres_vendors(id),  -- nullable = In-house
  quantity INTEGER NOT NULL CHECK (quantity > 0),
  defect_code_id INTEGER REFERENCES talleres_defect_codes(id),
  reason TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'PENDING',  -- PENDING|IN_PROGRESS|COMPLETED|CANCELLED
  resulting_envio_id INTEGER REFERENCES talleres_envios(id),  -- 이 rework로 생성된 새 Envio
  created_by INTEGER REFERENCES users(id),
  created_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP
);

CREATE INDEX idx_rework_lote ON talleres_rework_orders(lote_id);
CREATE INDEX idx_rework_source_envio ON talleres_rework_orders(source_envio_id);
CREATE INDEX idx_rework_status ON talleres_rework_orders(status);
```

### 2-2. `talleres_envios` 컬럼 추가

```sql
ALTER TABLE talleres_envios ADD COLUMN rework_order_id INTEGER
  REFERENCES talleres_rework_orders(id);
CREATE INDEX idx_envios_rework ON talleres_envios(rework_order_id);
```

### 2-3. API 스키마

**POST /talleres/rework-orders**
- Body: `{ sourceEnvioId, sourceRecepcionId?, targetEtapaId, targetVendorId|null, quantity, defectCodeId?, reason? }`
- 트랜잭션:
  1. source envio 검증 (존재, storeId 일치, quantity <= recepcion.defectQuantity 또는 available)
  2. ReworkOrder 생성 (status=PENDING)
  3. 새 Envio 생성 (envioDate=오늘, pendingQuantity=quantity, sourceRecepcionId, reworkOrderId=생성된 ID)
  4. ReworkOrder.resulting_envio_id 업데이트
  5. 캐시 무효화
- Response: `{ reworkOrder, resultingEnvio }`

**GET /talleres/rework-orders?loteId=**
- Lote 기준 rework 목록 (include source envio, target etapa/vendor, defect code)

**PATCH /talleres/rework-orders/:id/status**
- Body: `{ status: 'CANCELLED' }` 만 수동 허용 (나머지는 envio 상태에 따라 자동 전환)

**자동 상태 전환 로직** (envio/recepcion 서비스 수정):
- Envio가 PARTIAL/COMPLETED 될 때 그 envio에 rework_order_id 있으면 ReworkOrder도 같은 상태로 자동 업데이트 (IN_PROGRESS / COMPLETED)

## 기술 스택

- 백엔드: NestJS 11 + Sequelize + PostgreSQL (PG15 local, PG10 운영 — 마이그레이션 PG10 호환 필수)
- 프론트: Next.js 13 + MUI 5 + @dnd-kit
- DB 마이그레이션: SQL 파일, api-ventago/migrations/ (PG10 호환, 사용자 확인 후 실행)

## 태스크 목록

- [x] TASK-28: SPEC (현재 문서)

**단계 1 — 이 세션에서 완료**
- [ ] TASK-29: `buildRoutingPath` 시그니처 변경 — assignments의 order 존중
- [ ] TASK-30: `updateRoutingPath` 가드 재작성 + `getRoutingStatus` helper 신설
- [ ] TASK-30a: 새 GET 엔드포인트 `/talleres/lotes/:id/routing-status` (각 etapa별 COMPLETED/IN_PROGRESS/FREE)
- [ ] TASK-31: `RutaConfigDialog.tsx` — @dnd-kit/sortable 도입, 상태 배지, drag handle 조건부, "Agregar etapa" 버튼
- [ ] TASK-31a: Dialog 열릴 때 `/routing-status` 호출해서 상태 맵 가져오기

**단계 2 — 이 세션 (백엔드까지)**
- [ ] TASK-32: `api-ventago/migrations/wave11-rework.sql` 작성 (PG10 호환)
- [ ] TASK-33: `ReworkOrder` 모델/서비스/컨트롤러 (api-ventago/src/app/subcon/rework-orders/)
- [ ] TASK-33a: Envio 모델에 `reworkOrderId` 컬럼 추가 + Recepcion 생성 시 rework 자동 상태 전환
- [ ] TASK-33b: SubconModule에 ReworkOrder 등록

**다음 세션 — 단계 2 프론트 (이 SPEC에 예약만, 구현은 안 함)**
- TASK-34-A: Recepcion UI에 "Enviar a rework" 버튼 + 패널
- TASK-34-B: RoutingFlow에 rework 배지 + "Rework activo" 섹션
- TASK-34-C: Talleres 메뉴에 "Reworks" 탭 (목록, 상태 필터)

**이 세션 마무리**
- [ ] TASK-34: ESLint 검증 + 리뷰 리포트 + 다음 세션 TODO 문서화

## 완료 기준 (이 세션)

**단계 1:**
- [ ] 새 Lote에서 발급 후 "Editar ruta"로 FREE 단계들 순서 드래그 변경 가능
- [ ] IN_PROGRESS 단계는 drag handle 회색 처리 (drag 불가)
- [ ] COMPLETED 단계는 배지로 잠금 표시, vendor select 비활성화
- [ ] cut_date 있어도 FREE/IN_PROGRESS 단계는 여전히 편집 가능 (상태별 잠금이 핵심)
- [ ] 백엔드가 잘못된 변경(완료 단계 제거 등) 시도 시 400 반환

**단계 2 (백엔드만):**
- [ ] 마이그레이션 SQL 검증 가능 상태 (파일로 저장)
- [ ] POST /talleres/rework-orders 호출 시 ReworkOrder + 새 Envio 생성 (트랜잭션)
- [ ] envios.rework_order_id 컬럼 추가 + 기존 envios는 NULL
- [ ] 프론트 미구현이므로 curl/Postman로 테스트 가능

## 금지사항 / 주의사항

- 기존 CT의 routing_path는 소급 변경하지 않음
- PostgreSQL pool: 모든 신규 쿼리는 트랜잭션 재사용, count/집계는 1회만
- PG10 호환: `GENERATED AS IDENTITY` 금지 → `SERIAL` 사용
- Spanish 사용자 메시지 (toast, BadRequest)
- 한국어 주석, 영어 함수/변수
- 마이그레이션은 사용자 확인 전 실행 금지 (DDL 규칙)
- 이 세션에서 단계 2 프론트는 손대지 않음 (범위 명확화)

## 다음 세션 TODO 요약

단계 2 프론트:
1. `ReworkDialog.tsx` — Recepcion에서 defectQuantity > 0일 때 "Enviar a rework" 버튼 → 이 다이얼로그
2. `RoutingFlow.tsx` 확장 — rework activos 섹션 추가
3. `ReworksTab.tsx` — Talleres 메인 메뉴에 새 탭
4. `useReworkOrders` SWR 훅
