import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import 'console_repository.dart';

/// Estado de actividad de una tienda (texto, color, punto) — **una sola regla** para la lista de
/// Clientes y el detalle (antes cada pantalla tenía su copia).
///
/// [2026-10-20 usuario] «si tuvo ventas hoy, que diga Activa hoy»: `salesToday` viene del servidor
/// con el día de Buenos Aires, así no depende de la hora del teléfono ni de la sesión.
(String, Color, String) estadoTienda(Tenant t, {DateTime? ahora}) {
  final now = ahora ?? DateTime.now();
  final la = t.lastActivityAt;
  if (la != null && now.difference(la).inMinutes <= 5) return ('En línea', AppColors.green, 'on');
  // «hoy» en Buenos Aires (UTC−3, sin horario de verano), no en la hora del teléfono [CODEX]
  DateTime ba(DateTime d) => d.toUtc().subtract(const Duration(hours: 3));
  final sameDay = la != null &&
      ba(la).year == ba(now).year &&
      ba(la).month == ba(now).month &&
      ba(la).day == ba(now).day;
  if (sameDay || t.salesToday > 0) return ('Activa hoy', AppColors.green, 'on');
  if (la == null) return ('Inactiva', AppColors.dim, 'off');
  if (now.difference(la).inDays <= 3) return ('Sin uso hoy', AppColors.amber, 'idle');

  return ('Inactiva', AppColors.dim, 'off');
}
