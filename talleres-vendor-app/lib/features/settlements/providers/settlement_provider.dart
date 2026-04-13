// 정산 Provider — 기간 필터 상태 및 정산 목록 관리 (Riverpod 3.x)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/settlement_dto.dart';
import '../data/settlement_repository.dart';

// 기간 필터 Notifier — Riverpod 3.x에서는 Notifier 사용 (StateProvider 제거됨)
class _DateRangeNotifier extends Notifier<DateTimeRange?> {
  @override
  DateTimeRange? build() => null;

  // 기간 필터 설정
  void setRange(DateTimeRange? range) => state = range;
}

// 기간 필터 상태 — 날짜 범위 선택 관리
final settlementDateRangeProvider =
    NotifierProvider<_DateRangeNotifier, DateTimeRange?>(
  () => _DateRangeNotifier(),
);

// 매장별 정산 목록 — storeId + 기간 필터 조합
// autoDispose: 화면을 벗어나면 자동으로 메모리 해제
final settlementListProvider =
    FutureProvider.family.autoDispose<List<SettlementDto>, int>(
  (ref, storeId) async {
    // 기간 필터 구독 — 변경 시 자동 재조회
    final dateRange = ref.watch(settlementDateRangeProvider);

    return ref.read(settlementRepositoryProvider).fetchSettlements(
          storeId,
          from: dateRange?.start.toIso8601String().split('T')[0],
          to: dateRange?.end.toIso8601String().split('T')[0],
        );
  },
);

// 정산 순액 합계 — settlementListProvider에서 computed
final settlementTotalProvider = Provider.family<double, int>((ref, storeId) {
  final settlements = ref.watch(settlementListProvider(storeId)).value ?? [];

  return settlements.fold(0.0, (sum, s) => sum + s.netAmount);
});
