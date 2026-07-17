# SPEC: Envío 인라인 고객 등록 — F2 결제 다이얼로그에서 바로 고객 캡처
생성일: 2026-07-16 · 상태: PLAN (승인 대기)

## 목표
Nueva Venta의 F2(Agregar Métodos de Pago)에서 Envío 체크 시 고객 정보가 없으면 지금은 경고("Datos de envío incompletos")+취소뿐이다. 다이얼로그 **우측 빈 패널에 고객 입력 폼**(CUIT/DNI·이름·주소·전화)을 띄워 그 자리에서 등록하고 envío 흐름을 이어가게 한다. **CUIT 입력 시 기존 고객과 일치하면 전 필드 자동 채움**.

## 배경 및 컨텍스트 (2026-07-16 실코드 정찰)
- 대상: `ventago-app/src/views/homes/components/ProductList/components/PaymentSummaryModal.tsx` (989줄)
  - L335 `envioChecked` · L347-357 `envioGuardNotice`(식별 고객+주소 사전검증) · L631-635 경고 Alert · L949 등록 버튼 disabled 조건 · 우측 패널 = MP QR 영역(QR 없을 때 빈 공간)
- 재사용 (InfoClient.tsx 검증된 로직):
  - CUIT 2단 조회: L296 `GET /clients`(스토어 로컬) → L318 `GET /global-clients/by-document/:doc`(글로벌)
  - 생성: L492 `POST /clients` `{...payload, storeId}` → `created.id` 반환 → `setSelectedClient(created)`
- envío 등록 흐름: 가드 해제 후 기존 `EnvioRegistroModal`(online_order from-pos) 그대로 — **무변경**
- 서버 변경 없음 예상 (기존 엔드포인트 재사용)

## 기술 스택
- Next.js 13 + MUI 5, apiConnector. api 변경 없음(확인 태스크만). ESLint/tsc 검증 = agent-runner `phase57-verify-front` 패턴(경로 추가)

## 태스크 목록
- [ ] TASK-1: `useClientByDocument` 훅 신설 — InfoClient의 로컬→글로벌 2단 조회 로직 추출(디바운스 500ms, 조회 최대 2회). 반환: 일치 고객(이름·주소·전화·id) 또는 null — 파일: `src/hooks/api/useClientByDocument.ts`
- [ ] TASK-2: `EnvioClientQuickForm` 컴포넌트 — 필드: CUIT/DNI(필수)·Nombre(필수)·Dirección(필수)·Teléfono(선택). CUIT 일치 시 전 필드 자동 채움 + "cliente existente" 표시(이 경우 생성 없이 해당 고객 선택). 불일치 시 신규 등록 모드 — 파일: `src/views/homes/components/ProductList/components/EnvioClientQuickForm.tsx`
- [ ] TASK-3: PaymentSummaryModal 통합 — `envioChecked && envioGuardNotice`일 때 우측 패널에 폼 렌더. "Usar este cliente" 클릭 → (기존 고객이면 선택 / 신규면 `POST /clients` 후 선택) → `setSelectedClient` 경로 확인(부모 props/context) → 가드 자동 해제 → "Registrar pedido online" 활성화. 실패 시 기존 에러 전면 노출 정책 준수
- [ ] TASK-4: api 확인 — POST /clients가 document 필수 검증·global 강등 규칙을 서버에서 보장하는지 확인만(변경 없음 목표)
- [ ] TASK-5: ESLint+tsc (러너 잡에 신규 파일 경로 추가) + 로컬 수동 E2E: ①신규 CUIT 등록→envío ②기존 CUIT 자동채움→envío ③CUIT 없이 시도→차단 확인

## 완료 기준
- 고객 미선택 상태에서 Envío 체크 → 우측 폼으로 등록/선택 → 취소 없이 pedido online 등록 완료
- 기존 CUIT 입력 시 1초 내 자동 채움 · ESLint 0 · sale/재고 hold 경로 diff 0

## 금지사항 / 주의
- **판매(sale) 생성·재고 hold·결제 로직 무변경** — 이 기능은 고객 선택 단계만 추가
- **CUIT/DNI 없는 고객은 global 등록 금지** (기존 규칙) — envío는 식별 고객 요건이므로 CUIT/DNI 필수 입력으로 설계
- POS hot path: 디바운스 500ms, 타이핑 중 연속 조회 금지 (pool 보호)
- EnvioRegistroModal·envioGuardNotice 검증 로직 자체는 수정 금지(서버 재검증 신뢰)
