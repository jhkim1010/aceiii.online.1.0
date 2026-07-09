---
status: partial
phase: 38-codigomadre-qr-print
source: [38-VERIFICATION.md]
started: 2026-07-09
updated: 2026-07-09
---

## Current Test

실기기(Zebra) + 운영 PG10 마이그레이션 적용 후 E2E 델타 출력 확인 대기.

## Tests

### 1. 운영 PG10 마이그레이션 적용
expected: `phase38-qr-print-log.sql`을 운영 PG10에 적용 → `qr_print_log` 테이블 + UNIQUE + 인덱스 생성. (현재 로컬 PG18만 적용됨)
runbook: `ssh jhkim-server "sudo -u postgres psql -d ventago" < api-ventago/migrations/phase38-qr-print-log.sql` (DDL — 사용자 확인 필수)
result: [pending]

### 2. TAB3 시각 UAT (dev electron)
expected: zebra-agent 실행 → TAB3 "QR" 진입 → price-type 드롭다운 로드 + 좌 프리뷰(1:3 QR/이름·가격) + 수치 5개(폭/높이/QR모듈/비율/폰트) 변경 시 프리뷰 라이브 반영 + 다크네이비+골드
result: [pending]

### 3. 델타 리스트 실렌더
expected: "Buscar cambios" → 신규(NUEVO)/변경(CAMBIO, 구→신 가격) codigomadre 리스트 + 체크박스(기본 체크) + 전체선택
result: [pending]

### 4. 실 Zebra 출력 + 델타 제외 사이클
expected: 항목 선택 → "Imprimir seleccionados" → 실프린터에 QR 라벨(좌 QR/우 이름+가격) 출력 → 앱 스캔 시 `/m/stock?s=&p=`로 해당 상품 매트릭스 오픈(Phase 37) → 재 "Buscar cambios" 시 출력분 제외
result: [pending]

### 5. 1개/2개(doble) 토글
expected: 2개씩 = 같은 상품 라벨 2장 출력
result: [pending]

### 6. 프린터 오프라인 실패 UX
expected: 프린터 미연결 시 해당 행 실패 표시(빨강) + 인라인 배너 + 토스트, 스냅샷 미기록(다음 배치 재등장)
result: [pending]

### 7. TAB1/TAB2 회귀 + zebra-agent CI 빌드
expected: 기존 Imprimir/Etiqueta 탭 정상 + push 시 build-zebra-agent.yml 태그 자동 증가 빌드 통과
result: [pending]

## Summary

total: 7
passed: 0
issues: 0
pending: 7
skipped: 0
blocked: 0

## Gaps

코드 갭 0. pending 7건은 운영 마이그레이션(사용자 확인)·실 Zebra 프린터·시각/CI 게이트. 코드 레벨 8/8 + QR-01..10 검증 완료(38-VERIFICATION.md).
