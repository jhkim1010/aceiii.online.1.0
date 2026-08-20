새 캐시 키 형식과 일부 무효화 경로가 일치하지 않아 인증 회수 및 Cut Ticket 갱신 후 stale 데이터가 남습니다. 또한 키 인코딩이 사용자 입력 간 충돌을 만들어 잘못된 검색 결과를 반환할 수 있으며, 관련 인증 캐시 테스트도 실제로 실패합니다.

Full review comments:

- [P1] 인증 캐시 일괄 무효화 prefix를 실제 키 형식과 맞추세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/auth/auth-cache-key.ts:24-24
  `authUserKey()`는 prefix의 `:`도 인코딩하여 `auth_user:g:` 형태의 키를 만들지만, 이 상수는 `auth:user:g:`를 사용하므로 `activateStoreUsers`와 `deactivateStoreUsers`의 일괄 무효화가 전혀 동작하지 않습니다. 매장 정지 후에도 기존 사용자 객체가 TTL 30초 동안 인증에 사용되며, 추가된 단위 테스트도 이 문제로 실패합니다. 인증 회수 경로이므로 실제 생성 키와 동일한 helper 기반 prefix를 사용해야 합니다.

- [P1] 기존 재작업 경로도 새 Cut Ticket 키를 무효화하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/subcon/lotes/lote.service.ts:1780-1780
  Cut Ticket 상세 키가 여기서 `talleres_cut-ticket:s{storeId}:...` 형식으로 변경됐지만, `rework-order.service.ts:158`은 여전히 `talleres:cut-ticket:${storeId}:`를 삭제합니다. 재작업 생성 후 해당 lot의 상세 조회는 최대 2분간 이전 BOM·routing 정보를 반환할 수 있으므로, 모든 쓰기 경로가 동일한 `storePrefix()` 형식을 사용하도록 함께 전환해야 합니다.

- [P2] 캐시 키 조각을 충돌 없이 인코딩하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/common/cache/cache-key.ts:24-25
  `:`를 `_`로 치환하면 원래 값 `a:b`와 `a_b`가 동일한 캐시 조각이 됩니다. 검색어가 키에 포함되는 모바일 및 공개몰 목록에서 두 입력이 같은 store의 동일 필터 조건으로 요청되면 두 번째 요청이 첫 번째 검색 결과를 반환할 수 있으므로, 구분자를 포함해 가역적이거나 충돌 없는 인코딩을 사용해야 합니다.
