// 매장 정보 모델 — 로그인 응답에서 vendor가 연결된 매장 목록
class StoreInfo {
  final int vendorId;
  final int storeId;
  final String storeName;
  final String? logoUrl;
  final String? aliasName;

  StoreInfo({
    required this.vendorId,
    required this.storeId,
    required this.storeName,
    this.logoUrl,
    this.aliasName,
  });

  // JSON 응답을 StoreInfo 객체로 변환
  factory StoreInfo.fromJson(Map<String, dynamic> json) => StoreInfo(
        vendorId: json['vendorId'] as int,
        storeId: json['storeId'] as int,
        storeName: (json['storeName'] as String?) ?? '',
        logoUrl: json['logoUrl'] as String?,
        aliasName: json['aliasName'] as String?,
      );
}
