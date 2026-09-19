# 절차서 — Ventago 전용 인증서 + 전용 PV (2026-09-19)

코드는 **전부 준비됐다.** 남은 것은 ARCA 포털 작업(사용자)과, 그 뒤 한 번씩 부르는
엔드포인트다. 이 문서는 그 순서만 적는다.

★ **왜 하는가**: cool-invoice 와 (a) 같은 인증서 (b) 같은 punto de venta 를 쓰고 있다.
  (a) 때문에 TA 캐시를 못 나누고, (b) 때문에 **우리가 안 만든 번호가 우리 원장의
  결번**으로 나타난다 — 그 결번은 IVA Digital 신고서에서 통째로 빠진다.

★★ **시한이 있다**: 운영 인증서 `CN=CNCOOLSISTEMA2024` 가 **2026-10-20 만료**.
  어차피 갱신해야 하므로, 갱신을 「전용 인증서 신규 발급」으로 하면 한 번에 끝난다.

---

## 0. 먼저 — cool-invoice 쪽 조율 (사람)

우리가 전용 인증서로 옮겨도 **cool-invoice 는 자기 인증서를 따로 갱신해야 한다.**
지금은 같은 파일을 쓰므로, 우리만 새것으로 가면 **그쪽이 10/20 에 멎는다.**
→ 그쪽에 「10/20 만료, 각자 갱신」을 알린다.

---

## 1. ARCA — 전용 인증서 (사용자)

AFIP/ARCA 포털 › **Administración de Certificados Digitales**

1. 새 **alias(Computador Fiscal)** 를 만든다. 예: `ventago-st6`
   ★ 같은 CUIT 에 인증서를 여러 개 둘 수 있다. 기존 `CNCOOLSISTEMA2024` 는 그대로 둔다.
2. 그 alias 에 **CSR 을 올린다** — CSR 은 우리가 만든다(아래 2번). 손으로 openssl
   을 쓸 필요 없다.
3. 서명된 `.crt` 를 내려받는다.
4. **서비스 위임**: 그 alias 에 `wsfe`(Facturación Electrónica) 를 위임한다.
   ★ 이것을 빠뜨리면 인증서는 멀쩡한데 발급만 실패한다. 우리 활성화 단계가
     그 상태를 **미리** 잡아낸다(아래 4번).

## 2. CSR 생성 (앱)

```
POST /api/afip/cert/csr
{ "slugDestino": "ventago_st6", "issuerId": 1 }
```
→ 응답의 `csr` 을 ARCA 포털에 붙여 넣는다.

★ 이 단계는 **새 폴더에만** 쓴다. 지금 발급에 쓰이는 키·인증서는 건드리지 않으므로
  **이 작업 중에도 판매가 계속된다.**

## 3. 서명본 업로드 (앱)

```
POST /api/afip/cert/upload
{ "crt": "<.crt 전문>", "slugDestino": "ventago_st6", "issuerId": 1 }
```
검증(CUIT 일치 · 키짝 · 유효기간 · CA 환경)을 통과하면 파일과 **완료 표식**을 놓는다.

★ 여기까지는 **아직 아무것도 바뀌지 않는다.** 발행자는 그대로 옛 인증서로 발급한다.

## 4. 활성화 (앱) — ★ 여기가 전환점

```
POST /api/afip/cert/activar
{ "slug": "ventago_st6", "issuerId": 1 }
```
**실제로 WSAA 에 로그인해 보고**, 성공해야만 `cert_slug` 를 옮긴다.
실패하면 아무것도 안 바뀌고 사유를 돌려준다(대개 1-4 의 서비스 위임 누락).

★ 되돌리기: `POST /api/afip/cert/revertir { "slug": "coolsistema" }`
  파일은 남으므로 고친 뒤 다시 활성화하면 된다.

★★ 활성화되면 **TA 캐시도 자동으로 우리 폴더로 간다**(인증서가 다르므로 TA 가
  애초에 독립이다). 여기서 G1·G2 가 함께 풀린다.

## 5. 확인

- 발급 한 건(가능하면 소액)으로 CAE 가 나오는지 본다.
- Configuración ▸ Facturación 에서 「carpeta compartida」 표시가 사라졌는지 본다.

## 6. 발급 차단을 켠다 (운영 설정)

공유 폴더를 쓰는 **운영 발행자가 하나도 없어졌을 때** 켠다. 그때는 아무것도 막지
않으므로 무해하고, 이후의 회귀만 잡는다.

```
AFIP_BLOQUEAR_EMISION_CARPETA_COMPARTIDA=true
```

---

## 7. 전용 PV (별개 · 언제든)

### 7-1. ARCA (사용자)
새 **punto de venta** 를 등록한다(Web Services 용). 그리고 알려 준다:
① 번호 ② 어느 CUIT ③ 언제부터.

### 7-2. 이전 (앱)
```
POST /api/afip/issuers/1/punto-venta
{ "puntoVenta": 7 }
```
★ **AFIP 최종번호 조회를 먼저** 하고, 실패하면 아무것도 바꾸지 않는다.
  ARCA 등록 전에 불러도 안전하다 — 거절될 뿐이다.

★★ 이전 뒤에도 **옛 PV 4 의 전표는 그대로 조회·재출력되고, 연속성 검증도 계속
  돈다**(전표의 `issuer_id` 로 옛 번호열을 같은 발행자에 붙인다). 그래서 신고 파일
  게이트가 전환 때문에 닫히지 않는다.

---

## 안 하는 것

- **인증서를 복사하지 않는다.** 복사하면 두 시스템이 **같은 CEE** 를 쓰게 되어
  TA 잠금이 그대로다 — 폴더만 갈라진다. 근거는
  `.planning/ANALISIS-2026-09-19-phase57-게이트웨이이탈-F1F5-실측.md` 2절.
- **레거시 원본을 지우지 않는다.** cool-invoice 가 읽고 있다. 우리는 읽기를
  그만둘 뿐이다.
