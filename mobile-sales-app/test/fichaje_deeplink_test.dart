// parseFichajeDeeplink 단위 테스트 — /m/fichaje 딥링크 파싱 계약(37-08 Task 1).
// 유효 QR → FichajeQr, /m/stock·오형식·파라미터 누락 → null.
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_sales_app/features/attendance/data/attendance_dto.dart';
import 'package:mobile_sales_app/features/attendance/views/fichaje_scanner_sheet.dart';

void main() {
  group('parseFichajeDeeplink', () {
    test('유효한 /m/fichaje 를 FichajeQr 로 파싱', () {
      final qr = parseFichajeDeeplink('/m/fichaje?s=6&b=12&d=2026-07-11&t=abc');
      expect(qr, isNotNull);
      expect(qr!.s, 6);
      expect(qr.b, 12);
      expect(qr.d, '2026-07-11');
      expect(qr.t, 'abc');
    });

    test('절대 URL(https://host/m/fichaje...) 도 파싱', () {
      final qr = parseFichajeDeeplink(
          'https://ventago.coolsistema.com/m/fichaje?s=9&b=3&d=2026-07-11&t=xyz.token');
      expect(qr, isNotNull);
      expect(qr!.s, 9);
      expect(qr.b, 3);
      expect(qr.t, 'xyz.token');
    });

    test('/m/stock 딥링크 → null (다른 QR 타입)', () {
      expect(parseFichajeDeeplink('/m/stock?s=6&p=100'), isNull);
    });

    test('null / 빈 문자열 → null', () {
      expect(parseFichajeDeeplink(null), isNull);
      expect(parseFichajeDeeplink(''), isNull);
    });

    test('오형식 문자열 → null', () {
      expect(parseFichajeDeeplink('hola mundo'), isNull);
      expect(parseFichajeDeeplink('::::'), isNull);
    });

    test('s 누락 → null', () {
      expect(parseFichajeDeeplink('/m/fichaje?b=12&d=2026-07-11&t=abc'), isNull);
    });

    test('b 누락 → null', () {
      expect(parseFichajeDeeplink('/m/fichaje?s=6&d=2026-07-11&t=abc'), isNull);
    });

    test('d 누락 → null', () {
      expect(parseFichajeDeeplink('/m/fichaje?s=6&b=12&t=abc'), isNull);
    });

    test('t 누락 → null', () {
      expect(parseFichajeDeeplink('/m/fichaje?s=6&b=12&d=2026-07-11'), isNull);
    });

    test('s 가 숫자가 아니면 → null', () {
      expect(parseFichajeDeeplink('/m/fichaje?s=abc&b=12&d=2026-07-11&t=abc'), isNull);
    });

    test('빈 t → null', () {
      expect(parseFichajeDeeplink('/m/fichaje?s=6&b=12&d=2026-07-11&t='), isNull);
    });
  });

  group('fichajeErrorCopy', () {
    test('백엔드 코드 → es-AR 카피 매핑', () {
      expect(fichajeErrorCopy('QR_EXPIRED'), 'Pedí el QR de hoy');
      expect(fichajeErrorCopy('QR_OTHER_STORE'), 'QR de otra tienda');
      expect(fichajeErrorCopy('RESELLER_NOT_APPROVED'), 'Tienda no aprobada por admin');
    });

    test('미지 코드 → 제네릭 카피', () {
      expect(fichajeErrorCopy(null), isNotEmpty);
      expect(fichajeErrorCopy('WHATEVER'), isNotEmpty);
    });
  });
}
