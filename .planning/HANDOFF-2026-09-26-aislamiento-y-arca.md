# 핸드오프 2026-09-26 — 테넌트 격리 · by-parent 병목 · ARCA 위임 안내서

앞 핸드오프 `HANDOFF-2026-09-25-c-agentes-y-carrito.md` 의 뒤다.
**§1(다음에 할 일) → §2(배포분) → §5(배운 것)** 순으로 읽으면 빠르다.

---

## 1. ★★ 다음 세션이 할 일

### 1-a. **Phase 94 (CUIT 자동 채움) — 전면 작업**

> 사용자 2026-09-26: 「**내일부터는 94를 마무리 해야 해**」

**선행 조건은 코드가 아니다 — AFIP 포털 위임이다.** 그게 없으면 단계 3~5 는
「실행된 적 없는 코드」가 된다.

- 사용자에게 **PDF 안내서를 전달했다**: `.planning/guias/ARCA-Padron-위임절차.pdf`
  (생성 스크립트 `arca-padron-delegacion.py` 도 같이 있다 — PDF 는 diff 가 안 되므로)
- 위임 완료 확인: `GET /afip/padron/diagnose` (superadmin) → **`ticketObtained: true`**
- **위임 전에도 할 수 있는 것**: 단계 1 `cuit.ts`(11자리 + 검증숫자, 순수 `.ts`).
  여기부터 시작하면 된다.
- ★ **단계 2(DB 조회 엔드포인트)는 취소다.** 이미 배포돼 돌고 있다 —
  `InfoClient.tsx:283-351` + `global-clients.service.ts:106`. 만들면 두 개의 진실이 된다.
- 범위·근거: `.planning/phases/94-cuit-autocompletar/94-CONTEXT.md`

### 1-b. **Phase 95 (테넌트 격리) — 배경 트랙, W0 은 «평일에»**

> 사용자 2026-09-26: 「지금 상태가 위험한 것은 아니라면 좀 더 시간을 두고 차근차근」

**W0 = 평일 로그 확인(5분).** 일요일에 하면 뜻이 없다 — 전 매장 개시 0이라
「경보 0건」이 아무것도 증명하지 않는다.

```bash
ssh jhkim-server '
f=/var/lib/ventago-logs/api/combined-$(date +%F).log
echo "요청 $(sudo grep -ac "\[HTTP\]" $f)"
echo "누수 $(sudo grep -ac "격리 누수 감지" $f) / 검증불가 $(sudo grep -ac "격리 검증 불가" $f)"
echo "★ store 가 숫자인 것: $(sudo grep -a "격리 누수 감지" $f | grep -cE "store=[0-9]+")"
'
```

★★ **`store=<숫자>` 가 1건이라도 뜨면 그것은 실제 오염이다 — Phase 94 를 중단하고
최우선으로 올린다.** 경보에 `파일:줄`·매장·user 가 실려 있으므로 그 자리부터 본다.

계획: `.planning/phases/95-aislamiento-multitenant/95-PLAN.md` (W0~W4)

---

## 2. 오늘 배포된 것 — 전부 빌드·컨테이너 확인 완료

| 저장소 | 커밋 | 내용 | 빌드 |
|---|---|---|---|
| app | `56a89c63` | 인증서 3단계에 Padrón 서비스 안내 추가 | front **#812** ✅ |
| api | `815da689` | `by-parent` attributes 축소 + 핫패스 `console.log` 제거 | **#963** ✅ |
| api | `5c2034a6` | 테넌트 가드: 「검증 불가」 분리 + **발생 위치 기록** | **#966** ✅ |
| api | `bec38dad` | **`storeId` 를 SELECT 에 강제** → `store=undefined` 소멸 | **#966** ✅ |
| api | `85f0d4f6` | 소스맵을 `NODE_OPTIONS` 로 (pm2 cluster 미전파) | **#967** ✅ |
| nginx | — | **gzip**(Ventago 두 블록의 :443 에만) + `.bak` 을 `sites-enabled` 밖으로 | reload ✅ |

현재 포인터: api `85f0d4f6` · app `56a89c63`.

★ nginx 백업: `/etc/nginx/backups/*.antes-gzip-20260926-025002` (**`sites-enabled/` 바깥**).
  되돌리기 = 복사 → `nginx -t` → `systemctl reload nginx`.

---

## 3. 숫자로 본 결과

| | 전 | 후 |
|---|---|---|
| 격리 경보 (실 트래픽) | **113건** (09-25) | **0건** (09-26) |
| `by-parent` 중앙값 (로컬 20회) | 43ms | **34ms** (-21%) |
| API 응답 전송량 | 301KB 비압축 | **gzip — 로컬 실측 336KB → 11KB (96.7%)** |
| nginx 중복 server_name 경고 | 4건 | **2건** (남은 2건은 남의 시스템) |

