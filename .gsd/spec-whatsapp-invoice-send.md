# SPEC: Facturar "WhatsApp"(digital) 출력 실제 발송 배선 + Emitir 진행상황 피드백
생성일: 2026-07-22

## 목표
Facturar 모달의 "WhatsApp" 라디오(output='digital')를 실제 발송으로 배선한다.
AFIP 발급 성공 후 기존 Click-to-Chat 인프라로 고객 WhatsApp에 comprobante 안내를
보내고(wa.me deeplink), Emitir 전 과정의 진행상황을 사용자에게 시각적으로 알린다.

## 배경 및 컨텍스트
- 현재 문제(운영 로그 실측 2026-07-22):
  - venta #79 발급 성공 `[SoapDirect] CAE 발급 성공 nro=69`, `POST /api/afip/vouchers 201 2781ms`
  - 그러나 digital 발송·피드백 흔적 전무 → 사용자 "아무 말도 없어"
- 원인 2층:
  1. 백엔드: `afip.controller.ts issue()`는 `output`을 안 씀(echo만). `AfipOutputService.dispatch()`
     의 digital 분기는 스텁(`return { ok: true }`), 전화번호 필드도 없음.
  2. 프론트: `PartialInvoiceModal.onConfirm` 성공 시 `onIssued()`+닫기만, 피드백 없음.
- ★재사용 자산(Phase 29 WhatsApp Click-to-Chat, 이미 존재):
  - `POST /whatsapp/click-to-chat` { clientId, templateKey, variables } → { url, ... }
    (대표자 신원 검증 → 고객 whatsapp strict 조회 → phone-normalizer(E.164/AR) →
     wa.me URL + 감사로그. 1회 최대 3쿼리, 모델 메서드=자동 release. pool 안전.)
  - 템플릿 `receipt_resend` (variables: fullname, saleId, total, date, storeName;
    fullname·storeName은 백엔드 자동 보강 → caller는 saleId/total/date만 전달)
  - 프론트 기존 패턴: `views/whatsapp/WhatsAppSendDialog.tsx`, `hooks/api/useWhatsAppTemplates.ts`
- 데이터 확인(운영 store 6 coolsistema):
  - 대표자 user 7 jungho, whatsapp_phone `+541130123113`
  - sale 79 client_id=23840 (GONZALEZ PAOLA ELIZABETH), clients.whatsapp `2302 521806`

## 기술 스택
- 프론트: Next.js 13 + MUI 5 (`PartialInvoiceModal.tsx`), apiConnector
- 백엔드: NestJS (변경 최소 — 신규 템플릿 1개만, 순수함수/DB무접근)
- DB: PostgreSQL 18. 신규 pool 사용 없음(기존 click-to-chat 재사용, 이미 pool 안전)
- ESLint: 프로젝트 규칙 엄격(warning=build fail). newline-before-return 등 준수

## 설계 결정 (D)
- D1: 발송 방식 = **wa.me deeplink(Click-to-Chat) 재사용**. 서버 자동발송(Cloud API) 아님.
  → 대표자(jungho) WhatsApp 세션에서 새 탭이 열리고 [전송]은 사람이 누른다(기존 한계 계승).
  → pool·외부 API 비용 0, 즉시 도입 가능.
- D2: 템플릿 = MVP는 기존 `receipt_resend` 재사용(백엔드 무변경). 
  선택적 개선: CAE/número/QR 링크 포함 신규 `invoice_issued` 템플릿(TASK-5, optional).
- D3: 호출 시점 = AFIP issue 성공(res.ok) 직후, output==='digital'일 때만 click-to-chat 호출.
  발급과 발송을 분리 → 발송 실패해도 comprobante는 유효(fail-safe).
- D4: 진행상황 = 모달 내 상태머신(idle→emitiendo→emitido→abriendo_wa→listo / error)
  + MUI Snackbar/Alert. digital은 "WhatsApp 창을 열었습니다 — [전송] 버튼을 눌러 완료하세요" 안내.

## 태스크 목록
- [ ] TASK-1: 프론트 whatsapp 발송 서비스 확인/추가 — 기존 호출 패턴 재사용
      파일: ventago-app/src/services/whatsapp.service.ts (없으면 신설, 있으면 재사용)
      · clickToChat({ clientId, templateKey, variables }) → apiConnector.post('/whatsapp/click-to-chat')
