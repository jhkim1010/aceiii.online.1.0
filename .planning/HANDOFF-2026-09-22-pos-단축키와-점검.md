# 핸드오프 2026-09-22 — POS 단축키·티켓 footer·매뉴얼, 그리고 진행 중인 기능 점검

다음 세션은 **§5(미해결)** 부터 보면 된다. §1~§4 는 배포까지 끝났다.

---

## 1. 배포 완료 (운영 반영됨)

| 커밋 | 내용 |
|---|---|
| api `96a04308` · `e9972c1e` | AI 매뉴얼 11개를 코드와 대조해 수정 · `manual_ventas §11` 단축키 표 |
| api `60118c35` · `2db9478d` | 티켓 하단 문구(에이전트별) · **취소된 판매는 재인쇄 거절** |
| app `ec3c52d` | Sucursales › Agentes de Impresión 의 «Pie del ticket» 편집 |
| app `bca657e` · `d9d4831` | F8 복구 · Alt+T 재출력 · `de`/`rec` · 문서로 고객 검색 · auto impTiq 유지 (+CODEX P1 2건 수정) |
| app `a0c1316` | 담기/지우기 뒤 커서 → cantidad · 목록 화살표 되감기 해제 |
| app `2311f57` | **F1 단축키 목록 창** + 코드↔목록 동기화 시험 |
| app `69e0912` | ESC 로 비우기 전 확인 (i18n es/en/ko) |
| app `e3e434e` | Gestión de Precios 헤더 고정 (relative 가 sticky 를 덮고 있었다) |
| app `d0d2abf` | 권한 화면 — 행 0 인 블록 숨김 |
| app `59a8f36` · `e73a394` | **ESC 가드 오판** · **입력칸 안에서 죽어 있던 단축키 6개(F2 포함)** |

운영 실측(2026-09-22 저녁): 24시간 **5xx 0건**, 매뉴얼 지식 **110행**, Jenkins api #934 / front #770.

### 이번에 확인된 「같은 형태」 — 다음에도 먼저 의심할 것

1. **`useHotkeys` 에 `enableOnFormTags` 를 빠뜨리면 그 키는 죽는다.** POS 는 거의 항상
   입력칸에 커서가 있다. F8·F2·ESC·Ctrl+R·Ctrl+Q·F3·F11 이 전부 그 상태였다.
   ★ Ctrl+R 은 preventDefault 도 안 걸려 **브라우저가 새로고침**됐다.
   → 시험 `src/__tests__/pos-shortcuts-sync.spec.ts` 가 목록·코드·옵션 셋을 대조한다.
2. **`position: relative` 가 MUI `stickyHeader` 를 덮는다** (Precios 헤더).
3. **숨겨진 모달이 「열린 모달」로 읽힌다** — 좁은 창의 사이드바 Drawer 가
   `MuiModal-hidden` 으로 상주해 ESC 가드가 항상 참이었다. 창 너비에 따라 동작이 갈렸다.
4. **기능이 있는데 아무도 모른다** — Alt+B 는 4개월 동안 화면·매뉴얼 어디에도 없었다.
   새 단축키를 만들면 `utils/shortcuts.ts` 와 매뉴얼 §11 에 **같이** 적는다.

---

## 2. 기능 점검 진행 상황 (사용자 지시: 「최대한 점검하고 오류 목록을 만들어라」)

근거 문서: `.planning/CHECKLIST-2026-09-22-funciones.md` (369항목).
영역 4갈래로 재점검 중이었고 **§1 판매만 결과가 도착**했다. §2 상품·원자재·공방,
§3 관리·Tesorería·설정, §4 보고서·도구·로그인 은 **결과 미수령** — 다시 돌려야 한다.

---

## 3. §1 판매 — 확인된 결함 (미해결분만)

우선순위 순. 각 항목은 코드 근거가 있으나 **P1 두 건은 내가 직접 재확인하지 못했다.**

### P1-A. 판매 수정 중 Ctrl+S(보류) → 같은 판매가 복제될 수 있다
- `?editSale=` 로 수정 중에 Suspender 를 누르면 원본은 남고 보류 사본이 생긴다.
  그 보류를 복원해 F2 하면 **같은 물건이 두 번 팔린다**(재고도 두 번 빠진다).
