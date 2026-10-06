# PEDIDO 10 — Zebra 에이전트: QR 라벨의 설명·가격 위치를 직접 조정

## 요청 원문 요약
- 매장: Cielo (store 22) · 지점: Cielo (branch 31, zebra 에이전트 id 24 «cielo») · 작성자: Joo Eun Um · 2026-10-05 13:22 (매장 시각)
- 원문: «cuando imprime QR codigo, k pueda controlar posici'on de descripcion y precio»
- **분류: 개선** (일부는 사용법 — 기능 자체는 이미 있으나 찾기 어렵고 조정 수단이 부족합니다)

## 현재 상태 (실측 · 코드 근거)

### ★ 위치 조정 기능은 이미 배포돼 있습니다
- 2026-10-02 `b7b5c32` (태그 **zebra-agent-v1.0.28**) 에서 추가: QR 탭 › «Texto de la etiqueta» 에서
  Descripción / Precio 를 켜고 끄고, **X/Y 를 mm 로 입력** (빈칸 = 자동).
  - 화면: `zebra-agent/renderer/index.html:638-658` (체크박스 + `qr-name-x/y` · `qr-price-x/y` + «Guardar configuración»)
  - QR 자체 위치 `qr-pos-x/y`: `:630-637` (v1.0.29)
  - 저장: `:2401-2411` → `setConfig('qrLayout')` (electron-store, **에이전트 PC 별**)
  - 그리기: `src/zpl-formatter.js:712-732` `textoQr()` (mm → dot ×8), `:749-800` `renderQrBlockApilado` (2 por etiqueta), `:810-866` `renderQrBlock` (1 por etiqueta)
- **Cielo 에이전트는 이미 v1.0.30** 입니다 (운영 `branch_agents.id=24 agent_version='1.0.30'`, 2026-10-05 16:49 UTC 온라인).
  ⤷ 주의: 오케스트레이터 메모의 「현재 태그 v1.0.9」는 틀렸습니다. 실제 최신 태그는 **zebra-agent-v1.0.30** 이고,
  PEDIDO 9 PLAN 의 「v1.0.9 → v1.0.10」도 **v1.0.30 → v1.0.31** 로 고쳐 읽어야 합니다.

### 그런데도 요청이 온 이유 (추정 — 근거 있는 것만)
1. **이 매장이 실제로 쓰는 경로는 QR 탭이 아닙니다.** 운영 `qr_print_log` 에서 branch 31 의 QR 탭 출력은
   2026-10-01 의 **2건뿐**입니다. 매장은 거의 「Etiquetas › Símbolo: Código QR」(SKU QR, 계산대용) 로 찍습니다
   (`index.html:263-298`). 그 화면엔 위치 조정이 없고 «Diseño (posición, tamaño, texto): pestaña «QR»» 라는
   안내문 한 줄만 있습니다(`:287`).
2. **다른 탭에서 바꾸고 «Guardar» 를 눌러야만** Etiquetas 출력에 반영됩니다. 인쇄·미리보기는 저장된 값만 읽습니다
   (`main.js:547` `texto: store.get('qrLayout')`, 미리보기도 `:579` 동일). QR 탭 미리보기는 저장 안 한 입력값으로
   바로 바뀌므로(`index.html:2383-2386`, `:2803`), **미리보기에선 움직였는데 인쇄는 그대로**인 상태가 쉽게 생깁니다.
3. **mm 숫자 입력뿐**입니다. 어느 값을 넣어야 어디로 가는지 알려면 시행착오가 필요합니다(끌어서 옮기기 없음).
4. **글자 크기를 따로 못 정합니다.** 설명=`fontSize`, 가격=`fontSize×0.9` 로 묶여 있고(`zpl-formatter.js:853`),
   «2 por etiqueta» 에서는 크기가 **12–16 dot 으로 고정 클램프**돼 «Fuente» 를 바꿔도 거의 안 변합니다(`:756`).
5. **정렬이 없습니다.** 2 por etiqueta 에서 QR 은 칸 가운데(`:768`)인데 글자는 왼쪽 정렬(`:779`)이라
   「가운데로 옮기고 싶다」를 mm 로 맞춰야 합니다.

## 제안 (권고안)
**「Etiquetas › Código QR」 패널 안에 바로 「Diseño del texto」 편집기를 둡니다 — 끌어서 옮기기 + 미세 조정 + 크기·정렬, 자동 저장.**

