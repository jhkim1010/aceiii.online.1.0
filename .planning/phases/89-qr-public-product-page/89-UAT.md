# Phase 89 — UAT (실물)

**일시:** 2026-09-17 (배포 완료 직후) · 확인자: 사용자 + Claude
**배포 상태:** api-ventago `89b3f70d` (build api-new-coolsistema #905 SUCCESS) ·
ventago-app `5931ca9` (build front-coolsistema #741 SUCCESS) · 컨테이너 재생성 확인됨.

★ **이 문서는 자동화로 확인 가능한 부분만 채워져 있습니다.** 실물 라벨을 폰 카메라로
찍는 것과 화면을 눈으로 보고 판단하는 것은 사람만 할 수 있습니다 — 그 항목은
**관측을 지어내지 않고** "사용자 확인 필요"로 남겼습니다. 아래 "사용자가 확인할 것"
섹션을 그대로 따라 하면 됩니다.

---

## 성공 판정

| # | 판정 | 결과 | 관측 |
|---|---|---|---|
| 1 | 실물 라벨을 폰으로 찍어 페이지가 열린다(계정 없이) | **사용자 확인 필요** | 자동화로는 URL이 비로그인 200으로 열리는 것까지만 확인됨(아래 「자동 확인 결과」). 실제 종이 라벨을 카메라로 찍어 여는 것은 사람만 가능 |
| 2 | 매장·지점·사진·가격이 보이고 가격이 라벨과 같다(다르면 병기) | **사용자 확인 필요** | `qr_precio_publico`가 현재 꺼져 있어(`false`) 토글을 켜야 상세 화면이 뜬다 — 토글 자체를 Configuración에서 찾아 누르는 것이 판정의 일부 |
| 3 | 두 CTA를 끝까지 눌러 각각 실제 화면에 도달한다 | **사용자 확인 필요** | 판정 2가 선행돼야 화면 하단 CTA에 도달 가능. 전/후 DB 행 수 대조로 제출 성공 여부를 Claude가 확인할 준비는 돼 있음(아래 「운영 DB 기준선」) |

---

## 자동 확인 결과 (배포 직후 Claude가 실행, 2026-09-17)

```
$ curl -s -o /dev/null -w '%{http_code}\n' 'https://app.coolsistema.com/m/stock?s=6&p=1'
308
$ curl -s -o /dev/null -w 'final=%{http_code} redirects=%{num_redirects}\n' -L 'https://app.coolsistema.com/m/stock?s=6&p=1'
final=200 redirects=1
$ curl -sI 'https://app.coolsistema.com/m/stock?s=6&p=1' | grep -i location
location: /m/stock/?s=6&p=1

$ curl -s -w '\n%{http_code}\n' 'https://newapi.coolsistema.com/api/public/qr-stock/6/1'
{"mode":"shop_redirect","storeName":"cool","logoUrl":null,"branchName":null,"shopUrl":"https://cool.coolsistema.com","storeApodo":null,"product":null}
200

$ curl -s -o /dev/null -w '%{http_code}\n' -X POST -H 'Content-Type: application/json' -d '{}' 'https://newapi.coolsistema.com/api/public/ventago-leads'
400

$ ssh jhkim-server "docker logs --since 10m api_ventago 2>&1 | grep -ci 'does not exist\|qr_precio_publico'"
0
```

★ **`/m/stock?s=6&p=1`가 308을 낸 것은 결함이 아닙니다** — Next.js의 표준 trailing-slash
리다이렉트로, 배포 전에도 있었던 동작입니다(배포 전엔 `308 → 404`, 지금은 `308 → 200`).
plan의 검증 명령 자체가 `-L`(리다이렉트 따라가기)을 쓰므로 `-L` 붙인 결과(`200`)가
기대와 일치하는 값입니다.

★ `mode:"shop_redirect"`도 기대와 일치합니다 — store 6은 `qr_precio_publico=false` +
`slug='cool'`(공개몰 켜짐)이므로, 3갈래 판정표대로 "공개몰로 가는 버튼" 화면이 뜨는
것이 배포 직후 기본값입니다.

★ 운영 로그에 `does not exist`/`qr_precio_publico` 관련 오류 0건 — 구버전이든 신버전이든
스키마 문제 없이 정상 동작 중입니다.

---

## 운영 DB 기준선 (제출 전/후 대조용 — Claude가 배포 직후 기록)

```
$ ssh jhkim-server "sudo -u postgres psql -p 5434 -d ventago -tAc \
    \"SELECT (SELECT count(*) FROM reseller.resellers), (SELECT count(*) FROM ventago_leads);\""
0|0
```

★ 시작값이 둘 다 0 — 실측(2026-09-16) 그대로. 사용자가 두 CTA를 제출한 뒤 Claude가
같은 조회를 다시 돌려 증가분을 이 문서에 채워 넣겠습니다.

현재 매장 6 설정(배포 직후, 아무것도 안 바뀐 상태):
```
$ ssh jhkim-server "... SELECT store_id, qr_precio_publico FROM store_configs WHERE store_id=6;"
6|f
$ ssh jhkim-server "... SELECT id, slug, alias_name, name FROM stores WHERE id=6;"
6|cool|cool|coolsistema
```

지금 매장에 붙어 있는 실물 라벨(운영 `qr_print_log`, 전부 지점 6 = "coolsistema"):

| product_id | price_type_id | 인쇄 당시 가격 | 상품명 | 인쇄일 |
|---|---|---|---|---|
| 264 | 11 | $22.000 | [CAMISA/CHINA] CAMISA TRAVELL | 2026-07-16 |
| 281 | 11 | $38.000 | [CONJUNTOS] CONJUNTO DEPORTIVO | 2026-07-16 |
| 89 | 11 | $32.000 | pañuelo k-pop | 2026-07-16 |
| 308 | 11 | $15.000 | DUMMY REMERA PRODUCCION MADRE | 2026-09-08 |
| 222 | 11 | $45.000 | [ABRIGOS/GENERAL] CAMPERA DE PAÑO | 2026-09-08 |

---

## 사용자가 확인할 것 (따라 하기 — 순서대로)

### A. 옛 라벨 스캔 — 계정 없이 열리는가 (성공 판정 1)

1. 매장(coolsistema, 지점 6)에 붙어 있는 QR 라벨 아무거나(위 표의 5개 상품 중 하나)를
   **폰 카메라**로 찍어 링크를 엽니다.
2. **로그인하지 않은 상태**로 페이지가 열리나요? (404나 로그인 화면이 뜨면 실패)
3. 지금은 설정이 꺼져 있어(`qr_precio_publico=false`) + 공개몰이 켜져 있으므로
   **"공개몰로 가는 버튼"**이 보여야 합니다(자동 확인 결과와 동일한 화면). 버튼을 눌러
   `https://cool.coolsistema.com`이 실제로 열리는지 확인해 주세요.

### B. 설정을 켜고 상품 상세 확인 (성공 판정 2)

4. 웹에서 store 6 admin 계정으로 로그인 → **Configuración › Operación › "QR del producto"**
   탭을 찾아 토글을 **켭니다**. (탭이 안 보이면 그 자체가 실패입니다 — 알려 주세요.)
5. 같은 라벨을 다시 찍습니다 → 이제 **상품 상세**(매장명 · 사진 또는 "Sin foto" · 가격)가
   떠야 합니다.
6. 가격을 확인해 주세요:
   - 화면의 큰 가격이 그 가격유형의 **현재 가격**인가요?
   - 종이 라벨의 숫자와 **같다면** → 화면에 "Precio en la etiqueta" 같은 병기 문구가
     **없어야** 정상입니다(이 "없음"이 판정 대상입니다).
   - 종이 라벨의 숫자와 **다르다면** → `Precio en la etiqueta: $X — el precio cambió.`가
     보이고, 그 `$X`가 종이에 인쇄된 숫자와 같아야 합니다.
7. 매장명이 맞나요? 지점명(coolsistema)이 나오나요(신 라벨만 — 옛 라벨은 안 나오는 게 정상)?

### C. (선택) 새로 인쇄한 라벨 — QR 크기 회귀 확인

8. POS에서 같은 상품의 QR 라벨을 **새로 1장 인쇄**합니다(`&b=`·`&pt=`가 실립니다).
9. 그 라벨을 폰으로 찍어 **읽히는지** 확인합니다.
   ★ 참고로 넘겨받은 사실: zebra 라벨 QR은 50×25mm·203dpi에서 33모듈·배율5·
   한 변 20.6mm·모듈폭 0.63mm·ECC M이고, `&b=`·`&pt=` 추가로 **크기가 전혀 늘지
   않았습니다**(휴대폰 최소 요구 0.25~0.33mm의 약 2배). 그래도 실물로 확인이
   필요합니다 — 인쇄물·카메라는 코드로 증명이 안 됩니다.
10. 읽히면 지점명이 나오는지, "Según la última impresión..." 문구가 사라졌는지 확인합니다.

### D. 두 CTA 끝까지 누르기 (성공 판정 3)

설정이 켜진 상태(위 B)에서 상세 화면 하단의 두 버튼을 각각 눌러 주세요.

**CTA① 이 매장의 reseller 신청**
11. 폼이 열리나요? 매장 선택 목록이 **보이면 안 됩니다**(QR의 매장으로 고정돼야 함).
12. 이름·전화·신분증번호·비밀번호 + 사진 3장(아무 사진이나)으로 **제출**합니다.
13. 성공 문구가 뜨나요?
14. superadmin/admin으로 `/admin/revendedores`를 열어 방금 신청이 pending 목록에
    보이는지 확인해 주세요.

**CTA② 당신 매장에도**
15. `Crear mi tienda`를 누르면 `/register?ref=cool`이 열리나요?
16. "¿Quién te recomendó?" 칸이 `cool`로 미리 채워져 있나요?
17. **가입을 끝까지 하지 마세요**(CUIT·주소·이중 OTP 필요) — 도달과 프리필까지만 확인.
18. (선택) 로그인한 창에서 같은 버튼을 누르면 어디로 튕기는지도 알려 주세요.

**이탈 받이**
19. 맨 아래 작은 텍스트 링크("Dejanos tu teléfono")를 눌러 이름·전화를 입력하고
    제출합니다. 가입 버튼보다 **작아 보이나요**?
20. 텔레그램 채널에 알림이 왔나요? (안 와도 괜찮습니다 — DB에는 남습니다. "알림만
    안 왔다"로 알려 주시면 됩니다.)

### E. 끝나고

21. 토글(B의 4번)을 원래대로 끌지, 켠 채로 둘지 알려 주세요. 둘 다 의도된 상태입니다.

---

## 남긴 시험 데이터와 그 영향

아직 없음 — 위 A~D를 사용자가 수행하면 운영 `reseller.resellers`·`reseller_tienda_link`·
`reseller_documents`·`ventago_leads`에 실제 행이 생깁니다. **지우지 않습니다**(상시 규칙).
사용자 확인이 끝나면 Claude가 전/후 DB 조회로 이 섹션을 채웁니다.

## 이 phase가 닫지 않은 것

- **숫자 ID 열거를 막지 못한다.** 공개몰 OFF 매장만 "인쇄 기록 존재"로 범위를 줄였을
  뿐이다. 공개몰 ON 매장(`GET /api/public/shop/:id/products`)은 이미 전 상품을 목록화한다.
- **구 라벨은 어느 라벨인지 서버가 모른다.** `b`·`pt` 없는 URL은 영원히 "최신 인쇄분" 추정.
- **`qr_print_log`를 쓰는 경로가 하나뿐**(`mark_qr_printed`) — `POST /print/qr`(단일 라벨)로만
  인쇄된 상품은 공개몰 OFF 매장에서 404. 오늘 영향은 0(그런 매장 없음).
- **CODEX P2 3건**(89-09 준비 단계 발견, 배포는 막지 않음) — 상세는
  `.planning/phases/89-qr-public-product-page/deferred-items.md`:
  - `leads.service.ts` fire-and-forget 통지가 프로세스 재시작에 겹치면 `pending` 영구 정지 가능
  - `ventago_leads.store_id`가 `ON DELETE CASCADE`라 매장 삭제 시 중앙 리드 데이터 소실 위험
  - `check-cta-destinos.sh`의 실HTTP 게이트가 404만 실패로 봄(500/401 안 잡음)
- CODEX 자동 훅이 phase 89 40개 커밋을 전부 건너뛴 사실도 같은 파일에 기록됨(원인 미확인).
- 이미지 파일명 모지바케 **수정**(89-02는 진단만) — 후속 결정 필요
- 공개몰 재고 수량 무조건 공개 — Phase 90으로 분리됨
- reseller 신청자 승인/거부 알림 수단 없음 — reseller 포털 없음
- **추천 가입이 승인까지 간 적이 없다** — 운영 `referral_credits` 0행

---
*Phase: 89-qr-public-product-page*
*작성: 2026-09-17 (배포 직후, 실물 확인 대기)*