- 근거: `ProductList.tsx` `handleSuspend` 에 `editingSaleId` 검사 없음
  (같은 함수가 `deudaPagoLine` 은 거절한다). 수정 여부 확인은 `handleSubmit` 에만 있다.
- ★ 오늘 만든 비우기 확인창이 「지우지 말고 Suspender 를 쓰세요」라고 **권한다** —
  「Cancelar modificación」 버튼에서도 같은 창이 뜬다.
- 방향: `handleSuspend` 첫머리에서 `editingSaleId` 면 거절 + 확인창 힌트를 그때는 감춘다.

### P1-B. 앱 전체에서 Ctrl+V 붙여넣기가 막혀 있다
- `UserLayout.tsx:69` 의 fichaje QR 단축키가 `preventDefault` + `enableOnFormTags` 라
  **입력칸 안에서도** 돌아 붙여넣기를 가로챈다.
- ★ 오늘 그 키를 F1 목록에 정식으로 실었다 — 지금은 「의도된 동작」으로 문서화된 상태다.
- 방향: 입력칸에서는 빼거나 키를 옮긴다(Ctrl+Alt+V 등). **사용자 결정 필요.**

### P2
- **스캔 경로만 포커스 통일에서 빠졌다**: `ProductsInputs.tsx:500-501` 이 아직
  `getElementById('input-cantidad')?.focus()` — `select()` 가 없어 수량을 치면 `31` 이 된다.
  나머지 네 경로는 `focusCantidad()` 로 통일돼 있다. → 한 줄 교체.
- **두 번째 `de`/`rec` 가 조용히 무시된다**: 이름이 `'Descuento'` 로 고정이라
  `discounts.some(d => d.name === …)` 에서 중복으로 걸려 아무 말 없이 끝난다.
- **auto impTiq 체크박스가 프린터 없으면 disabled** (`ProductList.tsx:2858`) —
  오늘 만든 「거부하지 않고 경고만」 분기가 **도달 불가능한 죽은 코드**다.
- **취소 확인창 금액이 콜롬비아 페소**: `SaleReviewPanel.tsx:235` `es-CO`/`COP` → `es-AR`/`ARS`.

### P3
- 색/사이즈 그리드 활성 상태에서 「+」가 이유 없이 무반응(`ProductsInputs.tsx:600`).
- 「Agregar」 버튼이 실제로는 권한 승인 모달을 연다(라벨과 동작 불일치).
- 재인쇄 권한 오류가 **500 + axios 원문**: `sales.controller.ts:313` 이 `throw new Error`
  (HttpException 아님) → `ForbiddenException` 으로.
- 판매 검증 실패 토스트가 **문자열 배열**을 그대로 붙여 보여 준다(`ProductList.tsx:2074`).

### 이상 없음으로 확인된 것
이중 제출 차단(생성·수정 각각), Alt+T 의 범위·연타·취소판매 거절, draft 에 `editingSaleId`
동반 저장, 비우기 확인창의 ESC=취소, i18n 키 3개 언어, 회수(`dp`) 양방향 차단.

---

## 3-B. §4 보고서 · 도구 · 로그인 — 확인된 결함 (전부 미해결)

실측으로 확정된 전제 2개: **운영 API 컨테이너는 UTC**(`docker exec api_ventago date` → `TZ=` 빈 값),
운영 `afip_vouchers` **21건 중 4건이 AR 달력일 ≠ UTC 달력일**.

### P1
1. **AFIP 발급분이 「오늘」 목록에서 사라진다** — Emitidas 날짜창이 UTC 로 잘린다.
   AR 21:00 이후 발급분이 그날 목록에 없고 전날 것이 섞인다(그 전표는 재출력·PDF·NC/ND 불가).
   `afip-query.service.ts:363-367` · 기본값 `afip.controller.ts:994`.
   ★ 같은 모듈 `afip-iibb.service.ts:8-11` 은 이미 `AT TIME ZONE` 을 쓴다 — **이 조회만 빠졌다.**
2. **Ventas 보고서의 검색어가 코드로 지워진다** — KPI·트렌드·지점표·Mix·목록 전부 무반응.
   `SalesCockpitDetail.tsx:502-507` → `useSalesCockpitDetail.tsx:132` 이 `filter=''` 로 덮는다.