- [ ] TASK-2: PartialInvoiceModal 진행상황 상태머신 + Snackbar/Alert 피드백
      파일: ventago-app/src/views/facturacion/PartialInvoiceModal.tsx
      · phase state 추가, Emitir 클릭~완료까지 단계별 문구
      · 성공 시 output별 안내(thermal/pdf/digital)
- [ ] TASK-3: digital 분기 배선 — issue 성공 후 clientId로 click-to-chat 호출 → window.open(url,'_blank')
      파일: 동일 (PartialInvoiceModal.tsx)
      · sale.clientId 부재 시: "고객 미지정 — WhatsApp 발송 불가" 안내(발급은 유지)
      · WHATSAPP_NOT_REGISTERED / INVALID_WHATSAPP_NUMBER 에러코드 graceful 처리(명확한 문구)
- [ ] TASK-4: sale 객체 clientId 전달 보장 — PendientesPanel/pending API 응답에 clientId 포함 확인
      파일: ventago-app/src/views/facturacion/PendientesPanel.tsx (+ 필요시 pending 조회 훅)
      · 누락 시에만 최소 패치. 이미 있으면 no-op.
- [ ] TASK-5 (optional): 백엔드 신규 템플릿 `invoice_issued` (CAE/número/QR 링크 포함)
      파일: api-ventago/src/app/whatsapp/templates/template-registry.ts
      · 순수 상수 추가, DB/ pool 무영향. MVP 검증 후 착수 가능.
- [ ] TASK-6: ESLint 검증 (`npx eslint <파일> --fix`) — 오류 0
- [ ] TASK-7: PostgreSQL pool 안전 점검 — 신규 pool 사용 없음 재확인(폴링 금지 유지)
- [ ] TASK-8: 운영 로그 확인 — 발급+click-to-chat 흐름 로그 정상, 신규 에러 0

## 완료 기준
- "WhatsApp" 선택+Emitir → 발급 성공 후 대표자 세션에 고객 번호 wa.me 새 탭 오픈
- Emitir 전 과정에서 사용자에게 진행/결과 문구가 항상 표시됨(무피드백 제거)
- 고객/번호 없음·정규화 실패 시 명확한 안내(발급 자체는 성공 유지)
- ESLint 오류 0, 신규 pool 사용 0, 운영 로그 신규 에러 0

## 금지사항 / 주의사항
- issueForSale/afip 발급 로직 변경 금지(발급과 발송 분리 원칙 — 발급은 이미 안정).
- 폴링·신규 pool·상시 연결 추가 금지(pool 낭비 방지). 발송은 사용자 클릭 트리거 1회성.
- wa.me는 자동전송 아님 — UI 문구가 "사람이 [전송] 눌러야 함"을 반드시 안내.
- ★테스트 데이터 주의: GONZALEZ PAOLA `2302 521806`은 국가코드/모바일'9' 없음 →
  libphonenumber AR 검증에서 INVALID 가능. 실검증은 유효 모바일(+54 9 11 XXXX-XXXX)로.
- lint: return 위 빈 줄, 주석 위 빈 줄, no-unused-vars 엄수.

---
## REVIEW (2026-07-22, Execute 완료)
- [x] TASK-1/2/3: PartialInvoiceModal.tsx — apiConnector 직접 재사용, phase(form/working/done) 상태머신 +
      Alert 진행/결과 피드백, digital 분기 배선(click-to-chat→window.open), clientId 없음·에러코드 graceful.
- [x] TASK-4: sale.clientId — listPendientes 가 Sale 모델 원본 반환 → clientId 포함 확인(무패치).
- [ ] TASK-5(optional): invoice_issued 템플릿 — MVP 는 receipt_resend 재사용으로 skip(사용자 확정).
- [x] TASK-6: ESLint — 오류/경고 0 (exit 0).
- [x] TASK-7: pool — 프론트 변경, 신규 pool/폴링 0. 기존 click-to-chat(최대 3쿼리, 자동 release) 재사용.
- [x] TASK-8: 로그 — issue() 는 output 미사용 echo, thermal/pdf 도 발급 후 무동작(no-op) 확인.

### 변경 파일
- ventago-app/src/views/facturacion/PartialInvoiceModal.tsx (+181/-51)
  ※ 이 diff 에는 이전 미커밋 WIP(Phase 58 offline-F10 가드: useOfflineStatus)도 포함됨 — 함께 커밋됨.

