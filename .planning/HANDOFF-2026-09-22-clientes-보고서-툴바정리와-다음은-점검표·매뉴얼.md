# 핸드오프 2026-09-22 — Clientes 보고서 · 툴바 정리 · 다음은 점검표·AI 자료·매뉴얼

앞 핸드오프: `HANDOFF-2026-09-21-pos-단축키와-ws-개통.md`
목업: https://claude.ai/code/artifact/06a5572c-1b0b-4d22-b234-404cdabdc656 (Clientes 두 얼굴)
    https://claude.ai/code/artifact/417c445e-ee2e-481e-acc8-316aaaaf7566 (Clientes 화면 분리안)

---

## 0. 한 줄

**오늘 한 것은 전부 운영에 나가 있다**(마지막 front #761 만 이 문서 작성 시점에 빌드 중 —
커밋 `3219faf` 를 grep 해서 결과를 확인할 것). **다음 세션의 본 작업은 §3** 이다.

---

## 1. 오늘 배포된 것

| 내용 | 커밋 | 빌드 |
|---|---|---|
| POS 「CodigosMadres」 체크박스 제거 | app `0f2ff49` | front #754 |
| AI 도우미 상시 아이콘 · 직원 채팅은 안 읽음/사이드바 «Chat de equipo» 때만 | app `55ad5d7` | #755 |
| POS 코드 없는 판매(tmp) 코드 칸 열기 · **비우면 SKU 판매로 복귀** | app `88c7b7c` | #755 |
| Guía de configuración 에 「Producción externa y materia prima」 선택 섹션(6항목, 분모 8 불변) | api `c0585fac` · app `e103ad2` | #924 · #756 |
| `/manuales` 에서 전역 AI 아이콘 숨김(페이지 자체 채팅과 중복) | app `e2bf728` | #756 |
| ClienteVista 이름 한 줄 · 표 글자 크기 통일 | app `b80335b` | #757 |
| ClienteVista **Eliminados**(소프트 삭제 고객 조회) · 카드 숫자 서버 집계 · 표 높이 자동 | api `3138dc48` · app `3e7aae8` | #925 · #757 |
| 「Historial」 → Carga Masiva 화면으로 | app `df9dbbe` | #758 |
| Reportes **Clientes**: «Crédito solo» 체크박스 + 달력(해제=기간 중 구매 이력) | api `ea8b563f` · app `86e66dd` | #926 · #759 |
| 「Configurar Campañas」 → Configuración 허브 탭 | app `6a877d5` | #760 |
| reports-v2 레지스트리 변수 이름 17건 = 실제 파일 이름 | app `3cc1782` | #760 |
| Alertas 달력 **되돌림** · 탭 제목 사본 수정 | app `3219faf` | #761 (확인 필요) |

---

## 2. ★ 남은 것

| | 내용 | 상태 |
|---|---|---|
| **A** | **ProductBranch 없는 활성 상품 76건** → Zebra 라벨 인쇄 404(`products.service.ts getProductsForPrintCodes`). 원인: `create()` 가 PB 를 안 만든다. POS 판매는 막지 않는다(실증) | 미착수 — 09-21 핸드오프 §5-A |
| **B** | CODEX P2 — CUIT 귀속 검사에 잠금 없음(`pg_advisory_xact_lock`) | 미착수 |
| C | **`/configuracion/carpetas-compartidas` + `/logs` 진입점 0건**(허브·사이드바·링크 모두 없음). 기능 본체 `/carpetas-compartidas` 는 사이드바에 있다. 허브 탭으로 넣을지 **사용 여부 확인 후** 결정 | 사용자 판단 대기 |
| D | **기준일(`asOfDate`) 필터** — 달력 없는 3개(Alertas · Stocks · Stock Vistas)는 전부 현재 스냅샷이라 기간이 아니라 기준일이 맞다. 백엔드가 기준일 계산을 지원하는지부터 확인 | 제안만 |
| E | **NOIX(branch 28) 영수증이 안 나온다** — 감열 에이전트 2대(`caja`,`caja1`)인데 터미널 매핑 0 → `ambiguous_target`. 코드 결함 아님, `/sucursales/28/impresora` 에서 매핑하면 끝 | 사용자 조치 |
| F | 사용자가 브라우저 순회 중 본 **오류 메시지 재현 못 함**. JS 오류 0 · 알림 0. 연속 페이지 이동 중 끊긴 요청의 일시 알림일 **가능성**(미확인) | 문구 받으면 추적 |
| G | **오늘 커밋들에 CODEX 자문을 돌리지 않았다.** 훅은 자동으로 안 뜬다(메모리 참조) — 필요하면 손으로 | 미실시 |

---

## 3. ★★ 다음 세션 본 작업 — 기능 점검표 · AI 학습 자료 · 고객 매뉴얼