3. **발급 모달에서 Enter 한 번이 곧 CAE 발행.** `PartialInvoiceModal.tsx:382-398` 의 window keydown 에
   `e.target` 검사가 없다. CAE 는 되돌릴 수 없다(NC 를 따로 끊어야 한다).

### P2 (요약 — 상세는 이 세션의 §4 보고)
- **Excel 내보내기 15/18 이 영구 비활성인데 백엔드 엔드포인트는 이미 있다**(배선만 누락).
- **Enviado 보고서 권한 마이그레이션이 `role_functions` 를 안 넣었다** — 실측: store 3·8 admin 과
  4개 매장 gerente 전원이 그 보고서를 못 본다.
- **`/facturacion` 의 vendedor 차단이 프론트 전용** — 서버도 vendedor 를 허용해 고객 DNI·CAE 가 노출된다.
  ★ 고치려면 **API·프론트를 같이 배포**해야 한다(한쪽만 나가면 403/400).
- 등록(sucursal/terminal) 모달이 **실패하면 닫혀서 사용자가 갇힌다** — sessionToken 없이 전 요청 401.
- **비밀번호 재설정 기능이 없다** — CTA 만 있고 백엔드 엔드포인트 0건. 지원 연락처도 플레이스홀더 번호.
- 스페인어 화면에 **한국어 내부 문구**가 그대로(부분발급 초과 경고는 일상 경로) · 원 예외 메시지 노출.
- **필터가 쿼리에 안 실리는 보고서 4건**(season-turnover, stocks Panel A/B 불일치, clientes-credito, ventas).
- **AI 도우미**: Ollama provider 가 **대화 기록을 버린다**(후속 질문에 맥락 없음) ·
  **LLM 오류 문구가 assistant 메시지로 DB 에 영구 저장**된다.
- **팀 채팅 `Grupo General` 전송 제한이 프론트 전용**(서버 검사 0건).

### 입구가 없는 실기능 3건 (나머지는 dead code/중복 래퍼로 판정)
`/reportes/asistencia`(근태 — 백엔드 완비) · `/admin/vto`(superadmin 과금) ·
`/configuracion/carpetas-compartidas/logs`(접근 감사).

### 코드만으로 확인 못 한 것
Select 에서 Enter 버블링 범위 · 운영 프론트 빌드의 `NEXT_PUBLIC_ENABLE_REMOTE_SUPPORT` 주입 여부 ·
**신규 매장 provisioning 이 보고서 권한을 복제하는지**(템플릿 role 은 18개 보고서 권한이 0건) ·
vendedor 계정 없이는 권한 관련 항목을 화면에서 못 잰다.

---

## 3-D. §2 상품 · 원자재 · 공방 — 확인된 결함 (전부 미해결)

기존 「이상」 13건 **전부 여전히**. 오늘의 헤더 sticky 수정에 **회귀 없음**(손잡이 정상).
오늘 고쳐진 것 1건 확인: 「선택 없으면 전체에 일괄 적용」은 이제 경고 후 중단한다.

### P1 (돈·재고가 틀어지는 것 위주)
- **「Descripción por WEB」이 기존 상품에서 저장되지 않는다** — 입력 후 Modificar 를 누르면
  **초록색** «No hay cambios para actualizar» 가 뜨고 버려진다(diff 가 stock/price/base/sku 4종뿐).
- **Talleres 목록이 말없이 10건에서 잘린다** — `pageSize` 미지정 → 서버 기본 10.
  11번째 로트·발송은 목록·검색·Excel 어디에도 없고, **그 잘린 목록으로 진행률을 계산**해
  오래된 로트가 0으로 보인다. 공방도 11번째부터는 발송·정산 대상에서 사라진다.
- **정산에서 그 날짜 단가가 없으면 수령분이 조용히 빠진다 → 공방 과소 지급**(신호 0건).
- **Inventario 편집 저장이 재고 원장을 무시하고 `currentStock` 을 덮어쓴다**(lost update).
- **Proveedor 없이 「Fiado」 입고 가능** → 아무도 못 갚는 외상 + 결제 시 500.
- **Cut Ticket 매트릭스**: 칸을 비우면 0 이 저장되고, 저장 대기 중 갱신이 타이핑을 덮어쓴다.
- **재고 리포트에서 이동/불량 셀 → `/ventas` 로 가면 상품 필터가 사라진다**(좁히는 필터가 전체로).
- 레거시 `/talleres/lotes` 는 **없는 라우트**(`/production/materials`)를 불러 화면이 통째로 빈다.

