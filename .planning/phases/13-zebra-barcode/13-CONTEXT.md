---
phase: 13
title: "Nuevo Producto + Zebra Barcode Agent"
status: draft
depends_on: ["01"]
estimate: 7 days
waves: 5
---

# Phase 13: Nuevo Producto 고도화 + Zebra Barcode Agent

## 목적

상품 등록(Products → Nuevo Producto) UX 를 "카테고리 → 부모 SKU → 색상·사이즈 자식 SKU" 흐름으로
재설계하고, 각 SKU 마다 재고 단위로 스캔 가능한 바코드를 Zebra 프린터로 자동 출력할 수 있는
**독립 데스크탑 Zebra Agent** (Phase 11 Print Agent 아키텍처 재사용) 를 구축한다.

- 부모 코드: `codigo madre` = SKU 부모 (상품 본체)
- 자식 코드: `codigos hijitos` = 색상 × 사이즈 조합별 자식 SKU, 각자 `id_codigo` 단일값 보유
- 재고: 자식 SKU 단위로 추적
- 태그: `temporada`, `origen` 을 tag 스타일로 저장해서 나중에 통계/필터에 활용
- 출력: Zebra ZPL 프린터 (`ZPL II`) 로 바코드 라벨 (80mm 감열지와 별개 장비)

주요 환경: **Windows (우선)**, macOS (지원) — Print Agent 와 동일한 크로스 플랫폼 Electron 배포

---

## 두 가지 흐름

### A) 상품 생성 (Products → Nuevo Producto)

| 단계 | UI | 동작 |
|------|-----|------|
| 1 | Category 선택 | 선택된 category prefix 로 `codigo madre` 자동 생성 (`CAM-2026-0001` 식) |
| 2 | 상품 기본 정보 | name, price, cost, supplier, description |
| 3 | 색상·사이즈 매트릭스 | 다중 선택한 colors × sizes 조합을 `codigos hijitos` 로 일괄 생성 |
| 4 | Tag 입력 | `temporada` (Verano 2026 등), `origen` (Importado/Nacional 등) — 태그 형태 |
| 5 | 생성 완료 후 | 각 자식 SKU 마다 Zebra Agent 로 라벨 출력 옵션 (일괄/개별) |

### B) 바코드 출력 (Zebra Agent)

| 문서 | 트리거 | 형식 | 내용 |
|------|--------|------|------|
| **Etiqueta de Producto** | `print_barcode` 이벤트 | ZPL II 그래픽 | 매장 로고, 상품명(2줄), 색상·사이즈, 가격, Code128 바코드 (id_codigo) |

---

## 기존 자산 (재사용 가능)

| 자산 | 위치 | Phase 13 재사용 목적 |
|------|------|---------------------|
| Product 모델 `sku`, `parentId`, `HasMany Product[]` | [products.model.ts](api-ventago/src/app/products/products.model.ts) | 부모-자식 관계는 이미 존재, UI/생성 로직만 추가 |
| `products-categories` 서브모듈 | `api-ventago/src/app/products/products-categories/` | category prefix 소스 |
| `colors`/`sizes` 설정 엔티티 | `api-ventago/src/app/config/productos/...` | 매트릭스 조합의 기반 |
| Print Agent 아키텍처 전체 | `print-agent/` | Zebra Agent 의 베이스 (WebSocket, 트레이, 셋업 마법사, 업데이트 파이프라인) |
| `BranchPrinterConfig` 테이블 + `/print/config/:branchId` | `api-ventago/src/app/print/` | 지점당 Zebra 설정·API Key·온라인 상태 공통 관리 (스키마 확장) |
| PrintGateway `/print-agent` 네임스페이스 | [print.gateway.ts](api-ventago/src/app/print/print.gateway.ts) | Zebra Agent 도 같은 게이트웨이에 별도 이벤트로 합류 |
| Electron GitHub Actions 크로스 빌드 파이프라인 (Phase 11-05) | `.github/workflows/print-agent-release.yml` | Zebra Agent 도 동일 포맷의 job 추가 |

---

## 신규 작업 요약

