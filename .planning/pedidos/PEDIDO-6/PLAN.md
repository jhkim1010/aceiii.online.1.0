# PEDIDO #6 — 「Importacion de legacy」

| 항목 | 내용 |
|---|---|
| 매장 · 지점 | Shaple (store 26) · Shaple |
| 요청자 · 일시 | sebi park · 2026-10-02 16:16 (AR) |
| 분류 | **사용법 혼동 + 화면 개선** (기능 결함은 아님) |
| 접수 답장 | 자동 발송됨 |

## 요청 원문
> hay tablas que no hacer importacion  (가져오지 않는 표가 있다)

첨부 캡처: 레거시 임포트 **2단계(미리보기)** 에서 `logs`·`vdetalle`·`codigos_tmp`·`vcodes`·`ingresos`·
`fventas`·`cobdetalles` 가 회색 **「Ignorado」** 로 표시. 파일 `shaple_2026-10-02.backup` 41.75MB.
경고: `logs`·`vdetalle` truncated at 200000 rows.

## 현재 동작 (코드 근거)
레거시 임포트는 **두 단계**다 (메모리 `legacy-import-has-two-paths`).

| 단계 | 무엇 | 어디서 |
|---|---|---|
| 1. 한 방 (`runImport`) | 색·분류·시즌·원산지·공급자·상품(마드레/변형)·가격·판매원·고객 | 지금 보고 있는 미리보기 화면 |
| 2. 「Pasar a la tienda」 | ② 재고(`ingresos`) · ③ 판매(`vcodes`·`vdetalle`) · ④ 팩투라(`fventas`) · ⑥ 비용 | 1단계 **결과 화면**의 버튼 「Seguir: stock, ventas, facturas y gastos」 (`ImportLegacyView.tsx:620`) |

- 미리보기 라벨은 **1단계 기준**이라 2단계에서 가져갈 표도 전부 「Ignorado」(`ImportLegacyView.tsx:153`)로 보인다
  → 매장은 「판매·재고는 안 들어간다」로 읽는다. **그게 이번 요청의 원인.**
- `truncated at 200000` 경고는 **미리보기 파서**(`sql-parser.service.ts:48`)의 상한이다. 2단계는 이 파서를
  쓰지 않고 staging 에 COPY 하므로(`parseSql` 사용처는 `legacy-import.service.ts` 뿐) **판매 20만 행 제한은 없다.**
  그런데 화면은 그 사실을 말하지 않아 「데이터가 잘린다」로 보인다.
- 실제로 **안 가져오는 것**: `logs`·`codigos_tmp`(작업용 임시표) — 의도된 제외.
  ⑤ 외상·온라인은 매퍼가 없어 아직 못 한다(알려진 미완).
- 2단계 버튼은 1단계를 **실행한 뒤에만** 나온다. 미리보기에서는 다음 단계가 있다는 안내가 없다.

## 제안 (권고안) — 화면 문구·라벨만, 동작 변경 없음
1. 미리보기 「Se importa como」 라벨을 3종으로 나눈다:
   - 1단계 대상: 지금처럼 색 칩
   - **2단계 대상**: 「Paso 2 · ③ Ventas / ② Stock / ④ Facturas / ⑥ Gastos」 (파란 테두리 칩)
   - 진짜 제외: 「No se usa」 + 이유 툴팁 (`logs`: historial interno, `codigos_tmp`: tabla temporal)
2. 표 위에 안내 배너: 「Ventas, stock, facturas y gastos se pasan en el **paso 2**, después de importar el catálogo.」
3. truncated 경고 문구 보완: 「Sólo afecta a esta vista previa. Las ventas se importan completas en el paso 2.」
4. (선택) ⑤ 외상·온라인처럼 **아직 못 가져오는** 표는 「Todavía no se importa」로 구분.

### 대안
- B: 미리보기에서 바로 2단계까지 이어 실행 — 지점 매핑(사람이 정함)이 필요해 한 화면에 넣으면 실수 위험. 비권장.

## 영향
| 대상 | 내용 |
|---|---|
| app | `ImportLegacyView.tsx` (라벨 매핑·배너·경고 문구) |
| api | 미리보기 응답에 표별 「어느 단계」 정보가 없으면 **프론트 상수 표**로 매핑 (`ace-branches.sql.ts` 의 표 목록과 같은 근거). api 변경 없이 가능 |
| DB | 없음 |
| 위험 | 낮음 — 표시만 바뀜. 표 이름→단계 매핑이 두 곳(api 스트리밍 SQL, app 상수)에 생기므로 **시험으로 대조**(app jest 순수 .ts) |

## 규모 · 검증
- 규모: **S**
- 검증: app tsc/eslint/jest(매핑 상수) · 로컬 더미 백업으로 미리보기 화면 확인

## 매장에 보낼 답변 초안 (지금 바로 보내도 되는 사용법 안내)
> ¡Hola Sebi! Esas tablas no se pierden: la importación tiene **2 pasos**. Primero «Importar a mi tienda»
> (catálogo, precios, vendedores y clientes). Al terminar aparece el botón **«Seguir: stock, ventas,
> facturas y gastos»**: ahí elegís a qué sucursal va cada sucursal de ACE y se pasan **ventas (vcodes,
> vdetalle), stock (ingresos), facturas (fventas) y gastos**, completos (el aviso de 200.000 filas es
> sólo de la vista previa). `logs` y `codigos_tmp` no se usan a propósito. Vamos a aclarar esto en la pantalla.
