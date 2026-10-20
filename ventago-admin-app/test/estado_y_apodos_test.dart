// [2026-10-20] «si tuvo ventas hoy, Activa hoy» y «nombres con apodo».
import 'package:flutter_test/flutter_test.dart';
import 'package:ventago_admin_app/core/tenant/apodos.dart';
import 'package:ventago_admin_app/features/console/console_repository.dart';
import 'package:ventago_admin_app/features/console/tenant_status.dart';

Tenant _t({int ventasHoy = 0, String? ultima, String? alias}) => Tenant.fromJson({
      'storeId': 30,
      'storeName': 'Cache',
      'aliasName': alias,
      'salesToday': ventasHoy,
      'lastActivityAt': ultima,
    });

void main() {
  final ahora = DateTime(2026, 10, 20, 18);

  test('sin sesión pero con ventas hoy → Activa hoy (era Inactiva)', () {
    expect(estadoTienda(_t(ventasHoy: 62), ahora: ahora).$1, 'Activa hoy');
  });

  test('control: sin sesión ni ventas → Inactiva', () {
    expect(estadoTienda(_t(), ahora: ahora).$1, 'Inactiva');
  });

  test('actividad hace 2 min → En línea', () {
    final hace2 = ahora.subtract(const Duration(minutes: 2)).toIso8601String();
    expect(estadoTienda(_t(ultima: hace2), ahora: ahora).$1, 'En línea');
  });

  test('apodo: la tarjeta muestra el apodo y la tabla traduce por id y por nombre', () {
    final t = _t(alias: 'cache');
    expect(t.storeName, 'cache');
    Apodos.cargar([(id: t.storeId, nombre: t.storeLegalName, apodo: t.storeName)]);
    expect(Apodos.de(30, 'Cache'), 'cache');
    expect(Apodos.de(null, 'Cache'), 'cache');
    expect(Apodos.de(999, 'Otra'), 'Otra');
  });
}
