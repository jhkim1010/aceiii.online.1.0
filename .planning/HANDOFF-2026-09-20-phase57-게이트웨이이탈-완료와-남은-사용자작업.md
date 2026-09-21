# 핸드오프 2026-09-20 — Phase 57 W-F 게이트웨이 이탈 (코드 완료 · 사용자 작업 대기)

앞 핸드오프: `HANDOFF-2026-09-19-phase57-발행자구조와-게이트웨이이탈.md`
실측 분석: `ANALISIS-2026-09-19-phase57-게이트웨이이탈-F1F5-실측.md`
운영 절차서: `GUIA-2026-09-19-afip-certificado-propio-y-pv.md`  ← **사용자가 볼 문서**

---

## 0. 한 줄

**W-F(게이트웨이 이탈)의 코드는 전부 끝났고 운영에 나가 있다.**
남은 것은 **ARCA 포털 작업(사용자)** 과 그 뒤 엔드포인트를 몇 번 부르는 것뿐이다.

★ **시한이 있다: 운영 인증서 `CN=CNCOOLSISTEMA2024` 가 2026-10-20 만료(D-30).**

---

## 1. 배포 상태 — 전부 완료

| 빌드 | 리비전 | 결과 |
|---|---|---|
| api #920 · front #749 | `b3d65374` / `57d99ec` | SUCCESS · 컨테이너 재생성 확인 · 운영 200 |

