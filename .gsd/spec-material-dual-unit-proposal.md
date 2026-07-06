# 제안서: 원단 이중 단위 관리 (rollo ↔ metro)
작성일: 2026-07-03 · 상태: **Phase A 구현 완료 (2026-07-03)** — 사용자 결정: A만 / kg 포함 / 관리 UI 전환

## 구현 완료 (Phase A)
- 마이그레이션: `api-ventago/migrations/material-dual-unit.sql` — **로컬 적용: 사용자 psql 실행 / 운영 적용: 미완 (SSH 수동 — 누락 주의!)**
- 백엔드: Material 모델 4필드, `POST /mes/materials/:id/convert-to-dual` (1회 전환, 재고 ×factor), buildBomSnapshot merma 반영+스냅샷 동결, `POST /materia-prima/movements/retazo` (AJUSTE)
- 프론트: `src/utils/material-units.ts` (formatDualStock/formatPurchaseEquivalent/isDualUnit), InventarioView 이중 표시+전환 다이얼로그, BomEditorSection 단위 칩+이중 재고, cut ticket BomTable rollo 환산+merma 표시+retazo 버튼

## 후속 (미구현)
- ENTRADA 모달 rollos × m/rollo 이중 입력 (전환 후 m 직접 입력으로 대체 가능 — 편의 기능)
- 신규 자재 생성 폼에서 바로 이중 단위 설정 (현재는 생성 후 전환 버튼)
- merma 리포트 (이론 vs retazo 실적)
- Phase B/C (롤 개별 추적, dye lot, ancho/rendimiento)

## 1. 문제 정의

원단(tela)은 **rollo 단위로 구매·보관**하지만 **metro 단위로 소비**된다.
현재 시스템은 자재당 단위 1개(`mes_materials.unit`)와 재고 숫자 1개(`currentStock`)만 있어:

- BOM 에 "옷 1장당 몇 rollo" 같은 비현실적 입력이 강제됨 (스크린샷: PICACHU ROJO, unidad=rollo)
- 재고가 "몇 rollo 남았는지"만 보여 실제 사용 가능한 m 를 알 수 없음
- 가격도 rollo 단가/m 단가가 섞여 원가 계산 신뢰도 저하

## 2. 실무 시나리오 조사 (의류 제조 현장)

| # | 시나리오 | 시스템에 필요한 것 |
|---|---------|------------------|
| S1 | **롤 길이 편차**: 명목 50m/rollo 라도 실제 입고 롤은 47~52m. 공급자 인보이스는 실측 m 합계로 청구 | 입고 시 롤 수 + 롤당 실측 m 입력 |
| S2 | **열린 롤(rollo abierto)**: 재단 후 부분 사용된 롤 발생. "닫힌 3롤 + 열린 1롤 12.5m" 가 현장의 실제 재고 표현 | 이중 표시: N rollos + sobrante m |
| S3 | **니트/저지는 kg 거래**: tela de punto 는 kg 단위 구매, rendimiento(m/kg)로 환산 | 변환 계수를 rollo 전용이 아닌 일반 구조로 |
| S4 | **폭(ancho) 의존 소비량**: 같은 원단도 1.50m 폭 vs 1.80m 폭이면 prenda 당 소비 m 가 다름 | BOM consumo 는 특정 ancho 기준 — 자재에 ancho 기록 |
| S5 | **염색 로트(partida de teñido)**: 같은 색도 partida 가 다르면 색차 발생 → 한 lote 는 같은 partida 로 재단해야 함 | (고급) 롤별 partida 추적 |
| S6 | **merma(손실)**: 재단 손실·수축 5~10% — BOM 명목 소비량보다 실제 차감이 많음 | (고급) merma % 필드 |
| S7 | **가격 단위 혼동**: 구매는 rollo/kg 단가, 원가·BOM 은 m 단가 필요 | 단가의 기준 단위 명시 |
| S8 | **재고 실사**: 닫힌 롤은 세면 되지만 열린 롤은 m 추정 → AJUSTE 빈번 | 이중 단위 AJUSTE UI |
| S9 | **리오더 감각**: 창고 담당자는 "2롤 이하면 주문" 으로 사고 | minStock 의 rollo 환산 병기 |

## 3. 설계 제안 — 3단계 (Phase A 권장 착수)

### Phase A: 이중 단위 코어 (MVP)

**원칙: 재고의 단일 진실 = 소비 단위(m). rollo 는 표시/입력 보조.**

DB (`mes_materials` 컬럼 추가, 기존 데이터 무해):
```sql
ALTER TABLE mes_materials
  ADD COLUMN purchase_unit    varchar(20),        -- 'rollo' | 'kg' | NULL(=단일 단위)
  ADD COLUMN consumption_unit varchar(20),        -- 'm' 등. NULL 이면 기존 unit 그대로
  ADD COLUMN conversion_factor numeric(10,3);     -- 1 구매단위 = N 소비단위 (명목값, 예: 50)
-- 운영 적용 시 ALTER TABLE ... OWNER TO coolsistema 불필요(컬럼 추가) — 기존 테이블 owner 그대로
```

