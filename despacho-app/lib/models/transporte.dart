// 운송업체 — 발송 인계 드롭다운용.
class Transporte {
  final int id;
  final String name;

  /// 인계 즉시 배송완료(고객이 직접 가져가거나 자기 운송을 보내는 경우).
  /// true 면 운송사 추적번호가 존재하지 않으므로 발송 화면에서 요구하지 않는다.
  final bool deliversImmediately;

  const Transporte({
    required this.id,
    required this.name,
    this.deliversImmediately = false,
  });

  factory Transporte.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;

    return Transporte(
      id: id,
      name: (json['name'] ?? '').toString(),
      deliversImmediately: json['deliversImmediately'] == true,
    );
  }
}