**14일 전수 조사(09-13~09-26): 격리 경보 776건이 전부 `store=undefined`,
다른 매장 숫자가 찍힌 것은 0건 — 오염의 증거는 없다.**

---

## 4. ★ 남은 것 / 손 안 댄 것

- **raw SQL `sequelize.query` 219곳은 훅을 아예 안 탄다** (그중 store 조건 없는 것 **204곳**).
  → Phase 95 W1~W3.
- `if (storeId) where.storeId = storeId` 형태 **35곳** — 가드가 «구해 주는» 상태다.
  코드 자체는 안 좁혀져 있다. → W4.
- **RLS 는 하지 않기로 했다** (측정 후 철회, 견적 2~3주). 근거는 `95-CONTEXT.md` §4.
- 핸드오프 `2026-09-25-c` 의 이월분 중 **4-2(Historial del día 정렬)는 오늘 해결**했고,
  4-1(CUIT)은 Phase 94 로 승격, 4-3·4-4 는 그대로 남아 있다.
- 감사 문서의 P1(SSH 키 6개 귀속) · P2(공개 포트 축소)는 **미착수** —
  `.planning/AUDIT-2026-09-26-servidor-seguridad-y-300ms.md`.

---

## 5. 이 세션에서 배운 것 (전부 실측 — 다음에 같은 함정에 빠지지 말 것)

### ① **응답이 같아도 안전이 같지 않다**
`by-parent` 의 `attributes` 에서 `storeId` 를 뺐더니 **응답은 바이트 단위로 동일**한데
전역 테넌트 훅이 `undefined` 를 읽어 **격리 검증이 꺼졌다**(경보 0→2건).
→ **응답 동일성은 격리 안전의 근거가 아니다.** 조회 경로를 건드리면 **경보 수를 전후 대조**한다.

### ② **설정 파일에 줄이 있는 것 ≠ 적용된 것**
`node_args: ['--enable-source-maps']` 를 배포했고 파일도 컨테이너에 잘 갔는데,
**워커 4개 전부 플래그가 없었다** — pm2 **cluster 는 `node_args` 를 포크에 안 붙인다.**
워커 수를 세어(6개 중 2개) 발견했다. `NODE_OPTIONS` 로 옮겨 4/4 확인.
→ **프로세스의 cmdline/environ 을 직접 본다.**

### ③ **공식 문서가 최신이 아닐 수 있다**
ARCA 매뉴얼 **v3.7(2025-07)** 이 적은 호스트 `aws.arca.gov.ar` 는 **DNS 가 안 풀린다.**
실제로 사는 것은 구 `aws.afip.gov.ar`(WSDL 200).
→ **문서를 믿고 코드를 「고치면」 오히려 깨진다.** 고치기 전에 친다.

### ④ **병목은 «행 수» 가 아니라 «행의 무게» 였다**
`pageSize=1000` 을 50으로 줄이라는 codex 권고는 **하면 회귀**다(POS 검색이 클라이언트
필터라 서버로 옮기면 키 입력마다 376ms). 실제 비용은 **Sequelize 모델 인스턴스 1,500개**였고
DB 는 3ms 미만이었다. → **줄일 것을 먼저 측정한다.**

### ⑤ **codex 는 프롬프트가 길면 조용히 죽는다 — 임계값이 «1,000자 근처»**
4회 연속 침묵사 후 대조군으로 갈랐다(30자 OK · 700자 OK · 1,350자 죽음 · 4,500자 죽음).
보안 단어도 훅 실패도 원인이 아니었다. → **~700자씩 쪼개면 쓸 만한 답이 온다.**

### ⑥ **PDF 폰트 함정 둘**
AppleGothic 은 한글은 되지만 **스페인어 악센트 글리프가 없다**(`Padrón`→`Padrn`).
한글+악센트를 다 가진 폰트가 이 기계에 **Arial Unicode 하나뿐**인데 **bold 얼굴이 없어
`<b>` 가 아무 효과가 없었다.** → 강조를 **색**으로 바꿨다. 양방향 대조군으로 확인.

---

## 6. 검증 수치

| | |
|---|---|
| api | tsc 0 · jest `src/app/products` 19 suites/231 · `src/common/tenant` 3 suites/32 · eslint 새 지적 0 |
| 돌연변이 | 이 세션 **16개 적용, 16개 사망** |
| E2E 대조군 | `attributes` 에서 `storeId` 를 빼도 경보 0 · 응답 335,946 B 동일 · 유출 없음 |
| 운영 확인 | 빌드 SHA 대조 · 컨테이너 재생성 · 워커 environ 실측 · 소스맵 대조군 |