- `conversion_factor IS NOT NULL` 인 자재만 이중 단위 동작. 기존 자재는 무변경 (하위호환).
- `currentStock`/`minStock`/BOM `quantity`/`standardPrice` 는 **소비 단위 기준으로 통일**.
- 기존에 rollo 수로 저장된 currentStock 은 자재별 확인 후 ×factor 변환 (일괄 스크립트 대신 관리 UI 에서 자재별 전환 버튼 — 실사 겸용).

**표시 헬퍼** (프론트 공용 util):
```
formatDualStock(162.5, factor=50, 'rollo', 'm')
→ "162.5 m  (3 rollos + 12.5 m)"
```

UI 변경 4곳:
1. **자재 등록/수정 폼** (Materia Prima): 단위 섹션을
   `Unidad de compra [rollo ▾] · Metros por rollo [50] · Unidad de consumo [m ▾]` 로 확장. 미입력 시 기존 단일 단위.
2. **ENTRADA 모달**: `Rollos [4] × m/rollo real [48.5] = 194 m` 라이브 계산.
   저장은 194 m + notes 에 "4 rollos × 48.5 m" 자동 기입 (감사 추적).
   "롤별 실측 입력" 토글 → 48.5 / 49.2 / 47.8 / 50.1 개별 입력(합산).
3. **재고 표시** (InventarioView + Cost Sheet BOM 편집기 + cut ticket BomTable):
   `162.5 m (3 rollos + 12.5 m)` — 큰 숫자는 m, 괄호는 rollo 환산.
   minStock 경고도 m 기준, 툴팁에 rollo 환산.
4. **BOM 편집기**: Cantidad 필드 suffix 를 consumption_unit('m')로 고정 + 칩 `1 rollo = 50 m`.
   Precio 라벨 `Precio/m`. → cut ticket 차감 로직(consumeMaterialsFromBom)은 이미 m 로 흐르므로 **변경 불필요**.
   cut ticket BOM 테이블에 총소비 `195 m (≈ 3.9 rollos)` 병기 — 재단실에 몇 롤 내릴지 즉시 판단.

### Phase B: 롤 단위 정밀 추적 (선택)

`mes_material_rolls` 신규 테이블: material_id / entry_movement_id / actual_m / remaining_m /
status(CERRADO·ABIERTO·AGOTADO) / dye_lot / ubicación.
- 재단 출고 시 롤 선택(FIFO 제안), S2·S5·S8 완전 해결.
- 비용: 출고 UX 복잡도 상승 — 현장 정착 후 도입 권장.

### Phase C: 원가 정밀화 (선택)
- ancho, rendimiento(m/kg) → consumo 자동 보정, 공급자별 실측 부족(short delivery) 리포트.

## 3b. 짜투리(cabo/retazo) 처리 — 실무 방식 조사 (사용자 질문: 100m×10롤 ≠ 가용 1000m)

실무 3방식:
- **방식1 (보편)**: BOM 소비량에 merma % 포함 — consumo bruto = neto × (1+merma). 직물 2~5%, 니트/프린트 5~10%. 재고는 bruto 로 차감, 실사로 보정.
- **방식2**: 입고 시 롤당 고정 cabo 공제 (100m→가용 97m). 부정확해 단독 사용 드묾.
- **방식3 (정밀)**: 재단 후 최소 마커 길이 미만 잔량을 "retazo 선언" → AJUSTE 차감 + retazo 부재고 이동(kg 판매/재활용). 대형 공장은 cut planning SW 로 롤 배분 최적화.

**Ventago 권장: 방식1 + 방식3 라이트 → Phase A 에 포함**
- A-5: 자재(기본값) + BOM 라인(오버라이드)에 `merma_pct` — cut ticket 차감 시 자동 반영
- A-6: 재단 화면 "Declarar retazo" 액션 — 잔량 m 입력 → AJUSTE(reason=RETAZO). MovementType 재사용, 신규 타입 불필요
- A-7(리포트, 후순위): lote 별 이론 merma vs 실제 retazo 비교

## 4. 하위호환 / 리스크

- conversion_factor 없는 자재는 100% 기존 동작 — 점진 도입 가능
- 위험 지점 1곳: **기존 rollo 재고의 m 전환** — 자재별 수동 확인 필수 (자동 일괄 변환 금지)
- pool: 컬럼 추가만, 쿼리 패턴 불변

## 5. 결정 필요 사항
1. Phase A 만 먼저? (권장) A+B 동시?
2. 니트 kg(rendimiento) 지원을 A 에 포함? (구조는 동일 — factor 만 m/kg)
3. 기존 rollo 자재 전환 방식: 관리 UI 버튼(권장) vs SQL 일괄
