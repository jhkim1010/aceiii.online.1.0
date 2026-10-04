// RelojesRepository 단위 시험 — 네트워크 없이 Dio 어댑터를 페이크로 교체.
// 새 dev_dependency(mocktail 등)를 추가하지 않는다(계획 지시).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tienda_admin_app/features/relojes/relojes_repository.dart';

// 요청(method·path·data)을 기록하고 정해진 상태 코드/바디를 돌려주는 페이크 어댑터.
class _FakeAdapter implements HttpClientAdapter {
  final int statusCode;
  final Object? body; // jsonEncode 됨. null 이면 빈 바디.
  final List<RequestOptions> requests = [];

  _FakeAdapter({this.statusCode = 200, this.body});

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final text = body == null ? '' : jsonEncode(body);

    return ResponseBody.fromString(
      text,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// 연결 자체가 실패하는 상황(타임아웃·DNS 등) 재현용.
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw Exception('sin conexión (fake)');
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(HttpClientAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://test.local/api'));
  dio.httpClientAdapter = adapter;

  return dio;
}

void main() {
  group('WatchDevice.fromJson', () {
    test('id/model/lastSeenAt 파싱', () {
      final d = WatchDevice.fromJson({
        'id': 3,
        'model': 'Galaxy Watch6',
        'issuedAt': '2026-10-04T12:00:00Z',
        'lastSeenAt': null,
        'expiresAt': '2027-01-02T12:00:00Z',
      });
      expect(d.id, 3);
      expect(d.model, 'Galaxy Watch6');
      expect(d.lastSeenAt, isNull);
    });

    test('model 이 null 이면 displayName == Reloj', () {
      final d = WatchDevice.fromJson({
        'id': 1,
        'model': null,
        'issuedAt': '2026-10-04T12:00:00Z',
        'lastSeenAt': null,
        'expiresAt': '2027-01-02T12:00:00Z',
      });
      expect(d.displayName, 'Reloj');
    });
  });

  group('claimCode', () {
    test('공백·하이픈·소문자 정규화 후 body 로 POST, URL 에 코드 없음', () async {
      final adapter = _FakeAdapter(statusCode: 204);
      final repo = RelojesRepository(_dioWith(adapter));

      await repo.claimCode(' k7q4-29xm ');

      expect(adapter.requests, hasLength(1));
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.path, '/watch/pairing-codes/claim');
      expect(req.data, {'userCode': 'K7Q429XM'});
    });

    test('404 → ClaimError.invalid', () async {
      final repo = RelojesRepository(
        _dioWith(_FakeAdapter(statusCode: 404, body: {'message': 'x'})),
      );

      await expectLater(
        repo.claimCode('ABCD1234'),
        throwsA(isA<RelojesException>()
            .having((e) => e.error, 'error', ClaimError.invalid)),
      );
    });

    test('403 → ClaimError.notAdmin', () async {
      final repo = RelojesRepository(
        _dioWith(_FakeAdapter(statusCode: 403, body: {'message': 'x'})),
      );

      await expectLater(
        repo.claimCode('ABCD1234'),
        throwsA(isA<RelojesException>()
            .having((e) => e.error, 'error', ClaimError.notAdmin)),
      );
    });

    test('429 → ClaimError.tooMany', () async {
      final repo = RelojesRepository(
        _dioWith(_FakeAdapter(statusCode: 429)),
      );

      await expectLater(
        repo.claimCode('ABCD1234'),
        throwsA(isA<RelojesException>()
            .having((e) => e.error, 'error', ClaimError.tooMany)),
      );
    });

    test('연결 오류 → ClaimError.network', () async {
      final repo = RelojesRepository(_dioWith(_ThrowingAdapter()));

      await expectLater(
        repo.claimCode('ABCD1234'),
        throwsA(isA<RelojesException>()
            .having((e) => e.error, 'error', ClaimError.network)),
      );
    });
  });

  group('revoke', () {
    test('DELETE /watch/devices/{id}', () async {
      final adapter = _FakeAdapter(statusCode: 204);
      final repo = RelojesRepository(_dioWith(adapter));

      await repo.revoke(3);

      final req = adapter.requests.single;
      expect(req.method, 'DELETE');
      expect(req.path, '/watch/devices/3');
    });
  });

  group('listDevices', () {
    test('200 [] → 빈 목록', () async {
      final repo = RelojesRepository(
        _dioWith(_FakeAdapter(statusCode: 200, body: [])),
      );

      final list = await repo.listDevices();

      expect(list, isEmpty);
    });

    test('200 데이터 있음 → WatchDevice 목록으로 변환', () async {
      final repo = RelojesRepository(
        _dioWith(_FakeAdapter(statusCode: 200, body: [
          {
            'id': 5,
            'model': 'Galaxy Watch6',
            'issuedAt': '2026-10-04T12:00:00Z',
            'lastSeenAt': '2026-10-04T13:00:00Z',
            'expiresAt': '2027-01-02T12:00:00Z',
          },
        ])),
      );

      final list = await repo.listDevices();

      expect(list, hasLength(1));
      expect(list.first.id, 5);
    });

    test('403 → RelojesException(notAdmin), 빈 목록으로 삼키지 않는다', () async {
      final repo = RelojesRepository(
        _dioWith(_FakeAdapter(statusCode: 403, body: {'message': 'x'})),
      );

      await expectLater(
        repo.listDevices(),
        throwsA(isA<RelojesException>()
            .having((e) => e.error, 'error', ClaimError.notAdmin)),
      );
    });
  });
}
