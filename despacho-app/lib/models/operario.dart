// 작업자(operario) — 감사 추적용 경량 신원.
class Operario {
  final int id;
  final String name;

  const Operario({required this.id, required this.name});

  factory Operario.fromJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final id = rawId is int ? rawId : int.tryParse('$rawId') ?? 0;

    return Operario(id: id, name: (json['name'] ?? '').toString());
  }
}
