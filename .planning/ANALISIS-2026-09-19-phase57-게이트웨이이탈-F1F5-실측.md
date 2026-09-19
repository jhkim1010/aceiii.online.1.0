# Phase 57 W-F1~F5 — 게이트웨이 이탈: 실측과 결정 (2026-09-19)

계획서: `.planning/phases/57-*/57-SPEC-ADDENDUM-2026-09-18.md` §W-F

## 한 줄

**F1·F2·F3(코드)·F5 완료.** F4 는 보류하되 **이유가 바뀌었다** — 폴더가 아니라
**CUIT·인증서가 같은 것**이 원인이고, 그래서 해법도 「캐시 분리」가 아니라
**「Ventago 전용 인증서 발급」** 이다.

---

## 1. 계획서의 전제 중 틀린 것 셋

| 전제 | 실측 (2026-09-19) |
|---|---|
| F1 `resolvePvAndCoolUser` 를 «만들지 않는다» | **이미 만들어져 있었다.** 다만 호출부 0건이고 운영 2행 모두 `invoice_sucursal IS NULL` — 죽은 코드였다. 지웠다(동작 변경 0) |
| F3 «전용 디렉터리를 신설한다» | **본체는 이미 되어 있었다.** 게이트웨이 폴더 통째 마운트는 걷혔고 레거시 124개 중 붙는 것은 1개뿐. store 9 는 이전 완료 |
| F3 과 F4 는 독립이다 | **아니다.** G1 의 잔여분(`coolsistema` 폴더 하나)이 남은 이유가 곧 G2(`.lastTokens`) 다 |

### 운영 마운트 (실측)

```
/var/lib/ventago-certs                              → /app/certificates        (우리 것, 2개)
/var/lib/jenkins/workspace/certificados/coolsistema  → /app/certificates/coolsistema

/var/lib/ventago-certs/coolsyncrohomo1/  cert · key · .lastTokens   ← store 9, 이탈 완료
/var/lib/ventago-certs/coolsistema/      (비어 있음 — 위 중첩 마운트가 덮는다)
레거시 디렉터리 전체: 124개 (그중 우리가 보는 것 1개)
```

### 운영 인증서 (실측)

```
CN = CNCOOLSISTEMA2024 · serialNumber = CUIT 20950928434
issuer = CN=Computadores, O=AFIP, C=AR
notAfter = 2026-10-20        ← 31일 남음
cert/key modulus 일치 (MD5 fc3792a016a886c028770568952884b3)
```

---

## 2. ★★★ TA 는 **인증서 단위**다 — CUIT 단위가 아니다

이 한 줄이 F4 의 해법을 바꾼다. 근거는 ARCA 공식 기술명세 원문이다
(2차 자료는 엇갈렸다 — 한쪽은 «CUIT 단위», 다른 쪽은 «인증서 단위»라고 했다).

> "El WSAA, WS publicado por la AFIP que implementa la autenticación de **los
> computadores del EE (CEE) mediante certificados digitales X.509**"

> "Empresa SA cuya CUIT es 30123456789 y **el DN del CEE es
> `cn=srv1,ou=facturacion,o=empresa s.a.,c=ar,serialNumber=CUIT 30123456789`**"

> "el trámite ... incluye **el alta de los CEE**" (복수)

즉 **CEE = 인증서의 DN** 이다. 같은 CUIT 아래 `cn=srv1`, `cn=srv2` 처럼 **여러 CEE** 를
등록할 수 있고, 각 CEE 는 자기 TA 를 따로 받는다. `coe.alreadyAuthenticated`
(«El CEE ya posee un TA valido»)는 **같은 DN** 이 유효 TA 를 가진 채 재로그인할 때 난다.

출처:
- ARCA · Especificación Técnica WSAA 1.2.0 — https://www.afip.gov.ar/ws/WSAA/Especificacion_Tecnica_WSAA_1.2.0.pdf
- ARCA · WSAA Manual del Desarrollador 20.2.19 — https://www.afip.gob.ar/ws/WSAA/WSAAmanualDev.pdf

