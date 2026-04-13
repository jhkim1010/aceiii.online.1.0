// 정산 DTO — 백엔드 정산 응답 매핑
// amounts는 double.tryParse로 안전하게 변환 (문자열 or 숫자 모두 처리)

// 정산 데이터 전송 객체 — API 응답을 Dart 모델로 변환
class SettlementDto {
  final int id;
  final int subconOrderId;
  final String? orderNumber;
  final DateTime? periodFrom;
  final DateTime? periodTo;
  final double totalGrossAmount;
  final double deductionAmount;
  final double netAmount;
  final DateTime settlementDate;
  final String status;
  final String? notes;

  const SettlementDto({
    required this.id,
    required this.subconOrderId,
    this.orderNumber,
    this.periodFrom,
    this.periodTo,
    required this.totalGrossAmount,
    required this.deductionAmount,
    required this.netAmount,
    required this.settlementDate,
    required this.status,
    this.notes,
  });

  // JSON 응답에서 DTO로 변환 — 금액은 숫자/문자열 모두 안전하게 처리
  factory SettlementDto.fromJson(Map<String, dynamic> json) {
    // 금액 안전 변환 — API가 문자열로 반환할 수도 있음
    double parseAmount(dynamic value) {
      if (value == null) {
        return 0.0;
      }
      if (value is double) {
        return value;
      }
      if (value is int) {
        return value.toDouble();
      }

      return double.tryParse(value.toString()) ?? 0.0;
    }

    // 날짜 안전 변환 — null 허용
    DateTime? parseDate(dynamic value) {
      if (value == null || value == '') {
        return null;
      }

      return DateTime.tryParse(value.toString());
    }

    // 중첩된 subconOrder에서 주문 번호 추출
    final subconOrder = json['subconOrder'] as Map<String, dynamic>?;

    return SettlementDto(
      id: json['id'] as int,
      subconOrderId: json['subconOrderId'] as int? ?? 0,
      orderNumber: subconOrder?['orderNumber'] as String? ??
          json['orderNumber'] as String?,
      periodFrom: parseDate(json['periodFrom']),
      periodTo: parseDate(json['periodTo']),
      totalGrossAmount: parseAmount(json['totalGrossAmount']),
      deductionAmount: parseAmount(json['deductionAmount']),
      netAmount: parseAmount(json['netAmount']),
      settlementDate: DateTime.parse(json['settlementDate'] as String),
      status: json['status'] as String? ?? 'OPEN',
      notes: json['notes'] as String?,
    );
  }
}
