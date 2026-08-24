# 핸드오프 — 2026-08-24 · Phase 86 착수 (스트리밍 · 재고 · 하네스) ★

`HANDOFF-2026-08-23-phase85-w6c3-실행기.md` 에서 이어짐.
**긴 세션이었다** — Phase 85 마무리 → 결제 경로 보안 2건 → Phase 86 착수까지.

---

## ★★ 이 세션의 한 줄

**설계 문서가 한 매장만 보고 쓰여 있었고, 다른 매장을 실제로 복원해 재 보니
전제 두 개가 무너졌다. 그리고 내가 쓴 검사 여럿이 대조군을 통과했다 —
아무것도 안 지키고 있었다.**

---

## 배포 (전부 SUCCESS)

```
api-ventago  12145e9  MP OAuth 매장 귀속 (보안)              #802
             b932170  환불 원장 판매 귀속 (보안 HIGH)        #803
             636bfba  Phase 86 착수 — M1~M7 + 상한 50MB      #805
             fb9fa35  상한 65MB (85 는 실측이 막는다)        #805
             423b380  TASK-2b′ ① 스트리밍 리더               #807
             2a0821c  TASK-2b′ ② 재고 SQL 재현
             3ffdd3b  TASK-2b′ ③ staging + 관통
             f291958  더미 매장 관통 검증                     #808
             4157181  clientes — DNI 가 유일한 키
             765169c  임포트 하네스
ventago-app  5da0b0e / d59fcb7 / 5a97eb3                      #681, #683
운영 DB      mp_oauth_states · uq_mp_accounts_active_scope
             phase86 M1~M7 (로컬 5432 + 운영 5434 + 스테이징)
```

---

## ① 결제 경로 보안 2건 (Phase 86 과 분리 — 사용자 지시)

상세는 `HANDOFF-2026-08-23-...md` 하단. 요약:

- **MP OAuth**: `start?storeId=B` 로 **남의 매장 결제 수취 계정을 갈아끼울 수 있었다.**
  콜백이 `@Public()` 이라 전역 테넌트 가드가 no-op 인 자리. 운영 `mp_accounts` 0행.
  → 인가를 `start` 에서 하고 결과를 `mp_oauth_states` 행에 적는다(단일 사용).
  ★ 실측으로 codex 가정보다 나쁜 것을 찾았다: `mp_accounts` 에 **활성 유일 제약이
    아예 없어** 어느 계정이 대금을 받는지 비결정적이었다 → `NULLS NOT DISTINCT` 인덱스.
- **환불 원장**: `:saleId` 무검사로 **남의 매장 판매에 환불 원장**을 찍을 수 있었다.
  `mp_refunds`/`mp_refund_attempts` 는 `store_id` 가 없고 파생 훅이 **읽기만** 덮는다.
  → 네 축(가시성·관계·정합성·요청자 인가). ★ codex 가 내 과장을 잡았다 —
    정합성 축을 "인가 축" 이라 적었다.

**남은 MP 부채(MED)**: `disconnect`·`qr`·`payment-intents`·`wallets/:id/movements` 가
전역 가드에만 의존. `POST /qr` 은 같은 매장 **다른 지점** 계정 지목 가능.
`TENANT_GUARD_MODE=warn|off` 가 그 방어를 환경변수로 끈다.

---

## ② Phase 86 — SPEC v2 의 전제 두 개가 무너졌다

**권위는 `86-SPEC-v3.md`** (v2 상단에 대체 경고 붙임).

### 무너진 전제 ①: "`codigos_tmp` 가 백업 대부분"

v2 의 F1 이 그렇게 적었고 **TASK-2b 정당화가 거기 기댔다.** serpenti 실측:

```
전체 SQL 260.2MB → codigos_tmp 제외 246.1MB (94.6% 잔존) = 5.4% 뿐
부피는 vdetalle 782,575행이다
```

v2 의 수치는 **kandente4 한 매장** 값이다. 그대로 구현했으면 리더를 완성하고
"이제 200MB 가능" 이라 판단했다가 아무것도 해결 안 됐을 것이다.
→ TASK-2b 를 **"끝까지 스트리밍 + staging"** 으로 재정의.

### 무너진 전제 ②: 재고를 `stockrep`(365일 롤링)으로