1. **위치: 미리보기에서 끌어서 옮기기** (zebra-agent renderer)
   - 기존 정확 미리보기 캔버스(`lote-pv-canvas`, 인쇄와 같은 ZPL 을 그림)에서 **설명/가격 글자를 클릭→드래그**.
     놓으면 0.5mm 격자로 스냅, 해당 X/Y 칸이 같이 바뀜.
   - 선택된 글자는 금색 테두리 + 화살표 버튼 ◀▲▼▶ (0.5mm, Shift=2mm) 로 미세 조정.
   - «Auto» 버튼 = 그 항목의 X/Y 를 비워 지금의 자동 위치로 복귀.
   - 구현: `zplADibujo` 가 텍스트 요소에 `campo: 'nombre'|'precio'` 를 달도록 formatter 가 ZPL 앞에 `^FX` 주석(인쇄 무해)을 붙이거나,
     formatter 가 텍스트 박스 좌표를 미리보기 응답에 같이 돌려줍니다(권고: 후자 — 인쇄 ZPL 은 한 바이트도 안 바뀜).
2. **크기: 설명·가격 별도** — «Tamaño» 를 두 칸으로(설명 / 가격, dot 10–40).
   2 por etiqueta 의 12–16 클램프는 **사용자가 값을 정했을 때만** 풀고, QR 이 작아지면 기존 경고 영역(`pintarAviso`)에
   «El QR bajó a X mm» 를 띄웁니다(스캔 최소 폭 아래면 빨간색).
3. **정렬: 설명·가격 각각 Izq / Centro / Der** — ZPL `^FB{폭},1,0,{L|C|R}` 로 칸 폭 안에서 정렬. 기본 = 지금과 동일(L).
4. **저장: 자동** — 바뀔 때마다 300ms 디바운스로 `setConfig('qrLayout')`. «Guardar» 버튼과 「저장 안 함」 상태를 없앱니다.
   QR 탭의 기존 X/Y 칸은 **같은 `qrLayout` 을 읽고 쓰므로** 두 화면이 항상 같은 값을 보여 줍니다(편집 대상은 한 곳).
5. **기존 값 호환** — 키 추가만: `nombreFs`, `precioFs`, `nombreAlign`, `precioAlign`. 없으면 지금 출력과 **바이트 단위로 같음**
   (`test/qr-texto.test.js` 기존 18 checks 그대로 통과가 기준).

### 대안
- **A (최소, S)**: 코드 변경 없이 매장에 사용법만 안내(아래 초안) — 단 위 2·4·5 의 불편은 남습니다.
- **B (중간, S~M)**: 편집기를 Etiquetas 패널로 옮기고 자동 저장만(드래그·크기·정렬 없음).

### 매장에 바로 보낼 수 있는 안내 (대안 A, 스페인어 초안 — 승인 시에만 발송)
> Hola Joo Eun! Ya se puede: en el Zebra Agent, pestaña **«QR»** → bloque **«Texto de la etiqueta»**.
> Ahí podés activar/desactivar *Descripción* y *Precio* y poner su posición en **X / Y (mm)** desde la esquina
> superior izquierda (con «2 por etiqueta», desde cada mitad). Vacío = automático.
> Después tocá **«Guardar configuración»**: recién ahí se aplica también a *Etiquetas → Código QR*.
> Estamos preparando una versión donde vas a poder **arrastrar** el texto sobre la vista previa.

## 범위 밖
- 바코드(CODE128) 라벨 배치 — 이미 별도 편집기(`setLabelLayout`)가 있음, 이번 요청 아님
- 설명 2줄 이상(2 por etiqueta) — QR 크기를 깎으므로 별도 판단 필요(`zpl-formatter.js:744` 주석의 「2줄 상한」)
- 서버(`branch_agents.printer_config`)에 배치를 저장해 PC 간 공유 — 지금은 에이전트 PC 별 저장 그대로
- 회전·굵게·폰트 종류

## 영향
- **api**: 없음 · **ventago-app**: 없음 · **DB 마이그레이션**: 없음
- **zebra-agent**: `renderer/index.html` · `src/zpl-formatter.js` · `main.js`(미리보기 응답에 텍스트 박스 좌표) · 테스트 → **새 릴리스 v1.0.31**.
  태그를 손으로 올려 GitHub Actions 빌드(로컬 electron-builder 금지 — 루트 node_modules 147개 증발 전례). 매장 PC 는 자동 업데이트.
