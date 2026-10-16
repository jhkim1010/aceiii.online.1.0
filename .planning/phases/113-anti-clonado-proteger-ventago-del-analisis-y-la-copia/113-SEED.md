# Phase 113 — 복제 방지: Ventago 를 분석·복제 도구로부터 보호 (discuss/plan 용 시드)

## 요청 (2026-10-16)
사용자: 「나는 이런 프로그램들이 내 시스템의 복제를 할 수 없게 보안 시스템을 내장하게 하고 싶어.」
→ 「이를 위한 phase 를 하나 만들고 준비해줘.. **병렬 서버 준비 작업을 마치고 그 후에** 하면 좋겠어.」
계기: REA(`github.com/morluto/rea`, npm `rea-agents` 6.5.0, MIT) — 에이전트가 소스 없이 네이티브·JS/Electron·.NET·웹을
분석하는 MCP. 「다른 앱의 기능을 보고 내 제품에 만든다」를 표방한다.

## ★ 전제 (계획 단계에서 흐리지 말 것)
- **사용자 기기에 내려가는 코드는 막을 수 없다.** 목표는 ① 핵심은 서버에만 ② 내려가는 것엔 비밀이 없게
  ③ 분석 비용을 올린다 ④ 법적·추적 장치. 「복제 불가」를 완료 기준으로 쓰면 검증할 수 없는 phase 가 된다.
- **가장 강한 방어선은 이미 있다:** 업무 로직(판매·재고 원장·AFIP·정산)은 api 에만 있고 소스 저장소는 비공개.
  REA 류는 **받은 것**만 분석한다. 이 phase 는 「받는 것」의 노출을 줄이는 일이다.

## 실측 (2026-10-16)
| 대상 | 상태 | 근거 |
|---|---|---|
| 웹 프론트 | minify, **소스맵 0개**, `_app-*.js.map` 미제공 | 운영 컨테이너 `find .next/static -name '*.map'` = 0 |
| 프론트 비밀값 | `NEXT_PUBLIC_JWT_SECRET`·`NEXT_PUBLIC_JWT_REFRESH_TOKEN_SECRET` 가 **번들에 들어간다** — 서버 `JWT_SECRET_KEY` 와 **다른 값**(해시 대조)이라 위조 불가 | `src/@fake-db/auth/jwt.ts:18-20`(템플릿 잔재). `@fake-db` 는 `_app.tsx:34` 주석 · `Autocomplete.tsx:27` 타입 import 만 |
| print-agent · zebra-agent | `asar: true`, **난독화 없음**(obfuscator·bytenode 의존성 0) · 설치 파일은 **공개 저장소** `jhkim1010/ventago-downloads` | 각 `package.json` build.files · `gh api repos/.../ventago-downloads` private=false |
| Flutter 앱 6개 | 빌드에 `--obfuscate`/`--split-debug-info` **없음** | `.github/workflows/build-{colibri,admin-app,tienda-admin-app,despacho-app,mobile-sales-app}.yml` · `scripts/build-app.sh` · `ventago-admin-app/build-apk.sh` |
| API 수집 | 전역 **IP 기준** 스로틀(Redis 저장, `app.module.ts:182` · `ProxyThrottlerGuard`) 있음 · **로그인 사용자 기준 대량 조회 감시는 없음** · nginx `limit_req` 없음 | |
| 소스 저장소 | `ACE_online_1.0` 비공개(외부 404) | |

## 후보 웨이브 (discuss 에서 확정)
- **W1 비밀값 정리 (S):** `NEXT_PUBLIC_JWT_*` 와 `@fake-db` 제거(타입은 옮김). 「클라이언트 번들에 비밀 없음」을 **시험으로 고정** —
  빌드 산출물을 grep 해 알려진 비밀 키 이름·고엔트로피 문자열을 잡는다(대조군 필수: 심은 값을 잡는지).
  Flutter·에이전트도 같은 기준(하드코딩된 키/토큰).
- **W2 Flutter 난독화 (S):** 6개 빌드에 `--obfuscate --split-debug-info=<dir>`. 기호 파일은 릴리스별 보관(오류 추적용).
  ★ 리플렉션·`toString()` 이름 의존 코드(직렬화, enum `.name`)가 깨질 수 있다 → 앱별 스모크.
- **W3 에이전트 보호 (M):** javascript-obfuscator 또는 bytenode(V8 바이트코드) · Electron fuses(`EnableEmbeddedAsarIntegrityValidation`,
  `OnlyLoadAppFromAsar`, `RunAsNode` off) · 코드서명 확인.
  ★★ **중복 인쇄 절대 금지**(메모리 `no-duplicate-print-is-absolute`): 난독화 전후 ZPL/ESC-POS 출력이 **바이트 단위로 같은지** 시험.
  ★ 로컬 electron-builder 금지(메모리 `local-electron-builder-prunes-root-node-modules`) — Actions 에서만.
- **W4 API 수집 차단 (M):** 로그인 사용자·매장 단위 요청량/대량 조회 한도 + 비정상 패턴(전 상품 페이지 순회, 짧은 시간 수천 건) 텔레그램 경보.
  ★ POS 정상 사용(카탈로그 전체 동기화, 오프라인 캐시)이 걸리면 안 된다 — 먼저 **실측 기준선**(사용자별 분당 요청 p99).
- **W5 법적 장치 (S):** 이용약관에 역분석·복제 금지 조항 · 에이전트/앱 설치 화면과 웹 하단 저작권 고지. (문안은 사용자 확인)
- **W6 추적 (선택):** 매장별 보이지 않는 표식(배포본·화면) — 유출 시 출처 특정. 비용 대비 효과는 discuss 에서 판단.

## 범위 밖
- 서버 코드 난독화(내려가지 않으므로 의미 없음) · DRM/라이선스 키 서버 · 안티디버깅 같은 공격적 기법(오탐으로 매장 POS 가 멈추는 위험이 이득보다 크다).

## 선행 / 순서
- **사용자 지시: 병렬 서버(운용3) 준비가 끝난 뒤 착수.** 운용3 남은 단계 = 4 nginx·TLS·AFIP 인증서·MinIO 동기화 · 5 failover.sh ·
  6 DNS TTL(사용자) · 7 failback · 8 밤 리허설 (`.planning/PLAN-2026-10-16-servidor-standby.md`).
- W1 은 다른 웨이브와 독립 — 가장 먼저.