### 백엔드 (api-ventago)
- `products` 모듈: `codigo madre` 자동 생성 서비스 (category prefix + 시퀀스)
- `products` 모듈: 매트릭스 벌크 자식 생성 API `POST /products/:id/variants` (colors × sizes)
- `products` 모듈: `temporada` / `origen` 필드 (Product 모델 확장 또는 `product_tags` 정규화 테이블)
- `products-barcode` 서비스: `id_codigo` 채번(자식 SKU 단위, UNIQUE per store)
- `print` 모듈 확장: Zebra 지원
  - `print_barcode` 이벤트 추가
  - `BranchPrinterConfig` 에 `zebra_printer_info`, `zebra_online` 추가 또는 `agent_type` enum (`thermal`/`zebra`) 으로 다중 로우 지원 (DB 설계 결정 필요)
  - 엔드포인트: `POST /print/barcode`, body `{ productIds, copies? }`
- DB 마이그레이션:
  - `products.temporada` / `products.origen` 또는 `product_tags` 테이블
  - `products.id_codigo` (자식 SKU 단위 스캔 식별자, 자동 생성)
  - `branch_printer_configs` 스키마 확장

### 프론트엔드 (ventago-app)
- `pages/productos/nuevo` (또는 기존 "Nuevo Producto" 모달) 재작성
  - Category 선택 → 부모 SKU 프리뷰
  - 색상·사이즈 매트릭스 선택 UI (체크박스 그리드)
  - Temporada / Origen 태그 입력 (Autocomplete + 신규 값 허용)
  - "Generar variantes" 버튼 → 자식 SKU 일괄 생성
  - 생성 직후 "Imprimir Etiquetas" 버튼 (Zebra Agent 로 전송)
- `pages/productos` 목록에서 각 상품 행에 "Imprimir Etiqueta" 액션 추가
- `services/zebra.service.ts`: `printBarcodes(productIds, copies)`
- 관리자 화면: Zebra Agent 상태 표시 + API Key 관리 (Print Agent 관리 UI 복제)

### Zebra Agent (`zebra-agent/`)
- `print-agent/` 전체 구조 복제 후 ZPL 전용으로 전환:
  - `src/zpl-formatter.js`: 상품 데이터 → ZPL II 명령어 (Code128 바코드 + 텍스트)
  - `src/zebra-printer.js`: USB / 네트워크 Zebra 디바이스 연결 (`node-escpos` 대신 raw TCP/USB write)
  - `main.js`: WebSocket `/print-agent` 네임스페이스 접속, `print_barcode` 이벤트 처리
  - 셋업 마법사: 프린터 IP/Port, DPI (203/300) 선택
  - `package.json` 크로스 빌드 설정 (electron-builder, NSIS Windows + DMG macOS)

---

## 데이터 계약

### `POST /products/:parentId/variants` (매트릭스 벌크 생성)
```json
{
  "colors":    [1, 5, 8],        // color IDs
  "sizes":     [12, 13, 14, 15], // size IDs
  "temporada": "Verano 2026",
  "origen":    "Nacional",
  "defaultPrice": 45000,
  "defaultCost":  18000
}
```
→ 3 × 4 = 12 개 자식 Product 생성, 각각 `parentId`, `colorId`, `sizeId`, 고유 `sku`, 고유 `id_codigo`, 동일 `temporada`/`origen` 태그.

### WebSocket `print_barcode` 이벤트 payload
```json
{
  "branchId":   12,
  "printer":    "zebra",
  "copies":     1,
  "labels": [
    {
      "idCodigo":  "VG-0012345",
      "productName": "REMERA PIMA MANGA CORTA PREMIUM",
      "color":     "Azul Marino",
      "size":      "M",
      "price":     45000,
      "storeName": "LA BOUTIQUE"
    }
  ]
}
```

### WebSocket 이벤트 규약 (Phase 11 확장)
| 이벤트 | 방향 | payload |
|--------|------|---------|
| `print_invoice` | Server → Thermal Agent | (Phase 11 기존) |
| `print_fiscal` | Server → Thermal Agent | (Phase 11 기존) |
| `print_temp` | Server → Thermal Agent | (Phase 11 기존) |
| **`print_barcode`** | Server → Zebra Agent | 위 스펙 |
| **`zebra_online`** | Zebra Agent → Server | `{ branchId, version, dpi }` |
| **`zebra_offline`** | Zebra Agent → Server | — |

---

## 열린 결정 사항 (discuss 단계에서 확정 필요)