★ **남은 불확실성**: 문서 근거는 분명하나 「같은 CUIT · 인증서 2개 동시 로그인」을
  **실측한 적은 없다.** homologación 에서 한 번 재면 끝난다(운영 영향 없음).
  단 homo 인증서 추가 등록은 ARCA 포털 작업이라 사용자 손이 필요하다.

### 그래서 인증서를 «복사»하면 안 되는 이유

복사하면 두 시스템이 **같은 DN = 같은 CEE** 를 쓴다. 폴더만 갈라지고 잠금은 그대로다.
`.lastTokens` 를 각자 갖는 순간 서로의 TA 를 무효화한다(최대 12시간 발급 불가).

### 권장 경로 — Ventago 전용 인증서

| | 복사 | 전용 인증서 |
|---|---|---|
| cert·key 자리 | 우리 폴더 | 우리 폴더 |
| TA 충돌 | **남는다** (같은 CEE) | **사라진다** (다른 CEE) |
| 10/20 갱신 | 두 시스템이 같은 파일을 갱신 | 각자 따로 |

★ 기계 장치는 **이미 앱에 있다** — Configuración ▸ Facturación 의 「Generar CSR」 →
  ARCA 서명 → `.crt` 업로드. store 9 가 그 경로로 만들어졌다.
★ 시점도 맞다 — 어차피 31일 뒤 갱신해야 하고, 지금 구조에서는 그 갱신 CSR 이
  **남의 폴더에 쓰인다.**

---

## 3. 한 것

| | 내용 | 커밋 |
|---|---|---|
| **F1** | manager 게이트웨이 PV 해석 폐기 (G5). 재발은 `gateway-desacople.spec.ts` 가 막는다 | api `773e6240` |
| **F2** | 인증서 폴더의 권위를 `cert_slug` 로. **발급 경로가 그것을 안 보고 있었다** | api `df2ce772` · app `375d3f2` |
| **F3** | 전용 디렉터리 기계 장치. env 미설정이면 동작 변경 0 | api `3635b207` |
| **F5** | 공유 폴더를 **새로** 가리키는 것만 차단 (설정 시점) | api `282c86d6` |
| **F4** | **보류** — 위 2절이 이유 | — |

### F2 에서 드러난 구멍 셋 (전부 «한 곳만 고쳐서» 생긴 것)

1. `soap-direct.provider` 가 slug 를 `req.coolUser || req.cuit` 로 직접 조립 —
   **발급이 `cert_slug` 를 아예 안 봤다.** 화면·점검은 새 값, 서명은 옛 폴더.
2. `afip-cert.service.emisorDe` 도 같은 식 — CSR 생성이 발급과 다른 폴더를 볼 수 있었다.
3. **인증서 만료 감시가 `cool_user` 하나만 봤다** — `cert_slug` 로 옮긴 발행자나
   CUIT 이름 폴더는 감시에 **보이지 않았다.** 만료가 와도 조용하다.

그리고 D-16 이 `certSlug` 만 응답에서 뺐는데 **`coolUser` 가 그대로 새고 있었다**
(같은 값, vendedor 가 읽는 목록). `emisor-campos-sensibles.ts` 한 곳으로 모았다.

---

## 3-b. CODEX 자문에서 나온 결함 3건 (전부 수정 — api `50459e81`)

