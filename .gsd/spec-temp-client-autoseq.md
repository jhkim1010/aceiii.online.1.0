# SPEC: 임시 고객 자동 일련번호 + F2 즉시 등록

생성일: 2026-04-30

## 목표
운영자가 정식 CUIT/DNI 모르는 손님에게도 빠르게 venta 등록할 수 있도록, 임시 고객을 자동 일련번호로 즉시 만들고 venta 에 할당.

## 사용자 흐름

### 흐름 A — Tab 자동 일련번호
1. POS nueva-venta 화면에서 InfoClient 의 CUIT 칸 (`document` input) 에 커서 둠
2. 아무것도 입력 안 한 상태로 **Tab** 누름
3. CUIT 칸에 매장 prefix 포함 일련번호 자동 입력 (예: `S9-00001`)
4. 포커스가 자동으로 이름 (`fullname`) 칸으로 이동
5. 사용자가 손님 이름 입력 (예: "Juan")

### 흐름 B — F2 즉시 등록 + 할당
1. fullname 칸에 이름이 있고, document 칸에는 일련번호 또는 빈 값
2. **F2** 누름
3. document 가 빈 채로 fullname 만 있으면 → 자동 일련번호 부여 후 진행
4. document + fullname 으로 store_clients (+ legacy clients) 행 생성
5. 생성된 행을 selectedClient 로 설정 → venta 에 즉시 할당
6. fullname 도 빈 상태에서 F2 → **아무것도 안 함** (5번 답변)

### 갱신 흐름 (자동)
나중에 그 고객이 다시 와서 진짜 CUIT 알려줌:
1. 같은 매장에서 CUIT 입력 → 11자리면 by-document 자동조회
2. 운영자가 InfoClient 폼 편집 모달에서 document 를 진짜 CUIT 로 변경 + 저장
3. 단순 PATCH /clients/:id (또는 store_clients) — 별도 마이그레이션 로직 불필요

## 배경

### 일련번호 형식
- `S{storeId}-{5자리 zero-pad}` — 예: `S9-00001`, `S9-00002`, `S6-00042`
- 매장별 독립 카운터 — 다른 매장의 번호와 충돌 없음
- DB CHECK 없음 — 그냥 VARCHAR document 에 저장
- 정규식 매칭: `^S\d+-\d{5}$`

### 다음 번호 결정
백엔드 새 엔드포인트 추가:
- `GET /clients/next-temp-document` (또는 store_clients 라우트)
- 응답: `{ document: "S9-00001" }`
- 로직: `MAX(document)` 중 정규식 매칭하는 것의 5자리 부분 +1 → 0이면 1
- 매장별 격리 (storeId from JWT)
- 동시성 안전 — frontend 가 호출하고 즉시 사용 (충돌 시 등록 단계에서 `unique` 위반 → 자동 재시도 1회)

### 프론트엔드 동작
- `ClientFilters.tsx` 의 11자리 CUIT 자동 채움 로직과 충돌 안 하게 — 일련번호 입력은 11자리가 아니라 트리거 안 됨
- 기존 F2 가 'Consumidor Final' 로 매핑되어 있다면 그 동작은 새 흐름으로 대체
- F2 핫키는 InfoClient.tsx 또는 부모에서 등록 — 확인 필요

## 기술 스택
- 백엔드: NestJS 11 + Sequelize, store_clients / clients 모델
- 프론트엔드: React + MUI + react-hotkeys-hook
- DB: PostgreSQL — store_clients.document 컬럼 (varchar)
- ESLint 설정: 양쪽 다

## 태스크 목록

### 백엔드
- [ ] **B1**: GET /clients/next-temp-document (storeId from JWT) — 다음 일련번호 계산
- [ ] **B2**: POST /clients/temp (fullname 만 받음) — 자동 일련번호 + store_clients + clients (legacy) 동시 INSERT, 응답에 storeClientId 포함
- [ ] **B3**: ESLint 검증

### 프론트엔드
- [ ] **F1**: InfoClient.tsx 의 document 칸에 onKeyDown 추가 — 빈 채로 Tab 시 next-temp-document 호출 + setFormData + fullname 포커스
- [ ] **F2**: F2 핫키 동작 변경 — fullname 비어있으면 noop, 아니면 POST /clients/temp 호출 + setSelectedClient
- [ ] **F3**: 기존 'Consumidor Final' F2 동작 위치 추적 + 제거
- [ ] **F4**: ESLint 검증

### 검증
- [ ] **Z1**: 로컬에서 양쪽 흐름 수동 테스트
- [ ] **Z2**: 운영 매장별 일련번호 격리 검증 (서로 다른 매장에서 동시 등록)
- [ ] **Z3**: push + Jenkins 빌드 통과

## 완료 기준
- ESLint 0 errors (변경 파일)
- Tab 시 자동 일련번호 + fullname 포커스 이동 동작
- F2 시 fullname 있으면 즉시 등록 + venta 할당, 없으면 noop
- 같은 매장에서 두 번 Tab 시 연속 번호 (`S9-00001` → `S9-00002`)
- 정식 CUIT 로 갱신 가능 (수동 편집)

## 금지사항
- 기존 by-document 자동조회 (11자리) 흐름 깨지 않기
- DNI 7-8자리 입력 흐름 깨지 않기
- consumidor final 의 다른 사용처(있다면) 보존 — F2 외 경로
- selectedClient 가 임시고객일 때도 CreditBadges/payment 흐름이 정상 작동 (storeClientId 가 살아있으므로 OK)
