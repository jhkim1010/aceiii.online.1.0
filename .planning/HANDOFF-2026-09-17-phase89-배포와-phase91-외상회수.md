# 핸드오프 2026-09-17 — Phase 89 배포 완료 · Phase 91(외상 회수) 착수 대기

---

## ▶ 다음 세션이 할 일 — **Phase 91 을 마무리한다**

사용자 지시(2026-09-17): **④ Phase 91 외상 회수를 마무리해야 한다.**

시작점:
```
.planning/DECISIONS-2026-09-17-cobro-de-deuda.md      ← 결정 D-1~D-7, 실측, 작업 순서
.planning/ROADMAP.md  → ### Phase 91 (2072행)          ← 요약 + 함정
.planning/phases/91-cobro-de-deuda-pos/                ← 빈 디렉터리
Mock-up: https://claude.ai/code/artifact/9bd307cd-7637-46c7-bfa3-98585ed7021a
```
다음 명령: `/gsd-discuss-phase 91` → `/gsd-plan-phase 91` → `/gsd-execute-phase 91`

### 착수 전 반드시 읽을 두 가지

**① 첫 작업은 `dp` 단축키가 아니다.** 카하 줄이 먼저다 —
`POST /credit/payments` 가 `box_operations` 를 쓰고 열린 카하 없으면 차단.
참조 구현이 저장소 안에 있다: `online-orders.service.ts:2432-2465`.
작고, 검증된 형태가 있고, **`dp` 를 안 만들어도 그것만으로 돈 구멍이 닫힌다.**
★ 지금 이 순간에도 `/cuentas-corrientes` 로 받는 돈은 카하에서 사라지고 있다.

**② D-5 를 반만 하면 이중계상이 된다.** 지금 기간 매출은 결제수단을 안 거른다:
`SELECT SUM(s.total_amount) FROM sales s WHERE status/store/branch/date`
(`reportsBreveVentaCockpit.service.ts:62`). 외상 판매가 **이미 포함**돼 있다.
회수를 판매로 만들면서 **미회수 외상을 빼지 않으면 같은 돈을 두 번 센다.**
바뀌는 폭(store 6): 159건 26,423,936 중 외상 7건 1,690,600 · 미수 1,422,000.
금액이 달을 건너간다 — **사용자에게 고지하고 승인받았다.**

---

## 1. Phase 89 (QR 공개 상품 페이지) — 운영 배포 완료, UAT 만 남음

**12개 plan 전부 실행 · 배포 완료.** 죽어 있던 라벨 QR 이 살아났다.

```
app.coolsistema.com/m/stock?s=6&p=1   404 → 200
newapi.../api/public/qr-stock/6/1     404 → 200  {"mode":"shop_redirect",...}
POST /api/public/ventago-leads {}            → 400 (검증 동작)
Jenkins api-new-coolsistema #905 SUCCESS · front-coolsistema #741 SUCCESS
운영 로그 'does not exist' 0건
```

**검증 `human_needed`** — 자동 확인 13/13 통과, 새 gap 없음.
남은 것은 **사람이 실물로 해야 하는 판정 3건**뿐:
`.planning/phases/89-qr-public-product-page/89-UAT.md` 의 A~E 절차.
(실물 라벨 스캔 · 설정 켜고 가격 병기 판단 · 두 CTA 끝까지)

★ 운영 13개 매장 전부 `qr_precio_publico=false` — **기본 꺼짐이 의도된 배포 안전값**(D-04).
★ **phase 를 완료로 표시하지 않았다.** UAT 결과를 받고 마감할 것.

### Phase 89 가 실제로 찾아낸 결함 4건 (전부 대조군으로 실증)

| 출처 | 내용 | 상태 |
|---|---|---|
| 89-10 | `NULLS NOT DISTINCT` 를 복원 카탈로그 파서가 몰라 `catalogUniqueKeys()` 가 통째로 죽음 | 고침 |
| 89-11 | 자기가 만든 검사 2개가 **아무것도 검증 안 함** — `toContain('p.store_id')` 가 진짜 조건을 지워도 통과, psql 오류의 빈 출력이 `${VAR:-0}` 에 걸려 「위반 0」으로 접힘 | 고침 |
| 89-08 | `POST /reseller/auth/register` 가 multipart 단일 `storeIds` 를 배열로 못 받아 **정당한 제출을 전부 400 으로 거절** — 이 경로의 유일한 실사용 형태가 통째로 막혀 있었다 | 고침 |
| CODEX P1 | KYC 업로드 부분 실패 시 MinIO 고아 파일 | 고침 |

**미해결로 기록된 것** (`89-qr-public-product-page/deferred-items.md`):
CODEX P2 3건(리드 통지 pending 영구정지 · `ventago_leads` FK CASCADE ·
`check-cta-destinos.sh` 가 404 만 실패로 봄) · 이미지 파일명 모지바케 35건 ·
REQUIREMENTS.md 에 phase 89 요건 미등록.

---

## 2. ★★ CODEX 자동 검토가 Phase 89 전체(커밋 40건)를 건너뛰었다 — 원인 미상

`.team/reviews/.auto-codex.heads` 가 **phase 시작 전 값**에 멈춰 있었고
마지막 자동 보고서는 2026-09-16 18:52(작업 시작 **전**)였다.
수동으로 전체 diff 를 `codex exec` 에 넘겨 보완했고 **P1 1건 + P2 3건**을 받았다.

**배제된 것(실측):** `NODE_OPTIONS` 깨짐 아님 — 두 훅 모두 `node-sano.sh` 를 source 해
스스로 `unset` 한다. `codex` 미설치 아님(`codex-cli 0.146.0`).
남은 후보: 커밋 정규식 불일치 · `pgrep` single-flight · 시크릿 탐지 · diff 6줄 미만 ·
**PostToolUse 훅이 서브에이전트 Bash 에서 안 뜰 가능성**(PreToolUse 게이트는 확실히 떴다).

