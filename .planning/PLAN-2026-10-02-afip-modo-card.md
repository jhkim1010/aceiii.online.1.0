# Modo AFIP (emisión) 화면 개선 — 계획 (2026-10-02)

## 문제 (실제로 일어난 일)
- Noix 화면에서 **「Cambiar a: ARCA directo (SOAP) · Producción」** 이 보여서 사용자가 **이미 soap 인 줄** 알았다.
  실제는 `ws`(게이트웨이). 「Cambiar modo」 를 누른 적이 없다.
- 원인 (`ventago-app/src/views/admin/stores/details/components/AfipModoCard.tsx`)
  - 현재 모드는 **작은 본문 한 줄**(「Modo actual: …」), 목표 선택칸은 **큰 입력칸** — 눈은 큰 쪽을 읽는다.
  - 목표의 기본값이 `useState("soap")` + `"prod"` → **아무것도 안 해도 SOAP·Producción 이 채워져 있다.**
  - 버튼 문구 「Cambiar modo」 는 무엇으로 바뀌는지 말하지 않는다.
  - 발행자 표의 「Entorno actual: Producción」 이 ws 에서도 같은 모양 → soap 운영처럼 보인다.

## 제안 (app 1파일 + api 소폭)
1. **현재 모드 배지** (카드 맨 위, 크게)
   - `ws` → 🔵 **Gateway cool-invoice** · siempre producción
   - `soap`+prod → 🟢 **ARCA directo · Producción**
   - `soap`+homo → 🟠 **ARCA directo · Homologación** (sin validez fiscal)
   - 옆에 「Comprobantes emitidos: N · último DD/MM」 — 0 이면 「todavía ninguno」 (api: preview 응답에 집계 추가)
2. **바꾸기는 3개 카드 중 선택** — Gateway / ARCA·Producción / ARCA·Homologación
   - **기본은 아무것도 선택 안 됨.** 현재 모드 카드는 「ACTUAL」 표시 + 선택 불가.
   - 선택 전에는 미리보기·버튼 없음 → 「목표가 채워진 채로 보이는」 상태가 생기지 않는다.
3. **버튼 문구에 목표**: 「Cambiar a ARCA directo · Producción」
4. **점검 목록(✓/✗)** — 지금의 빨간 「No se puede…」 대신 항목별로
   - Certificado válido (CUIT · vence 2028-09-30) ✓
   - Emisores con punto de venta ✓
   - **Delegación «Factura electrónica (wsfe)» en ARCA — no se verifica desde acá** ⚠
     (사람이 ARCA 에서 확인해야 한다는 것을 **화면이 말한다**. 자동 확인은 하지 않음 — WSAA 로그인이
      공유 인증서 TA 를 건드려 최대 12시간 발급을 막을 수 있다 [메모리: afip-ta-is-per-certificate])
5. **발행자 표**: Entorno 칸을 「Producción (gateway)」 / 「Producción (ARCA)」 / 「Homologación」 로 경로까지.
6. **확인창**: 「현재 배지 → 목표 배지」 를 색으로 나란히 + 첫 발급이 실제 AFIP 전표라는 경고(운영일 때).

## 범위 밖
- 전환 로직·가드(서버 `provider-switch`)는 그대로. 화면 표시 + preview 응답 집계 1개만.

## 영향 · 규모
| 대상 | 내용 |
|---|---|
| app | `AfipModoCard.tsx` |
| api | `provider-switch/:storeId/preview` 응답에 `comprobantes: { total, ultimo }` (afip_vouchers 집계, store 단위) |
| DB | 없음 |
| 규모 | S~M |
| 배포 순서 | api 먼저(필드 추가만) → app. 어느 쪽이 먼저 나가도 안전(없으면 배지 옆 집계만 안 보임) |
