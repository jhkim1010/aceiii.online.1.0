# SPEC: Phase 25 Wave 5 (실용적 범위 — frontend wiring)
생성일: 2026-04-26

## 목표
Wave 4 의 백엔드 (`POST /clients/import`)를 **`CargaMasivaClientesView` 프론트가 실제로 호출**하도록 교체.
운영에서 clientes masivo importación 화면이 동작 가능 상태로 만든다.

## 범위 (실용적 결정)

**포함:**
- `CargaMasivaClientesView.tsx` 의 `/global-clients/massive-upload` → `/clients/import` 교체
- ParsedClient → ImportRowDto 변환 로직
- ImportResponse 의 errorCount/skippedCount 등 새 필드 표시
- Wave 5 SUMMARY 작성

**제외 (별도 작업으로 분리):**
- PromoteMergeDialog 신규 컴포넌트 (Plan 25-14 의 ClienteVistaView 통합)
  → 이는 `cliente-vista` 화면의 별도 작업, 다른 phase 에서
- Plan 25-15 sales/reports scope audit (Wave 7 — 큰 별도 작업)

## 태스크 목록

- [ ] TASK-1: `CargaMasivaClientesView.tsx` 의 `handleUpload` 메서드 교체
- [ ] TASK-2: ParsedClient → ImportRowDto 매핑 헬퍼 함수
- [ ] TASK-3: UploadResult 타입 확장 (errorCount, skippedCount, clientImportId)
- [ ] TASK-4: 결과 화면에 errorCode/rowIndex 표시 강화
- [ ] TASK-5: 25-14-SUMMARY 작성 (Wave 5 실용적 범위 반영)
- [ ] TASK-6: STATE.md 갱신 (59→60 plans, 81→85% — Wave 5 부분 완료)

## 완료 기준
- 프론트가 `/clients/import` POST 호출
- 응답 형식 (`ImportResponse`) 에 맞춰 결과 화면 표시
- 빌드 통과 (ventago-app)
- 운영 배포 후 admin 로그인 → CargaMasivaClientesView 사용 가능

## 호환성 메모
- 구 endpoint `/global-clients/massive-upload` 는 그대로 유지 (다른 호출자 있을 수 있음)
- 새 endpoint 가 실제 사용되면 추후 deprecate 가능

## Wave 5 이후 남은 작업 (다음 phase 후보)

1. **PromoteMergeDialog + ClienteVistaView 통합** (Plan 25-14 잔여 — D1-04 충돌 해결 UI)
2. **sales/reports scope audit** (Plan 25-15 / Wave 7 — 큰 별도 phase)