★ **push 승인을 구하기 전에 `.auto-codex.heads` 값을 직접 확인할 것.**
  그 값이 이번 작업 이전에 멈춰 있으면 **검토는 없었던 것**이다.

---

## 3. 이 세션에서 겪은 로컬 사고 두 건 (다시 겪을 수 있음)

**① `NODE_OPTIONS` 임시 파일이 세션 도중 사라진다.**
`--require /var/folders/.../cmux-claude-node-options/restore-node-options.cjs` 가 없어지면
`node` 가 즉사한다. 증상이 원인을 안 가리킨다 — `nest --watch` 재시작이 실패해
**로컬 API 가 내려간 채 남고**(부모 watch 는 살아 있어 «도는 것처럼» 보인다),
`npx jest`·`npx tsc` 가 exit 1 로 죽는다. ★ `node --version` 은 **통과**해서 헷갈린다.
판정은 `node -e 1` 종료코드로. 복구는 그 경로에 **빈 no-op 파일**을 다시 만들면 끝.
(이번에 그렇게 복구하고 `npm run dev:api` 로 재기동했다.)

**② 로컬 dev 가 느린 것은 정상이다 — 조치 불필요.**
로그인 화면 하나에 로컬 `next dev` **18.81 MB** vs 운영 **1.63 MB**(11.5배).
전송은 localhost 라 0.07초지만 브라우저가 18.8MB 를 파싱·실행하는 데 몇 초 걸린다.
서버 HTML 응답은 첫 컴파일만 1.1초, 그 뒤 37ms.

**③ 공유 워킹트리 주의.** 89-06 실행자가 화면 실측을 위해 `api-ventago/.env` 를 바꿨다가
원복하는 과정에서 **오케스트레이터의 동시 편집과 충돌**했다(내 백업 파일까지 사라졌다).
에이전트가 도는 중에 같은 파일을 건드리지 말 것. 이후 지시에 공유 규칙을 명시했다.

---

## 4. 보류 3건 (사용자 지시로 착수 안 함)

전문: `.planning/PENDING-2026-09-17-보류-3건.md`

| # | 항목 | 상태 |
|---|---|---|
| ① | **Phase 89 실물 UAT** | 위 1번. 사용자 확인 대기 |
| ② | **arriba.world 서브도메인** | 결정 4건 완료, 미착수 — `.planning/DECISIONS-2026-09-17-arriba-world-서브도메인.md` |
| ③ | **TLS 1.3** | 측정만 기록, 운영 무변경 |

### ② 요약
어려운 부분은 이미 있다 — nginx 정규식 vhost(`shop-wildcard.coolsistema.com.conf`) ·
acme.sh 와일드카드(GoDaddy DNS-01, cron 4회/일) · `tienda-app/src/middleware.ts` 는
**도메인 불가지론적**(첫 라벨만 뗀다)이라 고칠 필요 없음.
진짜 작업은 **가입 흐름에 이름+도메인 선택 추가** — 지금은 가입에서 slug 를 **전혀 안 정한다**(NULL).
결정: 전역 유일 / 가입 단계 입력 / 변경 가능하되 옛 이름 301 유지 / GoDaddy.
사용자 선행 작업: `*.arriba.world` A 레코드 → `62.72.7.245`.

### ③ 요약
`app.coolsistema.com/login/` 685ms 중 **서버 처리는 8ms**. 나머지는 왕복이다
(TCP 170 + TLS **338**(1.2 라서 2왕복) + 요청 168).
원인: `:443` 에 `default_server` 가 없어 **알파벳 순 첫 vhost** 가 소켓의 TLS 설정을 지배.
★ `ssl_protocols` 는 **server 블록별이 아니라 listen 소켓별**이다 —
`shop-wildcard.conf` 는 `TLSv1.2 TLSv1.3` 인데도 실제 협상은 TLSv1.2 였다.
제안(보류): `TLSv1.3` 을 **더하기만** — 새 연결마다 ~170ms(25%).

**곁가지 지뢰(미처리):** `include /etc/nginx/sites-enabled/*;` 가 확장자를 안 가려
**`newapi.coolsistema.com.conf.bak-20260825-214627` 이 실제로 로드된다.**
`nginx -t` 가 `conflicting server name ... ignored` 로 경고한다(`invoice`·`manager` 도 같은 형태).
알파벳 순으로 진짜 파일이 먼저라 **지금은 무해**하지만 그 백업은
`client_max_body_size 70m`(현재 128m)라 순서가 바뀌면 업로드가 깨진다.
★ 앞으로 nginx 백업은 **`sites-enabled` 밖에** 둘 것.

---

## 5. 지금 상태

**미push 커밋 3건(루트, 전부 문서):**
```
a3a56a7 docs(roadmap): Phase 91 추가 — 외상 회수(deuda pago)
020ea1f docs: 외상 회수(deuda pago) 결정 기록 + mock-up
cbf2e57 docs: 보류 3건 보관
```
서브모듈 둘은 **0건 미push**(Phase 89 전부 배포 완료).

**DB:** Phase 89 스키마 3건이 **세 곳 모두 적용 완료** —
로컬 `ventago`(5432) · 운영 `ventago`(5434) · `ventago_staging`(15432 터널 → 운영 서버 5434).

**dev 서버:** `npm run dev:api` 로 내가 재기동했다(로그 `/tmp/dev-api.log`).
사용자가 원래 쓰던 `./dev.sh` 창과 다른 자리다.
`api-ventago/.env` 는 원래대로 `ventago_staging` 를 가리킨다 — staging 에도 스키마를 넣었으므로 동작한다.
