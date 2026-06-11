# U18 Stock Cockpit MOV+ tooltip — Plant Seed

**Decision (2026-05-23, 재확인 2026-06-11):** U18 (Stock Cockpit MOV+ 셀 hover tooltip 최근 5건 표시) 은
Phase 35-A scope 외, Phase 36 boundary 외 처리. 후속 phase 후보로 plant-seed.

**Trigger condition:**
- Phase 35 운영 적용 완료 후 매장 운영자가 1개월간 사용
- MOV+ / MOV− 셀의 detail drilldown 요구 사용자 1명 이상 발생
- (또는) Stock Cockpit Phase B 확장 phase 가 별도로 결정될 때

**예상 phase 번호:** milestone v1.1 후반 (Phase 37 모바일 셸은 별도 진행 중이므로 Phase 38+ 후보).

**Dependencies (구현 시):**
- 신규 endpoint: `GET /sales/by-product-recent?productId=X&type=movido&limit=5`
- 또는 기존 endpoint 확장 + frontend tooltip 컴포넌트

**예상 effort:** 2-3 plans (backend endpoint + frontend tooltip + UAT)
