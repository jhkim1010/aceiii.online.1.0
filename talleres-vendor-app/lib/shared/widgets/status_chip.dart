// StatusChip — 발송 상태를 색상 배지로 표시하는 공유 위젯
import 'package:flutter/material.dart';

// 공통 상태 배지 위젯 — PENDING/PARTIAL/COMPLETED/CANCELLED/OPEN/CLOSED 지원
class StatusChip extends StatelessWidget {
  final String status;

  const StatusChip({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    // 상태별 색상과 라벨 매핑
    final (Color color, String label) = switch (status) {
      'PENDING' => (Colors.orange, 'Pendiente'),
      'PARTIAL' => (Colors.blue, 'Parcial'),
      'COMPLETED' => (Colors.green, 'Completado'),
      'CANCELLED' => (Colors.grey, 'Cancelado'),
      'OPEN' => (Colors.orange, 'Abierto'),
      'CLOSED' => (Colors.green, 'Cerrado'),
      _ => (Colors.grey, status),
    };

    return Chip(
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
      backgroundColor: color,
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