1. **DB 모델링** — `temporada`/`origen` 을 Product 컬럼 2개로 할지, 정규화된 `product_tags` 다대다 테이블로 할지
2. **단일 BranchPrinterConfig vs 분리** — 지점당 thermal/zebra 를 한 row 에 확장 컬럼으로 둘지, `agent_type` enum 으로 row 2 개로 나눌지
3. **id_codigo 포맷** — 매장 prefix + 순번(`NA-0012345`)인지, UUID 파생 짧은 해시인지, 운영 스캐너 호환성 우선
4. **바코드 심볼로지** — Code128 단일인지, EAN-13 도 지원해서 외부 입고 상품과 호환할지
5. **매트릭스 UI 편집** — 생성 후 개별 자식 가격/코스트 개별 수정 가능한가 (Phase 13 범위 내/밖)
6. **Zebra Agent 네임스페이스** — Print Agent 와 같은 `/print-agent` 로 합칠지, `/zebra-agent` 로 분리할지 (PrintGateway 증설 vs 신규 게이트웨이)
7. **라벨 사이즈** — 고정값(40×25mm) 인지, Agent 설정에서 선택 가능한지
8. **기존 재고 데이터 마이그레이션** — 이미 parentId 없이 만들어진 레거시 상품에 `id_codigo` 일괄 채번 정책

---

## Wave 요약 (예상)

| Wave | Plan | 작업 | 예상 | 비고 |
|------|------|------|------|------|
| 1 | 13-01 | DB 마이그레이션 (temporada/origen/id_codigo) + Product 모델 확장 + BranchPrinterConfig zebra 지원 | 1일 | 결정 1·2·3 선행 |
| 2 | 13-02 | 백엔드: `codigo madre` 자동 생성 + 매트릭스 벌크 variants API + `POST /print/barcode` | 1.5일 | |
| 3 | 13-03 | 프론트: Nuevo Producto 매트릭스 UI + 태그 입력 + "Generar variantes" 흐름 | 1.5일 | |
| 4 | 13-04 | Zebra Agent 스켈레톤 (Electron + WebSocket + 셋업 마법사 + ZPL formatter + Zebra printer driver) | 2일 | Phase 11 Print Agent 복제 |
| 5 | 13-05 | 프론트 "Imprimir Etiqueta" + 관리자 Zebra 상태 UI + GitHub Actions 크로스 빌드 + E2E smoke | 1일 | 결정 6·7 필요 |

---

## 성공 기준 (Phase 완료 조건)

1. Nuevo Producto 에서 category 선택 시 `codigo madre` 가 자동 생성되어 미리보기
2. 색상·사이즈 매트릭스에서 N×M 조합을 1회 클릭으로 N×M 개 자식 SKU 생성 — 각 자식은 고유한 `sku` + `id_codigo` 보유
3. `temporada`, `origen` 이 태그로 저장되어 `GET /products?temporada=...&origen=...` 필터 및 리포트 집계 가능
4. Zebra Agent 가 Windows `.exe` + macOS `.dmg` 로 빌드되어 비개발자가 설치·셋업 가능
5. 생성 직후 "Imprimir Etiquetas" 클릭 시 자식 SKU 수만큼 Zebra 라벨 출력 (각 라벨에 Code128 + 상품명 + 색상·사이즈 + 가격)
6. Print Agent 와 Zebra Agent 가 동일 매장에서 **동시 동작** (네임스페이스 충돌 없음)
7. Zebra Agent 오프라인 시 상품 생성 / "Imprimir Etiqueta" 는 실패해도 사용자 판매/재고 흐름에 영향 없음 (fire-and-forget)
8. 관리자 화면에서 Zebra Agent 온라인 상태 실시간 표시 + API Key 재발급
9. 바코드 스캐너로 라벨을 스캔하면 `id_codigo` 값이 그대로 읽혀 `nueva-venta` 에서 해당 자식 SKU 자동 장바구니 추가 (재고 차감 단위 확인)

---

## 범위 밖 (Out of Scope)

- 엑셀 대량 import → 자식 SKU 일괄 채번 (Phase 5 레거시 import 와 연계, 별도 wave)
- Zebra 프린터 외 Brother/Dymo 라벨 프린터 지원 (추후 agent_type 추가로 확장)
- EAN-13 심볼로지 + GS1 기준 체크디짓 자동화 (결정 4에서 확장 여부 논의)
- 온라인 카탈로그(마켓플레이스) 자동 업데이트 — Phase 2 범위
- 매트릭스 편집 후 개별 자식 price override UI — 결정 5 에서 확정 필요