### P2 (숫자가 갈라지거나 조용히 틀리는 것)
- **/precios: 필터를 바꿔도 선택이 남는다** → 화면에 없는 상품에 일괄 조정이 나간다.
- **가격 저장이 실패해도 화면은 새 가격을 보여 준다**(롤백·재조회 없음) · 개별 저장이 **센타보를 버린다**.
- **Stocks Panel A 가 필터를 반영하지 않는다** → 표와 KPI 가 다른 모집단.
- **「오늘」이 UTC 달력**(원자재 3화면) — 21시 이후 등록이 내일로 잡힌다.
- 외상 공식이 두 벌이라 Dashboard 와 Pagos 총액이 갈라질 수 있다 · 「Proveedor activo」 체크박스 무동작 ·
  「Pagado Este Mes」가 현재 페이지 20행만 합산 · 부모 원단이 재고에 «Agotado» 로 섞인다.
- **커밋 후 재조회 실패를 「쓰기 실패」로 보고** → 사용자가 결제를 다시 넣게 만든다(4화면 동형).
- QC 탭은 **없는 라우트**를 불러 영구 공백.

---

## 4. 오늘 만든 것 중 다음 세션이 알아야 할 자리

- `ventago-app/src/views/homes/utils/` — `shortcuts.ts`(단축키 목록의 단일 출처) ·
  `focus-pos.ts`(커서 복귀) · `clear-sale.ts`(비우기 확인 + 모달/목록 가드) ·
  `quick-adjust.ts`(`de`/`rec` + `parseQuantity`) · `last-sale.ts`(Alt+T 대상).
- `api-ventago/src/app/print/ticket-footer.ts` — 티켓 하단 문구 규칙의 단일 출처.
  **오프라인(edge) 인쇄에는 아직 안 붙는다**(CODEX P2, 미해결 — edge 동기화 자료에 실어야 함).
- 시험: `pos-shortcuts-sync` · `pos-clear-confirm` · `pos-focus` ·
  `pos-quick-adjust-last-sale` · `precios-sticky-header` (app),
  `ticket-footer` · `footer-callsites` · `thermal-target-footer` · `manual-sync.service` (api).

---

## 5. 미해결 · 다음 할 일

1. **§2(상품·원자재·공방)·§3(관리·Tesorería·설정) 재점검을 다시 돌린다.**
   §1·§4 는 끝났다(위). 프롬프트 형식은 같게: 체크리스트의 기존 「이상」 재판정 +
   새 결함을 `file:line` 근거로.
1-b. §4 의 **P1 3건을 먼저 고친다.** 1번(UTC 날짜창)은 이미 운영에서 19%가 어긋나 있고,
   3번(Enter 로 CAE 발행)은 되돌릴 수 없는 조작이다.
2. §1 의 **P1-A**(보류로 판매 복제)를 직접 재확인하고 고친다. **가장 위험하다.**
3. §1 **P1-B**(Ctrl+V) 는 사용자 결정을 받는다 — 키를 옮길지, 입력칸에서 뺄지.
4. P2 4건은 한 커밋으로 묶어도 된다.
5. **Phase 92**(ARCA 발급분 vs 수령분) — 계획만 있고 **코드는 2026-10 에**.
   착수 1번은 코드가 아니라 실제 「Mis Comprobantes」 파일 확보다.
   문서 `.planning/phases/92-arca-balance-emitidos-recibidos/92-CONTEXT.md`,
   mockup https://claude.ai/artifact/GreadkC8Y2GccrbDKXzG7S
6. print-agent 를 새로 빌드해 매장 PC 에 설치해야 **티켓 footer 가 실제로 찍힌다**
   (구버전은 새 필드를 무시할 뿐 깨지지는 않는다).

★ 운영 확인 절차: push → Jenkins(api-new-coolsistema / front-coolsistema) 성공 확인 →
  브라우저 **강력 새로고침**. 오늘 「배포가 안 됐다」고 본 것은 전부 캐시였다.