- ★ **PEDIDO 9 와 같은 파일(`renderer/index.html`, Etiquetas 의 Productos 카드)** 을 고칩니다. 둘 다 Cielo 요청이므로
  **한 릴리스(v1.0.31)로 묶어** 내는 것을 권합니다(따로 내면 매장 PC 업데이트가 두 번, 충돌 해결도 두 번).
- **다른 매장**: 새 키가 없으면 출력 동일 → 영향 없음. 화면만 달라짐(편집기 추가).
- **중복 인쇄 위험**: 없음 — 드래그·자동 저장은 **미리보기만** 다시 그리며 인쇄 IPC 를 부르지 않습니다.
  인쇄 경로(`formatBatchLabels` · IPC `print:labels` `main.js:523` · `qr:print` `:674`)는 그대로입니다. 구현 시 이벤트 핸들러에서 인쇄 함수 호출이 없는지 검사 항목으로 둡니다.
- **위험**: 낮음~중간 — 미리보기(renderer 미러)와 실물이 어긋날 위험. 그래서 미리보기는 **formatter 가 만든 ZPL 을 그대로 그린 것**만 씁니다(기존 `zplADibujo` 방식 유지, renderer 근사 계산 금지).

## 규모 · 검증
- 규모: **M** (renderer 편집기 + formatter 2개 함수 + 테스트 + 릴리스)
- 검증:
  - `test/qr-texto.test.js` 확장: 새 키 없음 → 기존 ZPL 과 동일(회귀 0) · `nombreFs/precioFs` 반영 · `^FB` 정렬 L/C/R ·
    2 por etiqueta 에서 사용자 크기 지정 시 클램프 해제 + QR 축소 경고
  - 돌연변이: `precioFs` 무시 / 정렬 무시 / 클램프 해제 조건 반전 → 테스트가 실패하는지
  - `test/qr-lote-cableado.smoke.js`: Etiquetas 인쇄가 **자동 저장된 `qrLayout`** 을 쓰는지(저장 버튼 없이)
  - 미리보기 좌표 = 인쇄 ZPL 의 `^FO` 좌표(같은 함수에서 나온 값) 대조
  - 실물: Cielo 와 같은 50×25 · 2 por etiqueta 로 «Prueba (1 fila)» 1회 출력 → 위치·스캔 확인 (중복 출력 없는지 로그 확인)

## 결정해 주실 점
1. **범위**: 권고안(드래그 + 크기·정렬 + 자동 저장, M) / 대안 B(편집기 이동 + 자동 저장만) / 대안 A(안내만)
2. **2 por etiqueta 에서 큰 글씨 허용**: 권고 = 사용자가 정하면 허용 + QR 축소 경고. 대안 = 지금처럼 12–16 고정
3. **PEDIDO 9 와 한 릴리스(v1.0.31)로 묶을지** — 권고: 묶음
4. **지금 대안 A 안내문을 먼저 매장에 보낼지** (구현 전 임시 해결)

## 구현 결과 (2026-10-06)
- 결정: 권고안(끌어서 옮기기 + 크기·정렬 + 자동 저장), 2 por etiqueta 에서 큰 글씨 허용 + QR 축소 경고. 릴리스는 #9 가 v1.0.31 을 먼저 써서 **v1.0.32**.
- zebra-agent `206ab6b`, 태그 **zebra-agent-v1.0.32** (Actions 성공, ventago-downloads 에 exe·dmg 2개). api·app·DB 변경 없음.
- 새 키 `nombreFs/precioFs/nombreAlign/precioAlign` — 없으면 ZPL 이 이전과 바이트 동일(120 조합 대조).
- 테스트: `qr-diseno-texto.test.js` 31 · `qr-diseno-cableado.smoke.js` 17(각 검사에 돌연변이 대조) · 기존 9개 통과. 돌연변이 8/8 잡힘.
- CODEX: 이중 클릭 이중 인쇄 창 · QR 탭 미저장분 인쇄 · 탭 간 덮어쓰기 · 저장 실패 시 인쇄 · 미리보기 행과 박스 불일치 → 전부 반영.
- 검증: 실제 formatter 를 붙인 로컬 서버로 renderer 를 브라우저에 띄워 마우스 드래그·화살표·Auto·크기·정렬·경고·저장 직후 인쇄(1회)·이중 클릭(대화상자 1개) 확인.
  **실물 프린터 출력은 미확인** — 매장에서 «Imprimir 1 de prueba» 로 위치·스캔 확인 필요.
