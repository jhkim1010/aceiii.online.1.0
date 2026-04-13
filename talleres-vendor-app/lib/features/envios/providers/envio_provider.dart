// Envio Provider — 매장별 발송 목록 상태 관리 (Riverpod 3.x)
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/envio_dto.dart';
import '../data/envio_repository.dart';

// 매장별 envio 목록 — family provider로 storeId 기반 캐싱
// autoDispose: 화면을 벗어나면 자동으로 메모리 해제
final envioListProvider =
    FutureProvider.family.autoDispose<List<EnvioDto>, int>((ref, storeId) async {
  return ref.read(envioRepositoryProvider).fetchEnvios(storeId);
});