### ★발견 (스코프 외, 후속 제안)
- afip issue() 는 output(thermal/pdf/digital)을 전혀 소비하지 않음(echo만) → thermal/pdf 도 발급 후
  실제 출력 트리거 없음. UI 캡션 "se imprime en la comandera" 는 미구현 상태였음.
  → 후속: issue 성공 후 output==='thermal' 이면 outputService.dispatch(thermal) 호출 배선(백엔드) 제안.

### 테스트 주의
- sale 79 는 이미 facturado → Pendientes 목록에 없음. 신규 pendiente 로 재현 필요.
- 테스트 고객 GONZALEZ PAOLA `2302 521806` 은 국가코드/모바일'9' 없어 libphonenumber AR 검증
  실패 가능 → done 상태에서 warning("número no válido") 표시 예상. 유효 모바일로 최종검증 권장.

### 배포
- 프론트 변경 → Jenkins front-coolsistema (docker build→next build) 또는 로컬 npm run dev:app 검증.

---
## REVIEW 2 (2026-07-22, thermal/pdf 배선 추가)
목표: thermal/pdf 도 발급 후 실제 출력(터미널별 라우팅). WhatsApp 과 동일하게 발급-출력 분리, issue() 무손.

### 변경 파일 (4)
- [FE] ventago-app/src/views/facturacion/PartialInvoiceModal.tsx — sendThermal/sendPdf 추가.
  성공 시 thermal→reprint(voucherId, branchId, terminalId), pdf→downloadFile(pdf blob). ESLint 0.
- [FE] ventago-app/src/services/afip.service.ts — reprint 에 terminalId 인자 추가. ESLint 0.
- [BE] api-ventago/src/app/afip/afip-output.service.ts — DispatchInput.terminalId + thermal 분기에
  터미널 라우팅(getTerminalThermalAgent→socketId, offline 시 agent_offline, 없으면 지점 broadcast).
- [BE] api-ministago/src/app/afip/afip.controller.ts — reprint @Body('terminalId') 추가 → dispatch 전달.

### 설계
- 발급 성공(res.voucherId) 후 별도 호출. issue()/issueForSale 무변경(발급경로 무손).
- 터미널별 라우팅: /print/temp 규칙 그대로 재사용(terminalId→매핑 comandera, offline=agent_offline, 미매핑=broadcast).
- branchId=localStorage selectedBranchId, terminalId=GET /cash-register/open 의 terminal.id.
- pdf=apiConnector.downloadFile(JWT blob) — 기존 헬퍼 재사용.
- graceful: comandera offline/오류/PDF실패 시 comprobante 는 유효로 유지하고 warning 문구만.

### 검증
- FE ESLint 0(PartialInvoiceModal, afip.service). 
- BE ESLint: api-ventago 타입인지 린팅이 device 45s 제한 초과 → 미완주. 편집영역 육안검증 클린
  (let targetSocketId 재할당·주석전 빈줄·block-start return). 최종 lint 게이트=Jenkins 빌드.
- pool: BE 추가 쿼리=getTerminalThermalAgent 1건(findByPk+include, thermal 선택 시에만). 폴링 0.

### 잔여
- 커밋·Jenkins(api+front) 빌드. 실검증: 신규 pendiente 발급 → 각 output(thermal 실제 comandera 출력·
  pdf 다운로드·whatsapp) 실기 확인. 터미널-comandera 매핑 없으면 지점 broadcast 로 동작.

---
## REVIEW 3 (2026-07-22, WIRING GAP #1 — print-agent fiscal 출력 배선) ★push 완료
문제: print-agent main.js print_invoice 는 payload.factura(D-02) 있어야 fiscal(CAE/QR) 렌더,
없으면 control ticket 로 빠짐. 백엔드 emitPrintInvoice 는 {cae,caeVto,qrUrl,voucher,issuer} flat
전송(.factura 없음) → thermal 눌러도 fiscal comprobante 안 나옴("WIRING GAP #1", Phase 57 W1).

해결: dispatch thermal 에서 기존 buildFactura(voucher,sale,issuer)[D-04 단일소스]로 D-02 factura
생성 → emitPrintInvoice payload.factura 로 전달. print-agent 가 fiscal path(CAE+QR PNG) 렌더.
- 정합 확인: buildFactura 출력(cant/desc/pUnit/subtotal, iva21, neto/total/receptor/emisor/letra/
  cod/number/cae/caeVto/qrUrl) == fiscal-formatter.js 읽는 필드. fecha 만 추가(voucher.createdAt; 없으면 now).
