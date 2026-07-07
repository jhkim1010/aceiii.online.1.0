/**
 * 서버 payload 가격 → 설정된 precio nivel 슬롯 매핑 (순수 함수)
 * main.js 와 테스트에서 공용으로 사용 — electron 의존성 없음.
 *
 * 매칭 우선순위: priceTypeId(숫자 비교) → label(이름, 대소문자 무시)
 * selection 이 비어 있으면 하위 호환: payload 순서대로 layout.priceCount 개.
 */

/**
 * 단일 상품의 가격 배열에서 선택된 nivel 만 추출
 * @param {Object} item - { prices: [{ priceTypeId, label, amount }] }
 * @param {Array} selection - [{ id, name }] 최대 3개
 * @param {Object} layout - { priceCount } (selection 미설정 시 fallback 개수)
 * @returns {Array} 슬롯 순서대로 정렬된 가격 배열
 */
function selectItemPrices(item, selection, layout) {
  const sel = Array.isArray(selection) ? selection : [];
  const incoming = Array.isArray(item.prices) ? item.prices : [];

  if (sel.length === 0) {
    const rawCount = layout && layout.priceCount;
    const count = Math.max(0, Math.min(3, rawCount == null ? 1 : parseInt(rawCount, 10) || 0));

    return incoming.slice(0, count);
  }

  const picked = [];
  for (const s of sel.slice(0, 3)) {
    const match = incoming.find(
      (pr) =>
        (s.id != null && pr.priceTypeId != null && Number(pr.priceTypeId) === Number(s.id)) ||
        (s.name && pr.label && String(pr.label).toLowerCase() === String(s.name).toLowerCase()),
    );
    if (match) picked.push(match);
  }

  return picked;
}

/**
 * 출력용 items 전처리 — 각 item 의 prices 를 선택 nivel 로 필터
 * @param {Array} items
 * @param {Array} selection
 * @param {Object} layout
 * @returns {Array}
 */
function prepareItems(items, selection, layout) {
  if (!Array.isArray(items)) return [];

  return items.map((it) => ({
    ...it,
    prices: selectItemPrices(it, selection, layout),
  }));
}

module.exports = { selectItemPrices, prepareItems };
