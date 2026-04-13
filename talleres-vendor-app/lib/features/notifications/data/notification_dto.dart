// 알림 DTO — 백엔드 알림 응답 매핑
import 'package:flutter/material.dart';

// 알림 데이터 전송 객체 — API 응답을 Dart 모델로 변환
class NotificationDto {
  final int id;
  final String type;
  final String title;
  final String? body;
  final int? referenceId;
  final bool isRead;
  final DateTime createdAt;

  const NotificationDto({
    required this.id,
    required this.type,
    required this.title,
    this.body,
    this.referenceId,
    required this.isRead,
    required this.createdAt,
  });

  // JSON 응답에서 DTO로 변환
  factory NotificationDto.fromJson(Map<String, dynamic> json) {
    return NotificationDto(
      id: json['id'] as int,
      type: json['type'] as String? ?? '',
      title: json['title'] as String? ?? '',
      body: json['body'] as String?,
      referenceId: json['referenceId'] as int?,
      isRead: json['isRead'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  // 알림 타입별 아이콘 — 타입에 따라 적합한 머티리얼 아이콘 반환
  IconData get icon => switch (type) {
        'NEW_ENVIO' => Icons.local_shipping,
        'DUE_SOON' => Icons.warning_amber,
        'SETTLEMENT_DONE' => Icons.payments,
        _ => Icons.notifications,
      };
}