사용자 요청(원문): *"모든 시스템 기능을 확인, 테스트 할 리스트를 만들고, 특히 AI 에게 학습시킬
자료 및 매뉴얼로 고객들에게 제공할 파일을 만들도록 해줘."*

**순서가 요점이다: ① → ② → ③.** 점검표로 「실제로 있고 동작하는 것」을 먼저 확정해야
매뉴얼이 없는 메뉴·없는 페이지를 안내하지 않는다(이 저장소가 여러 번 겪은 막다른 CTA).

### ① 기능 점검표
- **손으로 목록을 쓰지 말고 기계로 뽑는다**: `src/navigation/menuRegistry.ts`(사이드바) ·
  `src/pages/configuracion/index.tsx`(허브 탭 16) · `src/views/reports-v2/registry.ts`(보고서 18) ·
  `src/pages/**`(실재 페이지) + DB 모듈(`apps`/`modules`/`store_apps`).
- 항목마다: 어디서 여는가 · 무엇을 누르는가 · 무엇이 나와야 하는가 · 권한(역할).
- 검증은 cmux browser(운영 사이트, 사용자 로그인) — 오늘 보고서 18개를 이 방식으로 돌렸다.
  탐침 스크립트 예: scratchpad `revisar.sh` 패턴(`goto` → `eval` 로 DOM 세기).
  ★ 탐침 자체를 대조군으로 확인할 것 — 오늘 `errors list` 문구를 grep 이 세어 **전 항목
    오탐**이 났다.

### ② AI 학습 자료
- 대상: 사내 AI 도우미(`api-ventago/src/app/chat/` Knowledge base). **먼저 현재 KB 가
  무엇을 어떤 형식으로 읽는지 확인**하고 그 형식에 맞춘다.
- 기능당 1건: 무엇을 하는가 · 절차 · 흔한 질문 · 하지 말아야 할 것(예: 열린 카하 다시 열지 않음).
- 근거는 ①에서 확인된 화면 + 코드의 실제 동작. 추측 금지.

### ③ 고객 매뉴얼
- 이미 `/manuales`(`ventago-app/public/manuales/manifest.json`)에 ES·KO docx 6종이 있다
  (Ventas · Producto · Admin · Stock · MateriaPrima · Talleres). **새로 만들기 전에 낡은 부분부터**
  대조 — 오늘 바뀐 것(Clientes 보고서, Eliminados, 단축키, Campañas 위치 등)이 반영 안 돼 있다.
- 역할별(판매원 · 관리자). 형식은 사용자에게 확인(docx 유지 vs 화면 안 HTML).

---

## 4. 이번 세션에 뒤집힌 전제

1. **「NOIX 상품이 PB 가 없어 안 팔린다」 → 틀렸다.** POS 목록은 PB 를 조인하지 않는다. 그날 실제로 팔렸다.
2. **`clients.is_active` 는 활성 플래그가 아니라 소프트 삭제 표시다.** 그래서 「Inactivos」는 구조적으로 영원히 0 이었다.
3. **ClienteVista 와 Clientes 보고서는 다른 테이블을 본다** — `clients` vs `store_clients`+`global_clients`.
   대응은 부분적(6: 29중 19 · 9: 47중 23 · 19: 511중 507). `global_clients` 에 같은 문서번호가 여럿 → 조인하면 행이 불어난다.
4. **판매의 34%(coolsistema)~88%(NOIX)에 고객이 없다.** 고객 기준 보고서 합계는 매장 총매출이 아니다.
5. **「경보는 사건이라 기간이 맞다」 → 틀렸다(내 추정).** Alertas 는 재고 상태 스냅샷, 백엔드는 날짜를 안 읽는다.
6. **reports-v2 레지스트리의 `XReportBody` 는 `XCockpitBody` 를 가리켰다(17건).** 안 쓰이는 레거시 파일을 고칠 뻔했다. 이제 시험이 대조한다.
7. **사본은 갈라진다** — `_app.tsx` 탭 제목 표가 registry 를 베낀 사본이었고 이미 2건 빠져 있었다.
8. **오늘의 반복 형태(4회)**: 눌러도 아무 일 없는 컨트롤 · 이름이 자리를 배신 · 설정이 운영 화면 툴바에.
   하나를 찾으면 **기계로 전수**를 셀 것 — 단, 그 기계(스캔 스크립트)도 틀린다(경로 오탐 2건).

---

## 5. 검증 상태

app `__tests__` **47 suites / 518 tests** · tsc 0 · eslint 0.
api setup-guide 5/65 · clients 6/36 · reports 10/117. 오늘 새 시험은 전부 돌연변이로 죽는 것을 확인했다.
운영 브라우저 순회(front #760): 보고서 18개 전부 렌더 · 오류 UI 0 · JS 오류 0.
