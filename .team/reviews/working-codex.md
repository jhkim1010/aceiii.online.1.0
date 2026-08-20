상한 처리에서 정확히 5,000건인 유효 입력까지 거절하는 경계값 오류가 있습니다. 그 외 검토한 변경과 관련 테스트에서는 명확한 차단 결함을 발견하지 못했습니다.

Review comment:

- [P2] 상한 초과 판별을 위해 한 행을 더 조회하세요 — /Users/marcoskim/TrabajoProgramming/aceiii.online.1.0/api-ventago/src/app/subcon/subcon-settlements/subcon-settlement.service.ts:330-330
  기간에 recepción이 정확히 5,000건인 경우에도 `length >= 5000`이 참이어서 완전한 정산을 생성할 수 없게 됩니다. 실제 절단 여부를 구분하려면 5,001건까지 조회한 뒤 5,000건을 초과할 때만 거절해야 합니다.
