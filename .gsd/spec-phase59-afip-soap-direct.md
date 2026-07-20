# SPEC: Phase 59 — ARCA(구 AFIP) SOAP 직접 발행 (WSAA + WSFEv1)
생성일: 2026-07-20 · 상태: ★Wave A+B 완료 — homo CAE 발급 검증 통과(C/B/NC, CondIVA 포함). Wave C(운영 전환) 대기

## 목표
cool-invoice 게이트웨이 의존 없이 Ventago API가 직접 WSAA 인증 + WSFEv1로 CAE를 발급한다.
`store_configs.afip_provider='soap'` 전환만으로 매장별 점진 이행이 가능해야 한다 (팩토리 구조는 Phase 57에서 준비됨).

## ★긴급 배경 — RG 5616 데드라인 (2026-09-01)
- `CondicionIVAReceptorId`(수신자 IVA 조건)는 RG 5616에 따라 2025-04-15부터 의무이나
  **2026-08-31까지 유예 기간 → 2026-09-01부터 미전송 요청은 ARCA가 거부**한다.
- **현행 cool-invoice 게이트웨이는 이 필드를 전송하지 않는다** (소스 실측:
  `SoapMethods.ts`의 `IParamsFECAESolicitar`에 필드 자체가 없음. Ventago가 보내는
  `condicionIVAReceptorId`를 게이트웨이가 무시). → **약 6주 뒤 현행 발급 경로 전체 장애 위험.**
- Ventago는 이미 `code-maps.condIvaReceptorFor()`로 값을 계산·전송 중 → SOAP 직접 구현에
  필드 하나만 넣으면 즉시 해결된다.
- **플랜 B(병행 권장)**: 게이트웨이(별도 저장소 gitlab WillAular/invoiceah)에 필드 1개 추가
  패치 — Ventago 외 구 시스템 사용 매장들도 보호됨. Phase 59와 독립적으로 진행 가능.

## 배경 및 컨텍스트 (조사 실측 2026-07-20)

### 살아있는 참조 구현 = cool-invoice (운영 중, 포트 대상)
- 위치: 운영서버 `/var/lib/jenkins/workspace/cool-invoice` (docker `coolinvoice`)
- 스택: `soap` ^1.0.0 + `node-forge`(CMS 서명) + `xml2js` + `ntp-time-sync` + moment/luxon
- `lib/AfipSoap.ts` (266줄): WSAA loginCms — LoginTicketRequest XML 생성(NTP
  `time.afip.gov.ar` 시각 사용) → node-forge CMS 서명 → TA(token+sign) 파일 캐시
  `.lastTokens` (12시간, `tokensExpireInHours`) → `execMethod()`가 모든 WSFE 호출에
  Auth(Token/Sign) 자동 주입, `Errors.Err` 발견 시 `AfipResponseError`(code 포함) throw
- `afip-v2.ts`: 채번 = `FECompUltimoAutorizado`+1 → `FECAESolicitar` 조립
  (2자리 반올림, `Iva.AlicIva`, NC는 `CbtesAsoc`, Concepto>1이면 서비스 날짜 3종)
- 인증서: `/var/lib/jenkins/workspace/certificados/<slug>/{cert,key}` — **122개 slug**,
  coolinvoice 컨테이너에 `/home/node/app/certificates` rw 마운트. slug = afip_issuers.cool_user
- 게이트웨이 미지원: 마지막 번호 조회 API 없음(내부 채번), CondicionIVAReceptorId 없음

### ARCA 웹서비스 현황 (2026-07 리서치)
- 엔드포인트는 ARCA 개명 후에도 **afip.gov.ar 도메인 그대로 유효**:
  - WSAA homo `https://wsaahomo.afip.gov.ar/ws/services/LoginCms?wsdl`
  - WSAA prod `https://wsaa.afip.gov.ar/ws/services/LoginCms?wsdl`
  - WSFEv1 homo `https://wswhomo.afip.gov.ar/wsfev1/service.asmx?wsdl`
  - WSFEv1 prod `https://servicios1.afip.gov.ar/wsfev1/service.asmx?WSDL`
- 개발자 매뉴얼 **V4.5**: arca.gob.ar/ws/documentacion/manuales/manual-desarrollador-ARCA-COMPG.pdf
- 인증서 발급: homo = **WSASS**(자가서비스, clave fiscal), prod = Administrador de
  Certificados Digitales + Administrador de Relaciones로 wsfe 서비스 연동
- CondicionIVAReceptor 코드 (FEParamGetCondicionIvaReceptor로 동적 조회 가능):
  1 RI · 4 Exento · 5 Consumidor Final · 6 Monotributo · 7 No Categorizado ·
  8 Proveedor Exterior · 9 Cliente Exterior · 10 Liberado L.19640 · 13 Monotributo Social ·
  15 IVA No Alcanzado · 16 Monotributo Independiente Promovido
  (미전송/오류 시 에러 10242/10246)
- CAEA: 2026-06부터 contingency 전용 지위 → Phase 58 C3(오프라인 근본 해결) 후보 유지

### Ventago 측 현황
- provider 팩토리·인터페이스 완비, `soap-direct.provider.ts`는 16줄 스텁(즉시 throw)
- ambiguous 실패 분류 체계 존재(이중 CAE 방지) — SOAP 직접에선 Observaciones 코드를
  직접 받으므로 게이트웨이(전부 status 500 뭉뚱그림)보다 **정밀해짐**
- ★운영 `afip_issuers` **0행** — Phase 57 발급 경로는 아직 미가동 (현행 발급은 구 API →
  게이트웨이 경로). `store_configs.afip_provider='ws'` 8행 존재하나 **store 6이 중복 2행** —
  데이터 정리 필요