사용자 결정: **`screendetails2_id`, 전 기간.** 두 뷰 계열이 다른 값을 낸다.
전 기간이 VentaGO(영구 잔액)와도 맞아 v2 의 자체 모순이 사라진다.

★ 이름 주의: `screen_details_id` 가 아니라 **`screendetails2_id`**(뷰가 12개 있다).
★ `gasto_infos`→`gasto_info`, `crddetalles`→`crddetalle`.

### 실측 (serpenti, 67 테이블)

```
vdetalle 782,575 · codigos_tmp 298,098 · vcodes 151,637 · logs 128,014(alerta 4,587)
ingresos 97,047 · fdetalles 40,849 · fventas 20,750 · clientes 16,408 · codigos 11,805
sucursal 2종 · screendetails2_id 9,397행 (stock<0 이 1,699)
팽창률 23개 파일: x5.35~x5.93 · 164MB 백업 → 877.8MB
```

---

## ③ 사용자 결정 (전부 SPEC v3 에 기록)

| # | 결정 |
|---|---|
| 1 | A/B/C 그룹 + **업무 단위 원자 묶음** (원시 테이블 단위 아님) |
| 2 | `ingresos` 는 **참조용** — 재고를 안 움직인다 |
| 3 | **음수 재고는 0 으로 클램프** (codex 는 보존 권고 — 사용자가 0 선택) |
| 4 | 오염 방지 강조 |
| 5 | `clientes`: **DNI 없으면 어디에도 안 만든다** |
| 6 | `clientes`: **매칭은 DNI 로만** (이름 매칭 금지) |
| 7 | 업로드 상한 65MB (85 요청 — 실측이 막았다) |

★ 3번은 **값은 0, 사실은 노출** — 클램프 건수·목록을 preview·결과·다운로드로 낸다.

★ 7번: 85 × 5.93 = 504MB 로 변환 상한(400MB)을 넘어 **업로드는 되고 변환에서 거부**된다.
  400 을 505 로 올리면 Node 문자열 크래시 벽 512MB 에서 1.4% 남는다.
  **164MB 백업(877.8MB)은 이 구조로 어떤 설정으로도 못 연다.**

---

## ④ 완성된 것 — TASK-2b′

```
src/app/legacy-import/streaming/
  copy-text.ts              COPY 디코더 (기존 파서에서 꺼낸 단일 출처)
  pgdump-line.reader.ts     줄 단위 스트리밍 — 허용 테이블만
  ace-stock.sql.ts          재고 계산 서버 SQL (원본 뷰 재현)
  ace-staging.service.ts    잡별 스키마 + 배치 INSERT
  stock-baseline.writer.ts  원장 기록 (오염 방지 축)
```

**실측 결과:**

```
SQL 273.4MB 를 읽는 동안 힙 증가 22.1MB      (옛 경로는 273MB+ 를 문자열로)
재고 SQL vs 원본 ACE 뷰: 9,397행 **불일치 0** (구성 항목까지)
관통: staging 893,960행 → 재고 → 원본 뷰와 불일치 0
더미 매장: 원장 932행 · 트리거 5개 통과 · stock_balances 일치 · 오염 0
```

★ `IS FALSE` 이지 `IS NOT TRUE` 가 아니다 — NULL 에서 갈린다. 원본대로 유지.
★ 캐스트는 `NULLIF(x::text,'')::타입` — **native·text 양쪽에서 같은 SQL** 이 돈다.
  안 그러면 "검증한 SQL" 과 "도는 SQL" 이 갈라진다.

---

## ⑤ ★★ 임포트 하네스 (`test/itest/harness.ts`)

**왜 만들었나: 내가 쓴 소스 검사가 대조군을 통과했다.**
`if (!docKey)` → `if (false)` 로 죽여도 문자열은 남고, `normalizeCuit` 을 한 줄에서
빼도 다른 줄에 남아 정규식이 통과했다. 3개 중 2개가 아무것도 안 지키고 있었다.

막혔던 자리 셋:
① 모델 등록 — 경로 글롭은 **default export 요구**, 이 저장소는 named export
  → `src` 아래 `*.model.ts` 를 훑어 **Model 상속 여부로** 수집
② 가드 — 컨트롤러 가드가 다른 모듈 서비스 요구 → `overrideGuard`
③ 정리 — `global_clients` 가 매장을 가리켜 FK 에 막힘

### ★★★ 하네스가 곧바로 실제 결함을 드러냈다