- AfipQueryService.getSaleForFactura(storeId,saleId) eager-load(SaleItem+Product, StoreClient+
  GlobalClient, Clients) 추가. sale 미조회/오류 시 factura 생략 → control ticket fallback(graceful).

변경(api-ventago 2파일): afip-output.service.ts(+buildFactura 배선), afip-query.service.ts(+getSaleForFactura).
배포: 커밋 8bfee48 + root a479e5d, main push 완료(runner push-fiscal-wiring).
pool: getSaleForFactura 단일 쿼리(thermal 선택 시만). 폴링 0.

★운영 게이트(코드 아님): print-agent 설정 printControl=true AND printFiscal=true 여야 fiscal 출력.
comandera online + terminal-thermal 매핑(없으면 지점 broadcast). 실기 검증 시 이 설정부터 확인.

---
## REVIEW 4 (2026-07-22, AFIP 10015 — 문서 없음은 단순 Consumidor Final) ★push 완료
증상: venta #80 발급 시 "AFIP 거부 10015: Factura B(<$10M) DocTipo≠99 이면 DocNro>0 필수".
근본원인: 고객 "Consumidor Final"(clients id=5) document='00000000'(8자리 0). decideDocumentType 이
문자열 길이(8)로 DNI(96) 판정 → soap-direct 가 Number('00000000')=0 → DocNro=0, DocTipo=96 불일치.
수정(사용자 의도="CUIT/문서 없으면 단순 CF"): api-ventago 4파일
- code-maps.decideDocumentType: 숫자만 추출·값 0/무효 → FINAL_CONSUMER(99).
- soap-direct / rest-gateway.provider: 불변식 DocNro=0 ⟺ DocTipo=99 강제.
- build-factura: CF 표시/QR docNro 정규화(placeholder '00000000' 숨김, QR 스캔값 정합).
테스트 안전: code-maps.spec('20304050609'→80,'30111222'→96,''→99) 불변, build-factura.spec CF 불변.
배포: bb8da10 + root 7917466 push. 잔여: Jenkins 빌드 후 venta #80 재발급 확인.

---
## REVIEW 5 (2026-07-22, A4 PDF 재설계 + 감열 제목 — CoolSyncro 참조) ★push 완료
참조: /Users/marcoskim/Trabajos_Programming/CoolSyncro (Electron, pdfkit) — src/main/pdf/generator.js(A4),
thermal-generator.js(감열). AFIP RG1415+RG4892 완전 준수 "모던" 레이아웃. 샘플 pdfs/*.pdf.
문제: 우리 a4-generator 가 품목도 없이(dispatch lines=[]) 밋밋 → AFIP 규격과 상이.
PDF 수정(api-ventago 3파일):
- a4-generator.ts 전면 재작성(465줄): Factura(D-02) 소비. 로고(옵션·없으면 발행자명)/Letra 다크칩/COD,
  EMISOR·CLIENTE 2단, 지브라 품목표(A/M: P.Unit=neto·IVA%·Subtotal c/IVA / B: IVA포함가),
  Neto/IVA/Otros/TOTAL 다크바, QR(RG4892 78pt)+CAE+Vto 푸터, 다중페이지 bufferPages Pag n/N.
  좌표/색/폰트 CoolSyncro generator.js 그대로.
- afip-output.service pdf 분기: buildFactura 로 D-02 재구성(thermal 과 동일 소스). 미사용 letra() 제거.
- a4-generator.spec.ts A4Factura 로 갱신. qr-builder 는 이미 RG4892 정합(무변경).
- 격리 tsc(프로젝트 설정) 클린. (프로젝트 esModuleInterop 미사용)
감열(print-agent/src/fiscal-formatter.js): 이미 CoolSyncro 감열과 동일 구조로 잘 구현돼 있었음
(letra box/COD, EMISOR, RECEPTOR, 품목표, A/M IVA 분리, TOTAL, CAE, QR, leyenda). comprobante 제목
"FACTURA A/B/M" 추가(node 렌더 검증). ※반영은 print-agent 재빌드+재설치 필요.
배포: api b9b0d5b + root da66c48(api pointer + fiscal-formatter) push.
잔여: Jenkins 빌드 후 GET /afip/vouchers/:id/pdf 시각 검증. 로고=백엔드 PDF 는 옵션(store 로고 후속).
       감열 실기 반영=print-agent 재빌드.
