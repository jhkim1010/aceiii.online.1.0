# Phase 20: Nueva Venta Variation/CodigoMadre 디버깅 - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Nueva Venta의 variation(사이즈/색상) 렌더링 및 codigoMadre 수량 전달 오류를 진단하기 위한 **관찰 가능한 로깅 인프라**를 구축한다.

**이 phase가 전달하는 것:**
- 판매 한 건을 끝까지 추적할 수 있는 **UUID 기반 traceId**
- 프론트(브라우저 console + ventago-app 서버 winston) 와 백엔드(api-ventago winston + 콘솔) 양측에서 일관된 로그 라인
- traceId 가 판매 흐름의 모든 레이어(프론트 상태 변경 → /sales 호출 → /suspended-sales save/restore → print-agent 전송)에 전파되어, 한 번의 판매 세션을 관통 검색(grep)으로 재구성할 수 있음

**이 phase가 전달하지 않는 것 (Deferred):**
- 근본 원인 수정 (ProductList.tsx:201 에 기록된 "첫 parent만 타겟" 버그 fix는 다음 phase)
- Print-agent 티켓에 디버그 정보 출력 (payload에 traceId는 포함하되, 티켓 출력물 변경은 없음)
- Suspender/restore 데이터 스키마 변경
- 활성화 스위치/토글 (운영에서도 그대로 로깅 — 로그 레벨만 winston config 로 제어)

</domain>

<decisions>
## Implementation Decisions

### 로그 경로 & 지속성 (Area 1)

- **D-01:** 백엔드(api-ventago)는 기존 `nest-winston` 로거를 `sales-create.service`, `suspended-sales.service`, `print.service` 에 주입해 사용. 출력은 기존 winston config 그대로 — **콘솔 + `logs/combined-%DATE%.log` 일별 로테이션** 양쪽에 기록됨 (운영 도커 컨테이너에서도 동일하게 동작).
- **D-02:** 프론트엔드(ventago-app)의 브라우저 측은 **기존 `console.warn('[VARIATION-BUG]', ...)` 패턴을 그대로 유지**하되, 로그 라인 앞에 traceId 를 추가한다.
- **D-03:** 브라우저 로그를 서버에도 남기기 위해 ventago-app 에 **Next.js API route `/api/debug/variation-log`** 를 추가한다. 브라우저 `[VARIATION-BUG]` 로그는 non-blocking `fetch` 로 이 엔드포인트에 POST 되고, Next.js 측은 **ventago-app 전용 winston 인스턴스**를 통해 `ventago-app/logs/variation-debug-%DATE%.log` 와 Next.js 서버 콘솔 양쪽에 기록한다.
- **D-04:** "로컬에서 실행하면 로컬 winston/콘솔에, 서버에서 실행하면 서버 winston/콘솔에" — dev.sh 로컬 실행이든 Docker 컨테이너 실행이든 동일한 winston 설정(콘솔 transport + DailyRotateFile transport) 을 사용하므로 **실행 위치에 따라 자동으로 해당 환경의 파일/콘솔에 로그가 남는다**. 별도 환경 분기 코드 없음.
- **D-05:** 로그 전송 실패(백엔드 debug 엔드포인트 다운 등) 는 **silent swallow** — nueva-venta 작업을 절대 방해하지 않는다. 재시도/큐잉 없음.

### Trace ID (Area 2)

- **D-06:** 판매 세션(nueva-venta 화면) 진입 시 **`crypto.randomUUID()` 로 UUID v4 traceId 생성**. `SaleProductsContext` 에 저장. 판매가 완료(결제 성공) 되거나 `resetSale()` 호출 시 **새 UUID로 회전**.
- **D-07:** Suspender 에서 restore 되는 판매는 **원 traceId를 복구하지 않는다** — 복구 시점에 새 UUID 발급. 단, 로그에 `restoredFromSuspendedSaleId=<id>` 를 함께 기록해서 상관관계를 남긴다.
- **D-08:** 프론트 → 백엔드 전파: 모든 판매 관련 HTTP 요청(`POST /sales`, `POST /suspended-sales`, `GET /suspended-sales/:id`, `DELETE /suspended-sales/:id`, `POST /debug/variation-log`) 에 **`X-Trace-Id` 헤더**로 전달. `apiConnector` 에 axios interceptor 추가하여 자동 주입(SaleProductsContext 에서 읽어서 헤더에 얹음).
- **D-09:** 백엔드 → print-agent 전파: `print.service` 가 print-agent 로 emit 하는 **`print_invoice` payload 에 `traceId` 필드 추가**. print-agent 는 이 traceId 를 자신의 console.log 에 찍는다 (티켓 출력물은 건드리지 않음).
- **D-10:** 로그 라인 공통 포맷(문화적 공통 키): `{ traceId, userId, storeId, branchId, terminalId, event, phase, payload }`. winston logFormat 에 이 키들이 노출되도록 구조화 로그 객체로 넘긴다 (기존 `logFormat` 의 `message` 파라미터에 JSON stringify 로 직렬화).

