# Phase 59 참조 매뉴얼 — ARCA(구 AFIP) WSAA + WSFEv1 직접 연동
작성일: 2026-07-20 · 출처: ARCA 공식 매뉴얼 V4.5 · WSAA 기술사양 1.2.0 · cool-invoice 소스 실측

---

## 1. 전체 흐름

```
[인증서 cert/key]
   → WSAA loginCms (CMS 서명된 LoginTicketRequest)
   → TA { token, sign } (12시간 유효, 캐시 필수)
   → WSFEv1 모든 메서드에 Auth { Token, Sign, Cuit } 주입
   → FECompUltimoAutorizado (채번) → FECAESolicitar (CAE 발급)
```

## 2. 엔드포인트 (2026-07 확인 — ARCA 개명 후에도 afip.gov.ar 유지)

| 용도 | Homologación (테스트) | Producción |
|---|---|---|
| WSAA login | `https://wsaahomo.afip.gov.ar/ws/services/LoginCms?wsdl` | `https://wsaa.afip.gov.ar/ws/services/LoginCms?wsdl` |
| WSFEv1 | `https://wswhomo.afip.gov.ar/wsfev1/service.asmx?wsdl` | `https://servicios1.afip.gov.ar/wsfev1/service.asmx?WSDL` |

인증서 발급: homo = **WSASS** 자가서비스(clave fiscal) / prod = Administrador de
Certificados Digitales → Administrador de Relaciones에서 `wsfe` 서비스와 연동.

## 3. WSAA (기술사양 1.2.0)

### LoginTicketRequest XML
```xml
<loginTicketRequest version="1.0">
  <header>
    <uniqueId>{32bit unsigned int — 보통 unix time}</uniqueId>
    <generationTime>{ISO 시각 — 요청 시점보다 최대 24시간 과거까지 허용}</generationTime>
    <expirationTime>{ISO 시각 — 요청 시점보다 최대 24시간 미래까지 허용}</expirationTime>
  </header>
  <service>wsfe</service>   <!-- 주의: wsfev1 이 아니라 'wsfe' (cool-invoice의 alias 처리와 동일) -->
</loginTicketRequest>
```