| | 내용 |
|---|---|
| **P1** | **자동 운영 전환이 공유 폴더 가드를 우회했다.** 수동 경로 넷은 막는데 7일 상한의 자동 전환만 안 막았다 — 하필 **사람의 승인 없이** 세무 발급을 켜는 자리다 |
| **P2** | **복사 도중을 「전환 완료」로 오판.** 방아쇠가 파일의 «존재» 였는데, 복사는 파일을 먼저 만들고 내용을 나중에 쓴다 → 잘린 키로 서명. 방아쇠를 **완료 표식(LISTO)** 으로 바꿨다 |
| **P2** | **부분 실패에서 감시가 읽힌 것까지 버렸다.** `dirError` 만 보고 조기 반환해 만료 목록이 사라지고 "하나도 확인 못 함" 이라 거짓 보고 |

★ 셋 다 **내가 만든 것**이다. 특히 P1 은 「입구를 전수로 센다」를 하면서 다섯 번째를
  빠뜨린 것이고, 마지막 건은 「감시가 부재에서 침묵하지 않게」를 고치다 한 층 위에서
  같은 것을 다시 만든 것이다.

★ 복사 순서는 이제 사람 손에 맡기지 않는다 — `scripts/afip-copiar-cert.sh` 가
  복사 → modulus 대조 → 표식을 강제한다(분기 넷을 종료코드로 실측).

## 4. 그 뒤 — 코드는 **전부 준비됐다** (2026-09-19 추가분)

사용자 지시: 「코드 작업은 미리 다 해 줘」. 남은 것은 **ARCA 포털 작업뿐**이다.
절차는 `.planning/GUIA-2026-09-19-afip-certificado-propio-y-pv.md`.

| | 내용 | 커밋 |
|---|---|---|
| **F3b** | 전용 인증서 이전 3단계 — CSR(새 폴더) → 업로드(파일만) → **활성화(WSAA 확인 후에만 이동)** + 되돌리기 | api `66ad6c9d` |
| **TA 규칙** | 공유 선언 slug 면 공유 폴더, **아니면 그 인증서 폴더** — 전용 인증서를 받으면 스위치 없이 G2 가 풀린다 | api `66ad6c9d` |
| **F5b** | 공유 폴더로 **운영 발급** 차단 — 기본 꺼짐(`AFIP_BLOQUEAR_EMISION_CARPETA_COMPARTIDA`) | api `754af978` |
| **F6** | 전용 PV 이전 — **조회 먼저**, 실패 시 무변경. 옛 PV 는 `issuer_id` 로 계속 검증 | api `833aacf2` |

### 그 과정에서 시험이 잡은 결함 셋 (전부 내가 만든 것)

1. **`dedicado` ≠ `listo`** — 「거기에 만들 것이다」와 「거기에 있다」를 섞어서
   **빈 폴더로도 활성화가 통과**했다(업로드를 건너뛰고 발행자를 옮길 수 있었다).
2. **`Number(undefined)` = NaN, Map 은 NaN 을 키로 일치시킨다** — `issuer_id` 없는
   전표가 id 없는 발행자와 짝지어져 **남의 PV 가 우리 옛 번호열로 붙었다.**
   물어볼 수단이 없는 PV 가 「확인됨」이 되어 신고 게이트가 잘못 열리는 형태다.
3. spec 의 mock 이 group 질의 **둘**을 구분하지 않아 새 경로가 시험에서 안 돌 뻔했다
   (이 파일이 예전에 같은 이유로 헛통과한 전력이 있다).

## 5. 사용자에게 남은 것

1. **cool-invoice 조율** — 10/20 만료. 우리만 새 인증서로 가면 **그쪽이 그날 멎는다.**
2. **ARCA: 전용 인증서 alias 등록 + wsfe 위임** → 앱에서 CSR·업로드·활성화 3번 호출
3. **ARCA: 전용 PV 등록** → 앱에서 이전 1번 호출
4. 그 뒤 `AFIP_BLOQUEAR_EMISION_CARPETA_COMPARTIDA=true` 로 발급 차단 승격
5. (선택) homo 에서 «같은 CUIT · 인증서 2개» 실측 — 문서 근거는 확정적이나
   실측은 아직 없다. 2번을 하면 그 자체가 실측이 된다.