### 로그 이벤트 — 어떤 지점에 찍을지 (Area 1+2 종합)

프론트엔드 (브라우저 console + ventago-app winston):
- **E-F-01** `nueva_venta.mounted` — traceId 발급 직후
- **E-F-02** `nueva_venta.product_selected` — ProductsInputs.handleProductChange (codigoMadre 선택 시 context 덮어씀 시점)
- **E-F-03** `nueva_venta.variant_quantity_changed` — VariantsStockVenta 수량 입력
- **E-F-04** `nueva_venta.add_to_cart` — handleAddToCart 시작/종료. **cart 의 어떤 parent 에 더해졌는지 codigoMadre 를 반드시 로그에 포함** (근본 원인 관찰 지점)
- **E-F-05** `nueva_venta.cart_row_click` — 좌측 cart 행 클릭 (variant 그리드 복원)
- **E-F-06** `nueva_venta.suspender_save` — /suspended-sales POST 직전 payload
- **E-F-07** `nueva_venta.suspender_restore` — /suspended-sales/:id GET 후 context 로 복원되는 값
- **E-F-08** `nueva_venta.sale_submit` — /sales POST 직전 payload

백엔드 api-ventago (winston):
- **E-B-01** `sales.create.received` — sales.controller 진입, traceId + req.body 요약
- **E-B-02** `sales.create.items_resolved` — sales-create.service 에서 itemId → variant 해석 결과
- **E-B-03** `sales.create.persisted` — sale 저장 완료 후 sale.id
- **E-B-04** `suspended_sales.create.received` — suspended-sales.controller POST
- **E-B-05** `suspended_sales.restore.delivered` — suspended-sales.controller GET /:id 응답 payload 요약
- **E-B-06** `print.invoice.emitted` — print.service 가 print-agent 로 emit 직전 payload 요약(+ traceId)

Print-agent (electron console + electron-log 있으면 그쪽):
- **E-P-01** `print_invoice.received` — WebSocket 수신 직후 traceId + itemCount
- **E-P-02** `print_invoice.rendered` — HTML→PNG 완료

### Claude's Discretion

- 프론트 로그 배치 전송(debounce) 여부는 planner 판단 — 기본은 개별 즉시 전송(fire-and-forget fetch), payload 가 작으므로 성능 무시 가능.
- ventago-app 측 winston 설정 파일의 위치/포맷(api-ventago 의 `logger.config.ts` 를 참고해서 동일한 DailyRotateFile + Console transport 구성) 은 planner 가 결정.
- `/api/debug/variation-log` 엔드포인트의 rate-limit / payload size cap 은 planner 가 기본값으로 설정(예: 10KB cap, store 인증 체크만).
- print-agent 의 로그 출력을 electron-log 로 할지 기본 console 로 할지 — planner 가 의존성 확인 후 결정.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### 프로젝트 규약
- `CLAUDE.md` — ESLint 규칙(newline-before-return, lines-around-comment), apiConnector 사용 규약, 성능 최적화 규약, Winston 로깅 언급
- `.planning/codebase/CONVENTIONS.md` — 코드 컨벤션
- `.planning/codebase/STACK.md` — 기술 스택 레퍼런스
- `.planning/PROJECT.md` — 프로젝트 비전

### Frontend — 문제가 발생하는 현장
- `ventago-app/src/views/homes/components/ProductList/ProductList.tsx` — 좌측 cart 클릭 로직, 이미 [VARIATION-BUG] 마커 다수 (**특히 L201 주석이 근본 원인 기록**)
- `ventago-app/src/views/homes/components/ProductList/components/ProductsInputs.tsx` — codigoMadre 선택 시 context 덮어쓰는 지점
- `ventago-app/src/views/homes/components/ProductList/components/VariantsStockVenta.tsx` — variant 수량 입력 그리드
- `ventago-app/src/views/homes/hook/SaleProductsContext.tsx` — 판매 세션 상태 보관소 (traceId 저장 위치)
- `ventago-app/src/views/homes/components/DraftAndDebtors/DraftAndDebtorsList.tsx` — suspender/restore UI
- `ventago-app/src/services/api.service.ts` — apiConnector 정의 (interceptor 추가 지점)

