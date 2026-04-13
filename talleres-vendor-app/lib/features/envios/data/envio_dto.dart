// Envio DTO — 외주 발송 및 수령 이력 데이터 모델

// 수령 이력 항목 모델
class RecepcionDto {
  final int id;
  final int receivedQuantity;
  final int rejectedQuantity;
  final String recepcionDate;
  final String? notes;

  const RecepcionDto({
    required this.id,
    required this.receivedQuantity,
    required this.rejectedQuantity,
    required this.recepcionDate,
    this.notes,
  });

  // JSON 응답을 RecepcionDto 객체로 변환
  factory RecepcionDto.fromJson(Map<String, dynamic> json) => RecepcionDto(
        id: json['id'] as int,
        receivedQuantity: json['receivedQuantity'] as int? ?? 0,
        rejectedQuantity: json['rejectedQuantity'] as int? ?? 0,
        recepcionDate: (json['recepcionDate'] as String?) ?? '',
        notes: json['notes'] as String?,
      );
}

// 발송 항목 모델 — 로트, 에타파, 수령 이력 포함
class EnvioDto {
  final int id;
  final int loteId;
  final String? loteName;
  final int etapaId;
  final String? etapaName;
  final int quantity;
  final int pendingQuantity;
  final String envioDate;
  final String? dueDate;
  final String status; // PENDING, PARTIAL, COMPLETED, CANCELLED
  final List<RecepcionDto> recepciones;

  const EnvioDto({
    required this.id,
    required this.loteId,
    this.loteName,
    required this.etapaId,
    this.etapaName,
    required this.quantity,
    required this.pendingQuantity,
    required this.envioDate,
    this.dueDate,
    required this.status,
    required this.recepciones,
  });

  // JSON 응답을 EnvioDto 객체로 변환
  factory EnvioDto.fromJson(Map<String, dynamic> json) {
    // 로트 이름 추출 — 중첩 객체 또는 직접 필드
    final lote = json['lote'] as Map<String, dynamic>?;
    final etapa = json['etapa'] as Map<String, dynamic>?;

    // 수령 이력 목록 파싱
    final recepcionesJson = json['recepciones'] as List<dynamic>? ?? [];

    return EnvioDto(
      id: json['id'] as int,
      loteId: json['loteId'] as int? ?? lote?['id'] as int? ?? 0,
      loteName: lote?['name'] as String? ?? json['loteName'] as String?,
      etapaId: json['etapaId'] as int? ?? etapa?['id'] as int? ?? 0,
      etapaName: etapa?['name'] as String? ?? json['etapaName'] as String?,
      quantity: json['quantity'] as int? ?? 0,
      pendingQuantity: json['pendingQuantity'] as int? ?? 0,
      envioDate: (json['envioDate'] as String?) ?? '',
      dueDate: json['dueDate'] as String?,
      status: (json['status'] as String?) ?? 'PENDING',
      recepciones:
          recepcionesJson.map((e) => RecepcionDto.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
