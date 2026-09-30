import 'package:flutter_test/flutter_test.dart';
import 'package:ventago_admin_app/features/console/afip_modo_repository.dart';

void main() {
  // 서버 PreviewTransicion 과 같은 모양 (provider-switch.service.ts)
  final json = <String, dynamic>{
    'storeId': 6,
    'actual': {'provider': 'ws', 'production': false},
    'destino': {'provider': 'soap', 'production': true},
    'emisores': [
      {
        'issuerId': 3,
        'cuit': '20123456789',
        'puntoVenta': 4,
        'certSlug': 'x',
        'entornoActual': 'homo',
        'cert': {},
        'bloqueos': ['Sin certificado.'],
        'advertencias': [],
      }
    ],
    'bloqueos': ['PV 00004: sin certificado'],
    'advertencias': ['aviso'],
    'puedeAplicar': false,
    'estadoVisto': 'abcdef1234',
  };

  test('preview 파싱', () {
    final p = AfipModoPreview.fromJson(json);
    expect(p.storeId, 6);
    expect(p.actual.label, 'Gateway cool-invoice (siempre producción)');
    expect(p.destino.label, 'ARCA directo · Producción');
    expect(p.sinCambio, isFalse);
    expect(p.emisores.single.puntoVenta, 4);
    expect(p.emisores.single.bloqueos, ['Sin certificado.']);
    expect(p.puedeAplicar, isFalse);
    expect(p.estadoVisto, 'abcdef1234');
  });

  test('같은 모드면 sinCambio', () {
    final p = AfipModoPreview.fromJson({
      ...json,
      'destino': {'provider': 'ws', 'production': false},
    });
    expect(p.sinCambio, isTrue);
  });
}