`Clients` 의 `AfterCreate` 훅은 **`main.ts:138` 의 `attachClientsHook` 이 등록하는
싱글톤에 의존**한다. 등록이 없으면 훅이 **조용히 아무것도 안 한다** —
`global_clients`/`store_clients` 가 안 생기는데 **오류도 안 난다.**

→ **standalone 스크립트도 이 훅이 안 돈다**(main.ts 주석이 그렇게 적어 두었다).
  배치 작업을 쓸 때 반드시 확인할 자리.

### 정리가 실패한 실행을 견디게 했다

대조군이 중간에 죽어 잔여물을 남겼고 다음 실행이 그것 때문에 또 죽었다.
한 문장이 실패해도 넘어가게 고쳤다 — **정리가 아예 안 도는 것**이 더 나쁘다.

---

## ⑥ 빌드 #800 실패 — `.txt` 자산

`nest build` 가 `.txt` 스키마 카탈로그를 `dist/` 로 안 옮겨 컨테이너가 부팅하다
ENOENT 로 죽었다. `tsc`·단위 321·실DB 11 이 **전부 `src/` 에서 도는 탓에** 못 봤다.
blue/green 이 전환하지 않고 green 을 버려 운영은 무사했다(W5 가 값을 한 첫 사례).
→ `nest-cli.json` assets + `npm run build` 끝에 `scripts/assert-runtime-assets.js`.

---

## ★ 다음 세션이 할 일

### 바로 이어갈 것 — TASK-3′ 나머지 매퍼

하네스가 있으므로 이제 **동작으로** 검증하며 쌓을 수 있다.
`clientes-import.itest.ts` 가 본보기다.

B그룹 업무 단위(SPEC v3 §4):
판매(`vcodes`+`vdetalle` 원자) · 결제수단(`vtags`) · 팩투라(`fventas`+`fdetalles`) ·
외상(`creditoventas`+`crddetalle`+`cobranzacab`) · 온라인 · 입고 · 비용 · 시즌

**오염 방지 8겹**(SPEC v3 §5)을 매퍼마다 적용할 것. 특히:
- 배치 **커밋 전마다** 소유 증명 (최종 검사만으론 부족)
- 소유 검사는 **배치 조인** — 행별이면 `vdetalle` 782,575행에서 N+1
- 지점 매핑은 잡 시작 시 **불변 스냅샷**

### 그 다음
- TASK-4′ 잡 러너 (리스·배치·진행률·정산 `읽음 = 삽입+중복+필터+거부`)
- TASK-8′ 화면 — 목업: https://claude.ai/code/artifact/ffd90b56-f17e-49ec-91d7-1708069a3468

### 검사 관련 — 반드시 지킬 것
**새 검사를 쓰면 대조군을 돌려라.** 이 세션에서 소스 검사 2개, 대조군 1개가
통과했다(= 아무것도 안 지켰다). 통과하면 그 검사는 없는 것이다.

---

## 이월 / 미해결

- **스테이징이 30 테이블 뒤처져 있다** (200 vs 운영 230). Phase 86 마이그레이션 7개는
  적용해 뒀으나 나머지 격차는 그대로 — 손대려면 승인 필요
- `price_types.store_entity_id` 운영 18행 **전부 NULL** → `code-import.service.ts:154`
  의 가격 슬롯 정렬이 아무것도 정하지 않는다 (별건)
- MP 후속 부채 MED 3건 (①에 목록)
- SPEC v3 §9 의 남은 확인: 뷰 정의 해시 대조 · `borrado` 삼값 논리 ·
  정수 오버플로 · 배치 재시도 · 덤프 출처 검증
- 종전 이월 유지: sudoers 0440 · 프론트 blue/green 없음 · POS 카탈로그 P95 376ms ·
  소켓 한도 0 · `/me` 11쿼리 미캐시

## 로컬 환경 (다음 세션이 알아야 할 것)

- 로컬 `ventago`(5432) 를 오늘 백업(2026-08-20)에서 복원 + 마이그레이션 전부 적용 →
  **운영과 스키마 동일**. itest 가 여기에 붙는다
- `ace_probe` DB 에 serpenti 백업 전체를 복원해 뒀다 — **원본 ACE 뷰가 옆에 있어야**
  재고 재현 검증이 성립한다. 지우지 말 것
- `npm run test:itest` — 실DB 검사 34건
