# Phase 92 — ARCA 발급분 vs 수령분 균형 보기 (CONTEXT, 2026-09-22)

사용자 정의 목적: **「받은 영수증과 발급한 영수증이 어느 정도 발랜싱이 되고 있는지 아는 것」.**
매입 원장·공급자 채무 관리는 **이번 범위가 아니다**(원자재 모듈이 이미 그 일을 한다).

**상태: 계획만.** 사용자 결정(2026-09-22) — 「코드 작업은 다음 달」. 착수 전 §7-1(실제 파일 확보)부터.
Mock-up: https://claude.ai/artifact/GreadkC8Y2GccrbDKXzG7S (화면 3개 + 한글 메모)

---

## 1. 왜 수동 업로드인가 (조사 결과)

| 대상 | 공식 웹서비스 | 방법 |
|---|---|---|
| **emitidos** | 있다 — `FECompUltimoAutorizado` + `FECompConsultar` | 다만 **날짜 구간 목록 조회가 없다.** 번호를 1건씩 도는 수밖에 없다(지금 `serie-verificacion.service.ts` 가 그렇게 한다) |
| **recibidos** | **없다** | ARCA WS 카탈로그에 수령 전표를 나열하는 서비스가 없다. 포털 「Mis Comprobantes」 CSV/XLS 내려받기뿐 |

- `wsmicomprobantes` 같은 서비스는 **존재하지 않는다**(카탈로그 확인).
- 제3자 「API」(AfipSDK 등)는 **클라베 피스칼을 넘겨 사이트를 조작하는 로봇**이다 — 세무 계정 탈취 위험. **채택하지 않는다.**
- `WSCDC` 는 **검증용**이다: 번호·금액·CAE 를 주면 A/R 만 돌려준다. 무엇을 받았는지 알아낼 수 없다.
  (나중에 「올린 파일이 손으로 고쳐졌는가」를 막는 데는 쓸 수 있다. 인증서에 `wscdc` 위임 추가 필요.)

근거: ARCA WS 카탈로그 / WSCDC 매뉴얼 v0.4(2025-12-01) / WSFEv1 매뉴얼(RG 4291).

---

## 2. 범위 (최소)

**한다**
1. Mis Comprobantes 의 **Emitidos·Recibidos** 파일 업로드 (CSV 세미콜론/쉼표 자동 감지 + XLSX).
2. 월별 **Balance** 표: 발급 합계(neto·IVA) vs 수령 합계(neto·IVA), 차액.
3. 발급분 대조: **ARCA 에는 있는데 우리 DB 에 없는 전표** 목록(부수 효과, 아래 §5).

**하지 않는다** (이번에)
- 매입 원장·공급자 채무·지급 관리 — 원자재 모듈과 갈라진다.
- `expenses` ↔ 전표 연결.
- Libro IVA **COMPRAS** 고정폭 파일 — 레코드 레이아웃이 VENTAS 와 다르다. 신고는 회계사의 Portal IVA 가 한다.
- WSCDC 검증(2차 후보).

---

## 3. 데이터

테이블 **1개**: `afip_comprobantes_recibidos`.
`afip_comprobantes_externos` 를 본뜬다 — Libro IVA 필드를 이미 갖춘 유일한 테이블이다.

차이는 둘뿐:
- `cuit` 의 의미가 **발행자(공급자)** 다 → `cuit_emisor` + `cuit_receptor`(우리) 로 나눈다.
- `origen`(= 업로드한 파일/일시)과 멱등키.

멱등키: `UNIQUE (store_id, cuit_emisor, tipo_comprobante, punto_venta, afip_number)`.
같은 달을 두 번 올려도 늘어나지 않아야 한다(사람이 올리는 파일이다).

금액 불변식 `ImpTotal = ImpNeto + ImpIVA + ImpTotConc + ImpOpEx + ImpTrib` 검사는
`comprobante-externo.service.ts:45-79` 를 재사용한다.

emitidos 파일은 **저장하지 않는다** — 우리 `afip_vouchers` + `afip_comprobantes_externos` 가
이미 원장이다. 업로드분은 **대조용으로만** 읽고 차이만 보여 준다(§5).

---

## 4. 만들 것

| 층 | 내용 |
|---|---|
| API | `POST /afip/recibidos/import` (multer + exceljs; `xlsx` 는 백엔드 의존성이 **아니다**) · `GET /afip/balance?desde&hasta` |
| 화면 | `/facturacion` 에 탭 2개 — 「Importar」, 「Balance」. 업로드 선례: `CargaMasivaClientesView.tsx`, `CodeImportDialog.tsx` |
| 파서 | CSV 구분자 자동 감지(ARCA 는 `;` 인 경우가 있다) + XLSX. 서버측 CSV 선례: `delivery-payout-csv.service.ts` |

---

## 5. 부수 효과 — 이것이 실제로 값어치가 크다

PV 4 는 **cool-invoice 와 공유**한다(`cuit_compartido = true`). 즉 우리 DB 의 발급 합계는
그 CUIT 이 실제 발급한 전부가 아니다. ARCA 의 emitidos 파일을 올리면
**「ARCA 에는 있는데 우리에겐 없는 전표」가 그 자리에서 드러난다** —
지금은 결번을 한 건씩 `FECompConsultar` 로 되물어야만 알 수 있다.

찾아낸 전표는 기존 `POST /afip/externos` 로 담으면 Libro IVA 집계에 합류한다
(그 API 는 이미 있고 **화면만 없다**).

---

## 6. 읽는 사람이 오해하면 안 되는 것

- **IVA 크레딧은 A 전표만 준다.** B·C 를 섞어 합치면 「균형」 숫자가 거짓이 된다 →
  전표 종류별로 나눠 보여 준다.
- **ARCA 반영이 최대 24시간 늦다.** 「오늘 받은 청구서」는 어떤 방법으로도 안 나온다.
- 대상 매장은 **store 6(CUIT 20950928434, producción)** 하나다.
  store 9(ACE)는 homologación 전용 — 세무상 무효다.
- 사람이 올리는 파일이라 **CAE·금액을 손으로 고칠 수 있다.** 그래서 이 화면은
  「감시용」이고 신고 근거가 아니다. 근거로 쓰려면 WSCDC 검증이 붙어야 한다.

---

## 7. 순서

1. 표본 확보 — 실제 Mis Comprobantes 파일(emitidos·recibidos) 각 1개. **컬럼명을 추측하지 않는다.**
2. 파서 + 테이블 + import 엔드포인트 (시험: 중복 업로드 멱등 · 금액 불변식 · 구분자 감지).
3. Balance 집계 + 화면.
4. (선택) 「ARCA 에만 있는 전표」 목록 → 기존 `POST /afip/externos` 로 담기.

★ 1번이 먼저다. 파일 형식을 모르면 2번은 추측 위에 세우는 것이다.