(그 전: api #919/#918, front #748/#747 — 전부 SUCCESS)

---

## 2. 이번 세션에 한 것

| | 내용 | 커밋 |
|---|---|---|
| **W-F1** | manager 게이트웨이 PV 해석 폐기 (G5). 재발은 `gateway-desacople.spec.ts` | api `773e6240` |
| **W-F2** | 인증서 폴더 권위를 `cert_slug` 로 (G4) | api `df2ce772` · app `375d3f2` |
| **W-F3** | 전용 디렉터리 기계 장치 — env 미설정이면 동작 변경 0 | api `3635b207` |
| **W-F5** | 공유 폴더를 **새로** 가리키는 설정만 차단 | api `282c86d6` |
| CODEX 3건 | 우회로 · 경합 · 침묵 | api `50459e81` |
| **W-F3b** | **전용 인증서 이전 3단계** (CSR → 업로드 → **활성화**) + 되돌리기 | api `66ad6c9d` |
| **W-F5b** | 공유 폴더로 **운영 발급** 차단 — **기본 꺼짐** | api `754af978` |
| **W-F6** | 전용 PV 이전 (조회 먼저) + 옛 PV 계속 검증 | api `833aacf2` |
| CODEX 7건 | 파괴 경로 1 · 경합 3 · 판정 근거 3 | api `c0da8ce3` |
| **W-E4** | Emisores 표 **인증서 만료일** 열 + 발행자별 상태 엔드포인트 | api `b3d65374` · app `57d99ec` |
| UI | **Facturación 을 Preferencias 에서 분리** → `/configuracion/facturacion` | app `30b1b95` |
| CI | `api tests` 워크플로 **비활성** | api `0da64b9c` |

검증: api tsc 0 · `src/app/afip` **57 suites / 851 tests** · app tsc 0 · eslint 0 · 양쪽 빌드 0.

---

## 3. ★★★ 사용자가 해야 하는 것 (이것만 남았다)

절차 상세는 `GUIA-2026-09-19-afip-certificado-propio-y-pv.md`.

1. **cool-invoice 조율** — 10/20 만료. 우리만 새 인증서로 가면 **그쪽이 그날 멎는다.**
2. **ARCA: Ventago 전용 인증서 alias 등록 + `wsfe` 위임**
   → 앱에서 `cert/csr` → `cert/upload` → `cert/activar` 세 번 호출로 끝난다.
3. **ARCA: 전용 punto de venta 등록** (번호·CUIT·시작일)
   → `POST /afip/issuers/:id/punto-venta` 한 번.
4. 위가 끝나면 **`AFIP_BLOQUEAR_EMISION_CARPETA_COMPARTIDA=true`** 로 발급 차단 승격.
5. **GitHub 결제 해결 → `gh workflow enable "api tests"`**
   ★ 지금 그 게이트는 **꺼져 있다.** 안 켜면 조용히 무방비다.

---

## 4. 이번 세션에 뒤집힌 전제 (다음 세션이 또 속지 않도록)

1. **「W-F1 은 만들지 않는다」 → 이미 만들어져 있었다.** 호출부 0건인 죽은 코드였다.
2. **「W-F3 은 전용 디렉터리를 신설한다」 → 본체는 이미 되어 있었다.**
   레거시 124개 중 마운트되는 것은 1개뿐이고 store 9 는 이전 완료.
   남은 결합은 **폴더 하나(`coolsistema`)** 뿐이다.
3. **「W-F3 과 W-F4 는 독립」 → 아니다.** 그 폴더가 남은 이유가 곧 `.lastTokens` 다.
4. ★★★ **「TA 는 CUIT 단위」 → 아니다. 인증서(CEE = 그 DN) 단위다.**
   ARCA 기술명세 원문 확인. **그래서 인증서를 복사해도 결합은 안 풀린다** —
   전용 인증서를 새로 받아야 한다. → [[afip-ta-is-per-certificate-not-per-cuit]]
5. **「결제 금액 소수 정규화 5곳」(2026-09-10 핸드오프) → 이미 끝나 있었다.**
   저장 경로 7곳 전수 확인 + 돌연변이로 3건이 죽는 것까지 확인.
   ⤷ **핸드오프의 「아직 안 센 것」 목록은 낡는다. 코드로 먼저 확인할 것.**

---

## 5. 이번 세션에 배운 것 (반복된 형태)

1. **주입 모델 뒤에 숨는 쓰기 경로** — `pmModel.bulkCreate` 처럼 별칭+다른 메서드면
   `.create` grep 에 안 걸린다. `@InjectModel` 을 따로 세야 전수가 된다.
2. **`dedicado` ≠ `listo`** — 「거기에 만들 것이다」와 「거기에 있다」를 섞으면
   **빈 폴더가 «준비됨»** 이 된다(활성화가 그대로 통과했다).
3. **`Number(undefined)` 는 NaN 이고 Map 은 NaN 을 키로 일치시킨다** —
   `issuer_id` 없는 행이 id 없는 발행자와 짝지어져 **남의 PV 가 우리 것**이 됐다.
4. **입구 전수는 컨트롤러만 세면 모자란다** — 크론·자동 전환이 빠진다. 하필 그
   경로가 **사람의 승인 없이** 세무 발급을 켠다. → [[controller-enumeration-misses-cron-paths]]
5. **「감시가 침묵하지 않게」를 고치다 한 층 위에서 다시 만들 수 있다** —
   `scan` 은 부분 실패를 담게 했는데 `buildReport` 가 그걸 버렸다.
6. **측정 도구를 틀리면 없는 결함을 본다** — 이 앱은 Toastify 가 아니라
   `[role=alert]` 배너를 쓴다. 「토스트가 없다」로 UI 결함을 보고할 뻔했다.

---

## 6. 화면 검증 환경 (cmux)

★★ **cmux WebView 는 이 앱의 dev 번들을 평가하지 못한다.** dev `_app.js` 가
**13.9MB(eval-source-map)** 라 React 가 하이드레이션되지 않는다(3분 대기해도 0).
운영 사이트와 **로컬 운영 빌드는 정상**이다. Next 13 이 dev 소스맵 변경을 강제로
되돌리므로 줄일 수도 없다 → **검증은 `next build && next start` 로 한다.**
→ [[cmux-needs-production-build-for-this-app]]

★ `api.service.ts` 는 API 호스트를 **`NODE_ENV` 로만** 고른다. 그래서 로컬에서
운영 빌드를 띄우면 **운영 API 를 본다.** 이번엔 `addinitscript` 로 fetch·XHR·
WebSocket 을 `localhost:5002` 로 돌려 검증했다(`responseURL` 로 실증).
  ⤷ **제안(미착수)**: `NEXT_PUBLIC_API_HOST` 로 빼면 이 우회가 필요 없다.

★ **로컬 dev DB 가 낡았다.** `.env` 기본값 `ventago_staging`(15432)에는 Phase 57
마이그레이션이 **하나도 없다**(`entorno`·`cert_slug`·… 전부 없고
`afip_issuer_branches` 도 없음) → AFIP 화면이 500. 운영(5434)은 적용돼 있다.
로컬에서 AFIP 을 보려면 **`ventago`(5432)** 로 띄운다:
```
DB_NAME=ventago DB_PORT=5432 DATABASE_NAME=ventago DATABASE_PORT=5432 node dist/main
```

### 세션 종료 시점의 로컬 임시 상태 (원복 방법)
| | 상태 | 되돌리기 |
|---|---|---|
| API 5002 | `ventago`(5432) + `AFIP_CERTS_DIR=/tmp/certs-local` | 그냥 재기동 |
| 프론트 3050 | **운영 빌드**(`next start`) | `next dev -p 3050` |
| 시험 인증서 | `/tmp/certs-local/coolsistema/` (자체서명 45일) | 놔둬도 무해 |

`.env`·`next.config.js` 는 **안 건드렸다.** 로컬 DB 에서 바꿨던
`razon_social`·`afip_provider` 는 원복했다.

---

## 7. 아직 안 한 것

| | 내용 | 막는 것 |
|---|---|---|
| **W-D4** | 화면 배너(D-3·D-1) — 서버는 이미 `homoEstado.avisar`·`diasRestantes` 를 준다 | 없음 |
| **W-E5** | admin ModalBranch — 그 CUIT 을 쓰는 다른 매장 + 공유 허용 체크 | 없음 |
| **W-E8** | 미리보기(F10)가 보여 준 발행자를 되돌려 보내 서버가 대조 | 없음 |
| **W-F4** | TA 캐시 분리 | ★ **전용 인증서를 받으면 자동으로 풀린다** — 따로 할 일이 아니다 |
| **W-F7** | 이탈 검사(발급 경로에서 `coolsistema.com` 호출 0건) | 없음. F1 의 `gateway-desacople.spec.ts` 가 씨앗 |
| (별건) | 2026-09-10 핸드오프 §(3)의 나머지 둘 — 「계산해서 저장하는 경로」 전수 · 제외한 42개(수량·비율·좌표) | 없음 |

★ W-E4 는 이번에 했다(만료일 열). 앞 핸드오프의 「인증서 상태(CA 구분·공유폴더 경고)」
중 **만료일·상태**까지 했고, CA 구분·공유폴더 경고는 아직이다.