- afip_issuers에 cert 관련 컬럼 없음 (cool_user slug만 존재)

## 기술 스택
- Node.js(NestJS) — api-ventago 내 신규 `src/app/afip/soap/` 서브모듈
- 신규 의존성: `soap`, `node-forge`, `xml2js` (ntp-time-sync는 결정 사항 D3)
- DB: 기존 Sequelize 연결만 사용 — **신규 Pool 생성 금지**
- ESLint: api-ventago 기존 설정

## 결정 필요 (승인 시 함께 답변 요청)
- **D1. 인증서 보관**: (a) 게이트웨이와 동일 폴더를 api_ventago 컨테이너에도 마운트
  (마이그레이션 불필요, 즉시 122개 재사용 — **권장**) vs (b) afip_issuers에 암호화 컬럼
- **D2. 플랜 B 병행**: 게이트웨이에 CondicionIVAReceptorId 패치도 같이 할지
  (구 시스템 매장 보호 — **권장**, 별도 저장소 1필드 작업)
- **D3. 시각 소스**: NTP(time.afip.gov.ar) vs 서버 시계(-1분 여유) — 운영서버 NTP 동기화
  확인 후 결정

## 태스크 목록

### Wave A — 코어 포트 (api-ventago)
- [x] TASK-1: `soap/afip-soap.client.ts` — AfipSoap 포트 (WSAA CMS 서명, TA 캐시,
      execMethod). cert 로딩 추상화(D1), TA 캐시는 slug별 파일 유지 — 파일: 신규
- [x] TASK-2: `soap/wsfe.types.ts` — SoapMethods 포트 + **CondicionIVAReceptorId 추가** — 파일: 신규
- [x] TASK-3: `providers/soap-direct.provider.ts` 실구현 — issueCae(채번→FECAESolicitar,
      CondicionIVAReceptorId 포함), getLastVoucher(FECompUltimoAutorizado), getStatus(FEDummy)
- [x] TASK-4: 실패 분류 — AfipResponseError(code)=확정 거부, Resultado='R' Observaciones=확정,
      transport/timeout=ambiguous. **ambiguous 시 FECompConsultar로 발급 여부 확인 경로** 추가
- [x] TASK-5: 채번 직렬화 — (cuit, ptoVta, cbteTipo) 단위 mutex(프로세스 내) — 함정 1 대응
- [x] TASK-6: 디버그 로그 — 요청/응답 원문(토큰 마스킹) 로거, 매뉴얼 V4.5 에러코드 매핑 주석

### Wave B — 검증
- [x] TASK-7: homologación 인증서 확보 — CoolSyncro/afip-certs 기존 인증서 재사용(coolsyncrohomo1, ~2028-07) + FEDummy/FEParamGetCondicionIvaReceptor 스모크
- [x] TASK-8: homo E2E — Factura B(CF, cond 5) / Factura A(RI, cond 1) / NC(CbtesAsoc)
- [x] TASK-9: 단위테스트(기존 *.spec.ts 패턴) + ESLint 0개
- [x] TASK-10: ambiguous 재발급 금지 회귀 테스트

### Wave C — 운영 전환 (승인 게이트)
- [ ] TASK-11: store 6 store_configs 중복 행 정리 (운영 DB — 사용자 실행)
- [ ] TASK-12: 파일럿 매장 afip_issuers 등록 + `afip_provider='soap'` 전환 → 실발급 검증
- [ ] TASK-13: (플랜 B, D2 승인 시) 게이트웨이 CondicionIVAReceptorId 패치 — 별도 배포

## 완료 기준
- homo 환경 CAE 발급 성공 (CondicionIVAReceptorId 포함, 에러 10242/10246 없음)
- ESLint 오류 0개
- ambiguous 시 재발급 시도 0 (테스트로 보증)
- 신규 DB Pool 생성 없음, 신규 연결 누수 없음
- 기존 ws 경로 무영향 (팩토리 폴백 유지)

## 함정 3가지
1. **채번 경쟁**: `FECompUltimoAutorizado+1`은 동시 발급 시 중복 번호 → 거부(10016 계열).
   같은 (CUIT, PV) 직렬화 필수. 다중 인스턴스 배포 시 DB advisory lock 고려.
2. **이중 발급**: 타임아웃/모호 실패 후 무조건 재시도 금지 — CAE가 이미 나갔을 수 있다.
   FECompConsultar로 확인 후 진행 ('verificar' 수작업보다 자동 확인이 안전).
3. **시계 오차**: WSAA는 generationTime/expirationTime 관용이 좁다 — 서버 시계가 어긋나면
   토큰 발급 실패. NTP 확인(D3) + generationTime을 수 분 과거로 설정하는 관행 유지.

## 점검 포인트
- **1주 후**: homo CAE 발급 E2E 통과 여부
- **1개월 후**: 파일럿 매장 soap 전환 + **9/1 데드라인 전 전 매장 이행 계획 확정** (또는 플랜 B 배포 완료)
- **3개월 후**: 게이트웨이 의존 완전 제거 판단, CAEA(contingency) 채택 여부 재평가

## 금지사항 / 주의사항
- 운영 DB DDL·데이터 변경, 컨테이너 재시작, push는 승인 게이트
- 기존 ws provider 코드 경로 수정 금지 (폴백 안전망)
- 인증서/개인키/토큰을 로그·응답에 절대 노출 금지
- prod 엔드포인트로의 테스트 발급 금지 — homo에서만 검증 후 전환
