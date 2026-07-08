// 운송업체 — 발송 인계 드롭다운용.
class Transporte {
  final int id;
  final String name;

  const Transporte({required this.id, required this.name});

  factory Transporte.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;

    return Transporte(id: id, name: (json['name'] ?? '').toString());
  }
}