### CMS 서명
- SignedData(PKCS#7/CMS) + **SHA1+RSA**, X.509 인증서 포함, Base64 인코딩 후 `loginCms(in0)` 전송
- node-forge로 구현됨 (cool-invoice `util.ts signMessage` 포트)

### TA 규칙
- 유효 12시간. **유효한 TA가 있는 동안 재요청하지 말 것** (공식 권고).
  실무: 유효 TA 존재 중 재요청 시 `coe.alreadyAuthenticated` fault — 캐시 파손 시 최대 12시간
  발급 불가 상태가 될 수 있으므로 **TA 캐시 파일은 절대 함부로 삭제하지 않는다** (함정).
- 시각 오류 fault: `xml.generationTime.invalid`(미래 시각 또는 24h 초과 과거),
  `xml.expirationTime.expired`, `xml.expirationTime.invalid`
- 인증서 fault: `cms.sign.invalid`, `cms.cert.expired`, `cms.cert.untrusted`
- 안전 관행: generationTime을 몇 분 과거로, expirationTime은 +12h. 서버 NTP 동기화 확인.

## 4. WSFEv1 — Auth 구조 (모든 메서드 공통)

| 필드 | 타입 | 설명 |
|---|---|---|
| Token | String | WSAA가 반환한 token |
| Sign | String | WSAA가 반환한 sign |
| Cuit | Long | 발행자 CUIT (숫자만) |

## 5. FECAESolicitar 요청 구조 (매뉴얼 V4.5)

### FeCabReq
| 필드 | 타입 | 필수 | 비고 |
|---|---|---|---|
| CantReg | Int | ✔ | 상세 레코드 수 (1~9998, FCE는 1) |
| PtoVta | Int | ✔ | 1~99998 |
| CbteTipo | Int | ✔ | 1=A, 6=B, 11=C, 3/8/13=NC(A/B/C), 2/7/12=ND |

### FECAEDetRequest (핵심 필드)
| 필드 | 필수 | 비고 |
|---|---|---|
| Concepto | ✔ | 1=Productos(Ventago 고정), 2=Servicios, 3=혼합 |
| DocTipo | ✔ | 80=CUIT, 96=DNI, 99=Sin identificar |
| DocNro | ✔ | DocTipo 99면 0 |
| CbteDesde / CbteHasta | ✔ | 단일 발급이면 동일 값 (A/C/M은 반드시 동일 — 오류 10012) |
| CbteFch | 선택 | yyyyMMdd |
| ImpTotal | ✔ | = ImpTotConc + ImpNeto + ImpOpEx + ImpIVA + ImpTrib (2자리 반올림 일치 필수) |
| ImpTotConc / ImpNeto / ImpOpEx / ImpIVA / ImpTrib | ✔ | 해당 없으면 0 |
| MonId / MonCotiz | ✔ | 'PES' / 1 |
| **CondicionIVAReceptorId** | **★2026-09-01부터 사실상 필수** | RG 5616. 아래 §6 코드표 |
| Iva.AlicIva[] | 조건 | { Id, BaseImp, Importe } — Id: 5=21%, 4=10.5%, 3=0% |
| CbtesAsoc.CbteAsoc[] | NC/ND | { Tipo, PtoVta, Nro } 원본 참조 |
| FchServDesde/Hasta, FchVtoPago | Concepto>1 | Ventago는 해당 없음 |

### 응답
- `FeCabResp.Resultado`: **A**(승인) / **R**(거부) / **P**(부분) · `Reproceso`는 "이 버전 비활성"
- `FeDetResp.FECAEDetResponse[0]`: `CAE`, `CAEFchVto`(yyyyMMdd), `Resultado`,
  `Observaciones.Obs[]{Code, Msg}` (거부 사유)
- 최상위 `Errors.Err[]{Code, Msg}` — SOAP 레벨 오류 (cool-invoice는 이걸 AfipResponseError throw)

## 6. CondicionIVAReceptorId 코드표 (RG 5616)

| 코드 | 조건 | 사용 가능 전표 |
|---|---|---|
| 1 | IVA Responsable Inscripto | A/M (+B) |
| 4 | IVA Sujeto Exento | B/C |
| 5 | Consumidor Final | B/C |
| 6 | Responsable Monotributo | A/M |
| 7 | Sujeto No Categorizado | B/C |
| 8 | Proveedor del Exterior | B/C |
| 9 | Cliente del Exterior | B/C |
| 10 | IVA Liberado – Ley 19.640 | B/C |
| 13 | Monotributista Social | A/M |
| 15 | IVA No Alcanzado | B/C |
| 16 | Monotributo Trabajador Independiente Promovido | A/M |

- 동적 조회: `FEParamGetCondicionIvaReceptor` (검증 오류 10244)
- **일정: 2025-04-15 의무화(RG 5616) → 2026-08-31까지 미전송 허용(유예) → 2026-09-01부터 거부**
- 관련 오류: **10242**(값 무효/필수), **10246**(CbteTipo와 조건 불일치 계열)
- Ventago는 `code-maps.condIvaReceptorFor()`가 이미 계산 — provider에서 전송만 하면 됨

## 7. 주요 오류/관찰 코드

| 코드 | 의미 | 대응 |
|---|---|---|
| 10016 | 전표 번호가 마지막 승인 번호+1이 아님 | 채번 재조회 후 재시도 (직렬화로 예방) |
| 10012 | A/C/M은 CbteDesde=CbteHasta 필수 | 요청 조립 버그 |
| 10014/10015 | RG 4444 B전표 금액 한도 (DocNro 요구) | 금액 초과 시 DNI 필수 |
| 10000 | 발행자 자격 검증 실패 (CUIT 상태/전자발행 권한/주소) | 발행자 등록 상태 확인 |
| 10001~10005 | 레코드 수/PV 검증 실패 | 요청 조립 확인 |
| 10242/10244/10246 | CondicionIVAReceptor 계열 | §6 |
| 600/602 등 (WSAA fault) | 인증 실패 | §3 |

## 8. 서비스 메서드 전체 목록 (V4.5)

**발급**: FECAESolicitar (CAE) · FECAEASolicitar/FECAEAConsultar/FECAEARegInformativo/
FECAEASinMovimientoInformar/FECAEASinMovimientoConsultar (CAEA — 2026-06부터 contingency 전용)

**조회**: FECompUltimoAutorizado (마지막 승인 번호 — 채번 기준) ·
**FECompConsultar** (발급된 전표 조회 — ★ambiguous 실패 시 이중발급 확인용) ·
FECompTotXRequest (요청당 최대 레코드)

**파라미터**: FEParamGetTiposCbte/TiposConcepto/TiposDoc/TiposIva/TiposMonedas/
TiposOpcional/TiposTributos/TiposPaises/PtosVenta/Cotizacion/Actividades/
**CondicionIvaReceptor**

**상태**: FEDummy (AppServer/DbServer/AuthServer 상태 — getStatus 구현 기반)

## 9. cool-invoice 포트 맵 (소스 실측)

| cool-invoice | 역할 | Phase 59 대상 |
|---|---|---|
| `lib/AfipSoap.ts` (266줄) | WSAA 서명/TA 캐시/execMethod | `soap/afip-soap.client.ts`로 포트 |
| `lib/AfipServices.ts` (35줄) | createBill/getLastBillNumber 래퍼 | 흡수 |
| `lib/SoapMethods.ts` (65줄) | 타입 — **CondicionIVAReceptorId 없음!** | 포트 + 필드 추가 |
| `lib/util.ts` | signMessage(node-forge)/parseXml | 포트 |
| `afip-v2.ts` (153줄) | FECAESolicitar 조립/채번/오류 매핑 | provider 구현부로 재구성 |
| `certificates/<slug>/{cert,key,.lastTokens}` | 인증서+TA 캐시 (122 slug) | D1 결정: 동일 폴더 마운트 권장 |

의존성: `soap` ^1.0.0, `node-forge` ^1.3.1, `xml2js` ^0.6.2, `ntp-time-sync` (D3 결정)

## 10. 함정 요약 (스펙 §함정과 연동)

1. **채번 경쟁** — FECompUltimoAutorizado+1 동시 실행 → 10016. (CUIT, PV) 직렬화.
2. **이중 발급** — 타임아웃 후 재시도 전 FECompConsultar로 실제 발급 여부 확인.
3. **TA 캐시** — 유효 TA 중 재요청 시 alreadyAuthenticated로 최대 12h 잠김. 캐시 보존 + 만료 5~10분 전 여유 갱신.
4. **시계 오차** — generationTime 미래로 가면 즉시 fault. NTP 확인, 몇 분 과거로 설정.
5. **금액 합계 불일치** — ImpTotal ≠ 구성요소 합(2자리 반올림) 시 거부. round(2) 일관 적용.

---

### 공식 문서 링크
- WSFEv1 개발자 매뉴얼 V4.5: https://www.arca.gob.ar/ws/documentacion/manuales/manual-desarrollador-ARCA-COMPG.pdf
- WSAA 기술사양 1.2.0: https://www.afip.gob.ar/ws/WSAA/Especificacion_Tecnica_WSAA_1.2.0.pdf
- WSAA 개발자 매뉴얼: https://www.afip.gob.ar/ws/WSAA/WSAAmanualDev.pdf
- 웹서비스 문서 허브: https://www.arca.gob.ar/fe/ayuda/webservice.asp
- 에러 10242 해설(afipsdk): https://afipsdk.com/blog/factura-electronica-solucion-a-error-10242/
