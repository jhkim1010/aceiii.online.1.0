# 핸드오프 — 2026-09-16(b) · AFIP 게이트 마감 · 운영 500 둘 · Phase 89/90 신설

앞 핸드오프: `HANDOFF-2026-09-16-게이트와-탈출구.md`

이 세션의 요지 둘:
1. **「시험이 늘었다」는 안전의 근거가 아니다.** 6라운드 연속 내 수정에서 P1 이 나왔고,
   **세 번은 같은 형태** — 시험이 **검증 대상을 부르지 않았다**.
2. **감시의 침묵과 부재는 같은 모양이다.** CODEX 보고서가 아직 안 쓰인 상태를
   「지적 0건」으로 읽을 뻔했다.

---

## 0. 배포 상태

| 저장소 | 미push | 상태 |
|---|---|---|
| `api-ventago` | **0** | ✅ 배포 완료 — Jenkins `api-new-coolsistema` **#904 SUCCESS**, blue/green 전환, 컨테이너 재생성(healthy) |
| `ventago-app` | **0** | ✅ 앞 세션에 배포됨(front #740) |
| 루트 | **0** | ✅ |

**DB**: 마이그레이션 2개가 로컬 5432 · 운영 5434 **양쪽 적용 완료**
(`2026-09-16-afip-externos-entorno` · `2026-09-16-b-afip-externos-componentes`).

---

## 1. 운영 500 **두 건**을 고치고 **운영에서 실증**했다

HTTP 인증 없이 컨테이너 안에서 직접 호출해 확인했다(조회성·부작용 없음).

**① `GET /afip/iibb/xlsx`** — `xlsx` 가 **어느 package.json 에도 없었다.**
모노레포 루트에 호이스팅돼 로컬에서만 풀렸고, 운영 이미지엔 없었다.
`require` 가 메서드 안이라 **부팅은 통과하고 그 버튼만 죽었다.**
→ exceljs 로 전환. 배포 후 실증: `✓ xlsx 생성 OK — bytes=7572 hojas=["Hoja1","Resumen"]`

**② PDF 본문 추출** — `require('pdf-parse')` 인데 그 패키지가 **운영·로컬 모두 없었다.**
try/catch 가 삼켜 「Contenido no extraíble」 문자열이 지식베이스에 쌓였다 — 오류도 로그도 없이.
**즉 한 번도 동작한 적이 없다.** → pdf-parse v2 선언 + `PDFParse` API 로 전환.
배포 후 실증: `✓ PDF 추출 정상 — "VENTAGO PRUEBA 12345 · extraccion de texto"`

★ v2 는 `require` 결과가 **객체**다. 설치만 하고 종전처럼 `pdfParse(buffer)` 로 부르면
  `not a function` 으로 던지고 **같은 폴백에 삼켜진다** — 고친 것처럼 보이고 여전히 안 된다.

★ 비용: pdf-parse 21M + pdfjs-dist 36M ≈ **57MB** 가 이미지에 늘었다.

## 1-b. 같은 형태를 **클래스로** 막았다

`src/common/deps/undeclared-imports.spec.ts` — `src/**` 의 외부 import 를 전부 뽑아
api-ventago 자신의 package.json 과 대조한다. 같은 결함이 **세 번** 운영에 나갔고
(code-import-template · reportes-arca · afip-iibb) 앞 두 번은 그 파일만 고쳤다.

전수로 세니 하나 더 있었다 — **`libphonenumber-js`** 를 운영 코드가 **값으로** import
하는데 미선언이었다(`class-validator` 가 딸려 와 우연히 동작). 선언했다.

오탐 둘을 실측으로 잡았다: 주석 안의 `require('xlsx')` 6곳 · SQL 의
`substring(col from '정규식')` 2곳. 안 걸렀으면 영원히 빨간불이고 결국 꺼진다.

---

## 2. AFIP 번호열 게이트 — CODEX P1 **13건**을 6라운드에 걸쳐 마감

마지막 검토(`1152e1f6`)는 **P1 0건**. 미push 12건 전체의 보고서를 대조하는 감사를 돌려
남은 미해결이 아래 §4 의 1건뿐임을 확인했다.

| 라운드 | 지적 | 해소 |
|---|---|---|
| 668b650e (5) | 소유권 탈취 · 중복 등록 · AFIP 원본금액 · 범위 불일치 · 발행자 부재 | 7d74ca88 · 632c6780 |
| 7d74ca88 (2) | 탈출구 제거 · 발행자 부재가 외부원장 무시 | 632c6780 |
| 632c6780 (3) | TOCTOU 중복신고 · 검사 종류 ≠ 담기는 종류 · 비과세 전표 막다른 길 | f0c2510c · 77b88753 |
| f0c2510c (2) | 다른 CUIT 전표를 지움 · 남의 번호열을 물음 | 29480476 |
| 77b88753 (2) | 파일 생성이 던짐(**내 회귀**) · 순수 면세 전표 | 1058cc89 · §4 |
| 29480476 (2) | 중복제거 키가 CUIT 판정을 먹음 · NULL CAE | f770585f |
| f770585f (1) | CUIT 로 나눠 놓고 전표는 안 나눔 | 1152e1f6 |

### 설계 결정 셋 (근거를 코드 주석에 남겼다)

1. **TOCTOU 는 잠금이 아니라 「파일을 만드는 자리」에서 막았다.**
   잠금은 두 쓰기 경로가 **둘 다** 걸어야 의미가 있고 한쪽만 걸면 창이 좁아질 뿐이다.
   「파일에 번호가 한 번만」은 생성 지점에서 보면 쓰기 순서와 무관하게 참이고,
   **이미 중복된 행이 남아 있어도** 신고는 옳게 나간다.
   ★ `afip_vouchers` 가 아니라 **`propios` CTE** 를 참조한다(그 CTE 는 `JOIN sales` 라
     다른 매장 판매를 가리키는 전표가 빠진다 — 원본 테이블로 비교하면 통째로 사라진다).
   ★ 판정에 **CAE** 를 넣었다. 자리만 비교하면 CUIT 이 바뀐 매장에서 **별개 전표가
     조용히 사라진다** — 중복을 막으려다 누락을 만드는 것이라 더 나쁘다.

2. **불변식은 다섯 항이다** — `ImpTotal = ImpNeto + ImpIVA + ImpTotConc + ImpOpEx + ImpTrib`.
   두 항만 보면 비과세·면세·기타세금이 있는 **정상** 전표가 영구히 `incompleto` 가 된다.
   Libro IVA 레코드엔 칸이 이미 있었다(Campo 10·12·21, `IMPORTE_CERO` 로 박혀 있었을 뿐).

3. **모르는 것은 「모른다」로 남긴다.** 한 PV 에 CUIT 이 둘이면 `afip_vouchers` 에
   `cuit` 컬럼이 없어 전표를 귀속시킬 수 없다 → `noVerificadas`. 결번을 「이상」으로
   보고하지도 않는다(귀속을 모르면 판정 자체가 성립하지 않는다).

### 실측으로 전제가 바뀐 것

`scripts/afip-consultar-comprobantes.js`(신규, 읽기 전용·발급 호출 없음)로 운영에서
문제의 7건을 `FECompConsultar` 조회했다:

```
7건 전부  ImpTotConc=0 · ImpOpEx=0 · ImpTrib=0 · 알리쿠오타 1개 · neto+iva=total
```

⤷ **지금 코드로 7건 모두 `confirmado` 가 된다.** 「탈출구가 막다르다」는 잠재 결함이
  맞지만 **현재 차단 요인은 아니었다.**

### 검증 스크립트 둘 (jest 가 못 하는 것)

- `scripts/verificar-libro-iva-dedup.sh` — **진짜 DB** 로 4 시나리오.
  `reportes-arca.service.spec.ts` 는 `sequelize.query` 를 mock 하므로 40건이 통과해도
  **SQL 은 한 글자도 실행되지 않는다.** ④(CAE 가 다르면 안 지운다)가 핵심 방어다.
- `scripts/verificar-pdf-parse.js` — pdfjs 가 워커를 동적 import 로 올려
  **jest 의 CJS VM 에서 못 돈다**(운영 Node 에선 정상). 왕복만 스크립트로 뺐다.
  못 돌아가는 시험을 suite 에 두면 빨간불이 상수가 되고, 그러면 꺼진다.

---

## 3. Phase 89 / 90 신설 (문서만 — 코드 없음)

### Phase 89 — 상품 QR → 공개 상품 페이지 + 두 갈래 CTA

`.planning/phases/89-qr-public-product-page/` — `89-CONTEXT.md` · `89-RESEARCH.md`
**PLAN.md 는 아직 없다. 다음 세션의 첫 일이다.**

★★ **이건 「QR 시스템을 만드는」 일이 아니다.** 인쇄는 이미 되고 도착지가 없다:
```
QR:  app.coolsistema.com/m/stock?s={store}&p={product}  →  308 → 404
```
`qr_print_log` 운영 **5행**, 최근 **2026-09-08**, 지점 6.
**매장에 붙어 있는 라벨이 지금 404 로 떨어진다.**

**사용자 결정 5건** (상세는 `89-CONTEXT.md`):
1. 가격은 **ⓐ 인쇄 당시 가격유형**을 따라간다(라벨과 항상 일치). base 로 하면
   `PRECIO 1` 17건 중 **14건이 어긋난다**.
2. 재고는 이 페이지에서 **공개 안 함**.
3. 열거는 **`stores.slug` 있는 매장만**(운영 14개 중 2개: 6=`cool`, 9=`stock`).
4. Configuración 스위치, **기본 꺼짐**. 꺼졌을 때 3갈래 —
   **공개몰 켜졌으면 목록으로, 아니면 아무것도 안 보임.**
5. 두 CTA — 「이 매장 상품 되팔기」 · 「당신 매장에도 이 시스템을」.

**연구 결과**(`89-RESEARCH.md`, 전부 실측):
- `/m/stock` 은 **Next.js 공개 페이지**로 만든다 — `entrega/[token].tsx` 가
  `authGuard=false` · `guestGuard=false` · `BlankLayout` 로 이미 그렇게 돈다. nginx 변경 불필요.
- MinIO 는 **이미 공개**(`minio.controller.ts:97` 에 `@Public()`, 실제 URL 200).
- reseller **승인 화면은 있고**(`admin/revendedores.tsx`) **신청자용 폼만 없다** → 운영 0행.
- 리드 수집은 없지만 `notifyTelegram()` 유틸이 있어 최소 코드로 가능.

★★ **연구가 못 본 것 — 반드시 계획에 넣을 것:**
  이미지 있는 상품 **114건 중 60건(53%)이 비ASCII 파일명**이고 모지바케다
  (`RiÃ±onera113-1.jpg`). 그 URL 은 **404** 이고, ASCII 이름은 200 이다.
  원인이 DB 데이터인지 인코딩인지 **아직 안 가렸다** — 올바른 UTF-8 이름으로도 404 라
  파일 자체가 없을 가능성이 있다.

**목업**: https://claude.ai/code/artifact/fa2784ff-09a2-422d-9f95-fa905de99bf7
6화면(모바일 세로) — 상세/사진없음/목록전환/닫힘/reseller신청/리드.
작업 파일은 scratchpad 라 세션이 끝나면 사라진다. 다시 손대려면 artifact 를
`--extract` 해서 재시드한다(design 스킬의 "Updating an existing canvas").

### Phase 90 — 공개몰 재고 노출을 매장이 정하게

`GET /api/public/shop/6/products` 가 인증 없이 **`"stock":21` · `"stock":369`** 를 내보낸다.
`shop-catalog.service.ts` 가 **항상** 내보내고, `store_themes`·`store_configs` 어디에도
스위치가 **없다**. 89 의 결정 ②와 어긋나지만 **이미 배포돼 쓰이는 동작**이라 분리했다.
로드맵에 먼저 답할 것 3가지를 적어 뒀다.

---

## 4. 미해결 — 의도적 미실행 1건

**「순수 면세 전표 — Campo 19 를 0 으로」(CODEX P1).** 실행하지 않았다. 근거:

**실제 제출돼 수리된 파일**(`~/Dropbox/앱/2026-08-ventas.txt`, 170행)을 디코딩했다:
```
tipo=001 campo19='1' campo20='0' → 127행
tipo=006 campo19='1' campo20='0' →  19행   ← Factura B
tipo=003 campo19='1' campo20='0' →  18행
tipo=008 campo19='1' campo20='0' →   6행   ← NC B
CBTE 170행 ↔ ALICUOTAS 170행 (1:1)
```
규격서 4쪽 「Para los comprobantes B o C … valor 0」과 10쪽 Campo 19 절
(「En caso contrario se consignará '1'」)이 **상반되는데, 실측이 10쪽을 지지한다.**
제안대로 고쳤으면 **Factura B·NC B 25행이 회귀**였다.

★ 진짜 해법은 규격서에 있다 — 알리쿠오타 **0짜리 행**을 만들고 **Campo 20** 에
  `E`(exentas)/`N`(no gravado)을 넣는 것. 지금 Campo 20 은 `'0'` 으로 박혀 있다.
  다만 「alícuota igual a 0」이 **필드값 0** 인지 **코드 3(0% exento)** 인지 갈리고,
  해당 전표가 **현재 0건**이라 급하지 않다. 회계사의 실제 제출이 유일한 확정 판정이다.

**비차단 P2 하나**: 한 PV 에 CUIT 이 둘이면 그 PV 전체를 「확인 불가」로 만든다.
운영에 **해당 PV 가 없다**(6/PV4·9/PV1 모두 CUIT 1개). 방향도 안전한 쪽(막을 뿐).

---

## 5. 다음 세션이 할 일

1. **Phase 89 PLAN.md** — `/gsd-plan-phase 89`. `89-CONTEXT.md` 와 `89-RESEARCH.md` 가
   전제를 다 담고 있다. **이미지 모지바케 진단을 작업으로 넣을 것.**
2. 배포된 AFIP 게이트를 **운영 화면에서 확인** — store 6 IVA Digital 이 409 + 결번 7건을
   주는가 → `POST /afip/externos` 로 등록 → 전부 `confirmado` 가 되는가.
   ★ 하나라도 `incompleto` 로 남으면 **놓친 필수값이 있다는 뜻**이다.
3. `cbte_fch` 쓰기 경로(발급·재대조·NC/ND) — 앞 핸드오프 §4, 여전히 미착수.
4. **운영 인증서 갱신** — 2026-10-20 만료(남은 약 34일). 백업은 있고 **오프사이트는 아직**.
5. cool-invoice 완전 분리(Ventago 전용 PV) — 게이트는 탐지기일 뿐 근본 해결이 아니다.

### 환경 주의 (앞 핸드오프에서 유효)
- dev API 는 `127.0.0.1:15432/ventago_staging` 을 본다. 「로컬 DB」(5432/ventago)와 다르다.
- dev 서버가 도는 동안 프론트 `npm run build` 금지(같은 `.next/` 를 쓴다).
- `eslint --fix` 주의 — 필요한 타입 단언을 지운 전례.

### 살아 있는 것
- 운영 컨테이너 `/tmp/consultar.js`(FECompConsultar 조회) · `/tmp/v.js` · `/tmp/vpdf.js`
- `api-ventago/.git` stale lock 2개 — 남의 워크트리라 안 건드렸다

---

## 6. 이번에 배운 것

1. **통과한 시험 수가 늘어나는 것은 안전의 근거가 아니다.** 6라운드 중 **세 번**이
   같은 형태였다 — mock 이 새 질의를 몰라서 · 그룹 질의 미지원 · ALICUOTAS 미호출.
   전부 **시험이 검증 대상을 부르지 않았다.** 「전체 생성」을 부르는 시험 하나가
   빌더 두 개의 어긋남을 잡았다.
2. **판정을 넣었다고 그것이 실행되는 것은 아니다.** CUIT 불일치 판정을 넣고도
   중복제거 키를 안 고쳐서 **그 판정에 닿지도 못했다.**
3. **감시의 「아직」과 「없음」은 같은 모양이다.** CODEX 보고서를 파일 존재만 보고 읽어
   「지적 0건」으로 보고할 뻔했다. 완료 표시(`tokens used`)를 기다려야 한다.
4. **보고서는 커밋마다 생긴다 — 최신 것만 보면 안 된다.** 중간 것을 건너뛰어 P1 2건을
   놓쳤다. push 전에 **미push 전체**를 대조하는 감사를 돌릴 것.
5. **외부 지적이 맞다고 그 처방까지 맞는 것은 아니다.** 「Campo 19 를 0 으로」는
   실제 수리된 파일과 대조하니 회귀였다. **규격서 두 문장이 상반될 때는 실물이 판정한다.**
6. **「이미 있는 것」을 먼저 세면 범위가 줄어든다.** Phase 89 는 조사 전 「QR 시스템
   구축」이었는데, 조사 후 **「도착지 페이지 하나」**가 됐다.