### Backend — 로거 주입 대상
- `api-ventago/src/common/logger/logger.config.ts` — winston 설정 (Console + DailyRotateFile, 로그 포맷 참고)
- `api-ventago/src/app/sales/sales.controller.ts`, `sales/sales-create.service.ts`, `sales/sales.service.ts`
- `api-ventago/src/app/suspended-sales/suspended-sales.controller.ts`, `suspended-sales/suspended-sales.service.ts`
- `api-ventago/src/app/print/print.service.ts` — print-agent emit 지점

### Print-agent
- `print-agent/main.js` — L582 `wsConnection.on('print_invoice', ...)` 수신 핸들러
- `print-agent/src/print-pipeline.js` — 파이프라인 진입점
- `print-agent/src/formatter.js` — data 스키마 문서(헤더 주석)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **winston (nest-winston)**: api-ventago 에 이미 Console + DailyRotateFile transport 로 셋업됨 → 추가 설정 없이 `@Inject(WINSTON_MODULE_NEST_PROVIDER)` 로 로거만 주입하면 됨.
- **[VARIATION-BUG] 기존 console.warn 마커**: ProductList / ProductsInputs / VariantsStockVenta 에 이미 심어져 있음 → 삭제하지 말고 **traceId 를 prefix 에 추가하는 방식으로 enhance**.
- **apiConnector (axios 기반)**: 요청 interceptor 를 추가해 `X-Trace-Id` 헤더를 자동 주입하기 용이.
- **SaleProductsContext**: 판매 세션 단위 상태가 이미 여기에 모임 → traceId 저장처로 자연스러움.

### Established Patterns
- winston logFormat: `${timestamp} [${level}] [${context}] ${message}` — 구조화 로그를 넣으려면 message 에 JSON.stringify 된 객체를 넘기는 관례.
- Controller/Service 에서 Logger 주입 방식: `constructor(@Inject(WINSTON_MODULE_NEST_PROVIDER) private readonly logger: Logger)`.
- 프론트 디버그 로그는 console.warn + 이모지 prefix + `[태그]` 관례 사용 중 (유지).

### Integration Points
- 브라우저 로그 → Next.js API route → 파일 기록: ventago-app 에 현재 API route 디렉토리가 사실상 비어있음 (`pages/api/` 는 `web-vitals.ts` 정도). 신규 라우트 추가 마찰 없음.
- `X-Trace-Id` 헤더는 이미 세션 보안에서 `x-session-token` 을 같은 방식으로 얹는 선례가 있음 (api.service.ts) — 동일 패턴 복제.
- print-agent payload 에 traceId 필드 추가는 파괴적 변경 아님(없으면 undefined로 처리되어 기존 운영 호환).

</code_context>

<specifics>
## Specific Ideas

- 사용자 원문: "suspender 시킨 다음에 다시 부르면 더 오류가 심할 것 같아" — suspender/restore 경로의 로깅을 특별히 촘촘하게 남길 것 (E-F-06, E-F-07, E-B-04, E-B-05 가 같은 traceId 로 묶이면 안 되고 `restoredFromSuspendedSaleId` 상관관계 키로 연결).
- ProductList.tsx:201 주석("handleAddToCart는 항상 cart의 첫 parent를 타겟으로 함") 은 근본 원인 가설 — 이 phase의 로그는 이 가설을 **증명/반증** 할 수 있어야 한다 (E-F-04 이벤트가 "선택된 codigoMadre vs 실제 수량이 더해진 parent의 codigoMadre" 를 둘 다 기록).

</specifics>

<deferred>
## Deferred Ideas

다음 phase 후보 (Area 3~6 은 이 phase 범위 밖):
- **근본 원인 수정** (Area 5): variation 렌더링 버그 & handleAddToCart 의 "첫 parent 타겟" 버그 실제 fix. 이 phase 로그로 수집된 증거 기반으로 진행.
- **Suspender/restore 데이터 무결성 수정** (Area 3): suspended_sales 스키마 또는 보존 로직 변경.
- **Print-agent 티켓에 디버그 정보 출력** (Area 4): formatInvoiceHtml 스키마 확장, 디버그 footer, 별도 debug 티켓 이벤트.
- **활성화 스위치/토글** (Area 6): 환경변수/DB flag/쿼리 파라미터 기반 debug on/off — 지금은 항상 로깅, 용량 문제 생기면 그때 도입.

</deferred>

---

*Phase: 20-nueva-venta-variation-codigo-madre-print-agent-suspender-res*
*Context gathered: 2026-04-17*
