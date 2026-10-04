// RelojesScreen 위젯 시험 + AppShell 의 Relojes 진입점(admin 만) 시험.
// 새 dev_dependency(mocktail 등)를 추가하지 않는다 — repository 는 implements 로 페이크,
// AuthController 는 작은 서브클래스로 state 를 직접 주입(protected 접근은 하위 클래스 안에서만).
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tienda_admin_app/core/auth/biometric_service.dart';
import 'package:tienda_admin_app/core/network/dio_client.dart';
import 'package:tienda_admin_app/core/network/session_signal.dart';
import 'package:tienda_admin_app/core/storage/secure_storage.dart';
import 'package:tienda_admin_app/features/auth/auth_controller.dart';
import 'package:tienda_admin_app/features/auth/auth_repository.dart';
import 'package:tienda_admin_app/features/relojes/relojes_repository.dart';
import 'package:tienda_admin_app/features/relojes/relojes_screen.dart';
import 'package:tienda_admin_app/shared/app_shell.dart';

// ── 페이크 RelojesRepository (public 메서드만 구현 — private 멤버는 상속 요구 대상이 아님) ──

class _FakeRelojesRepository implements RelojesRepository {
  List<WatchDevice> devices;
  final Object? listError;
  final Object? claimError;
  final List<String> claimedCodes = [];
  final List<int> revokedIds = [];
  int listCalls = 0;

  _FakeRelojesRepository({
    this.devices = const [],
    this.listError,
    this.claimError,
  });

  @override
  Future<List<WatchDevice>> listDevices() async {
    listCalls++;
    if (listError != null) throw listError!;

    return devices;
  }

  @override
  Future<void> claimCode(String raw) async {
    claimedCodes.add(raw);
    if (claimError != null) throw claimError!;
  }

  @override
  Future<void> revoke(int id) async {
    revokedIds.add(id);
    devices = devices.where((d) => d.id != id).toList();
  }
}

WatchDevice _device({int id = 1, String? model = 'Galaxy Watch6', String? lastSeenAt}) {
  return WatchDevice.fromJson({
    'id': id,
    'model': model,
    'issuedAt': '2026-10-01T12:00:00Z',
    'lastSeenAt': lastSeenAt,
    'expiresAt': '2027-01-02T12:00:00Z',
  });
}

Future<void> _pumpScreen(WidgetTester tester, _FakeRelojesRepository repo) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [relojesRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: RelojesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

// ── 페이크 HttpClientAdapter (AppShell 하위 탭의 실제 네트워크 호출을 막는다) ──

class _AlwaysEmptyAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(<String, dynamic>{}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

// ── 페이크 AuthController — state 를 직접 주입(같은 상속 라인 안에서의 protected 접근) ──

class _FakeAuthController extends AuthController {
  _FakeAuthController(AuthUser? user)
      : super(
          AuthRepository(Dio(), SecureStorageService()),
          SecureStorageService(),
          BiometricService(),
          SessionExpiredSignal(),
        ) {
    state = AuthState(user: user);
  }
}

Future<void> _pumpAppShell(WidgetTester tester, {required List<String> roles}) async {
  final user = AuthUser(
    id: 1,
    name: 'Test',
    roles: roles,
    storeId: 6,
    storeName: 'Tienda Test',
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith((ref) => _FakeAuthController(user)),
        dioClientProvider.overrideWithValue(
          Dio(BaseOptions(baseUrl: 'https://test.local/api'))
            ..httpClientAdapter = _AlwaysEmptyAdapter(),
        ),
      ],
      child: const MaterialApp(home: AppShell()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('RelojesScreen', () {
    testWidgets('목록이 비면 안내 문구', (tester) async {
      await _pumpScreen(tester, _FakeRelojesRepository(devices: const []));

      expect(
        find.textContaining('Todavía no hay relojes vinculados'),
        findsOneWidget,
      );
    });

    testWidgets('하단 버튼 설정 안내 카드는 목록이 비어도 항상 보인다 (D-10)', (tester) async {
      await _pumpScreen(tester, _FakeRelojesRepository(devices: const []));

      expect(find.textContaining('Doble pulsación'), findsOneWidget);
    });

    testWidgets('입력이 정규화 후 8자가 아니면 버튼 비활성', (tester) async {
      await _pumpScreen(tester, _FakeRelojesRepository(devices: const []));

      await tester.enterText(find.byType(TextField), 'ABC');
      await tester.pump();

      final button = tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Vincular reloj'));
      expect(button.onPressed, isNull);
    });

    testWidgets('8자 코드 → claimCode 1회 호출 + 성공 SnackBar + 목록 재조회', (tester) async {
      final repo = _FakeRelojesRepository(devices: const []);
      await _pumpScreen(tester, repo);
      final callsBefore = repo.listCalls;

      await tester.enterText(find.byType(TextField), 'ABCD1234');
      await tester.pump();
      final button = tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Vincular reloj'));
      expect(button.onPressed, isNotNull);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Vincular reloj'));
      await tester.pumpAndSettle();

      expect(repo.claimedCodes, ['ABCD1234']);
      expect(
        find.textContaining('Reloj vinculado. En unos segundos muestra las ventas.'),
        findsOneWidget,
      );
      expect(repo.listCalls, greaterThan(callsBefore));
    });

    testWidgets('ClaimError.invalid → Código inválido o vencido', (tester) async {
      final repo = _FakeRelojesRepository(
        devices: const [],
        claimError: const RelojesException(ClaimError.invalid),
      );
      await _pumpScreen(tester, repo);

      await tester.enterText(find.byType(TextField), 'ABCD1234');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Vincular reloj'));
      await tester.pumpAndSettle();

      expect(find.text('Código inválido o vencido'), findsOneWidget);
    });

    testWidgets('ClaimError.notAdmin(claim) → mensaje de admin', (tester) async {
      final repo = _FakeRelojesRepository(
        devices: const [],
        claimError: const RelojesException(ClaimError.notAdmin),
      );
      await _pumpScreen(tester, repo);

      await tester.enterText(find.byType(TextField), 'ABCD1234');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Vincular reloj'));
      await tester.pumpAndSettle();

      expect(
        find.text('Sólo el administrador de la tienda puede vincular relojes'),
        findsOneWidget,
      );
    });

    testWidgets('ClaimError.tooMany → Demasiados intentos. Esperá un minuto.', (tester) async {
      final repo = _FakeRelojesRepository(
        devices: const [],
        claimError: const RelojesException(ClaimError.tooMany),
      );
      await _pumpScreen(tester, repo);

      await tester.enterText(find.byType(TextField), 'ABCD1234');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Vincular reloj'));
      await tester.pumpAndSettle();

      expect(find.text('Demasiados intentos. Esperá un minuto.'), findsOneWidget);
    });

    testWidgets('ClaimError.network → Sin conexión', (tester) async {
      final repo = _FakeRelojesRepository(
        devices: const [],
        claimError: const RelojesException(ClaimError.network),
      );
      await _pumpScreen(tester, repo);

      await tester.enterText(find.byType(TextField), 'ABCD1234');
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Vincular reloj'));
      await tester.pumpAndSettle();

      expect(find.text('Sin conexión'), findsOneWidget);
    });

    testWidgets('목록 행: displayName · hace N min · sin uso todavía · Quitar', (tester) async {
      final repo = _FakeRelojesRepository(devices: [
        _device(
          id: 1,
          model: 'Galaxy Watch6',
          lastSeenAt: DateTime.now().subtract(const Duration(minutes: 5)).toIso8601String(),
        ),
        _device(id: 2, model: null, lastSeenAt: null),
      ]);
      await _pumpScreen(tester, repo);

      expect(find.text('Galaxy Watch6'), findsOneWidget);
      expect(find.text('Reloj'), findsOneWidget);
      expect(find.textContaining('hace'), findsWidgets);
      expect(find.text('sin uso todavía'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Quitar'), findsNWidgets(2));
    });

    testWidgets('Quitar → confirmación → revoke + desaparece de la lista', (tester) async {
      final repo = _FakeRelojesRepository(devices: [_device(id: 7)]);
      await _pumpScreen(tester, repo);

      await tester.tap(find.widgetWithText(TextButton, 'Quitar').first);
      await tester.pumpAndSettle();
      expect(find.text('Quitar reloj'), findsOneWidget);

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Quitar'),
      ));
      await tester.pumpAndSettle();

      expect(repo.revokedIds, [7]);
      expect(find.textContaining('Todavía no hay relojes vinculados'), findsOneWidget);
    });

    testWidgets('목록 로드가 notAdmin 이면 안내 + 입력·버튼 비활성', (tester) async {
      final repo = _FakeRelojesRepository(
        listError: const RelojesException(ClaimError.notAdmin),
      );
      await _pumpScreen(tester, repo);

      expect(
        find.text('Sólo el administrador de la tienda puede vincular relojes'),
        findsOneWidget,
      );
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
      final button = tester
          .widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Vincular reloj'));
      expect(button.onPressed, isNull);
    });
  });

  group('AppShell — Relojes 진입점 (admin 만)', () {
    testWidgets('admin 역할 → 아이콘 보임 + 탭하면 RelojesScreen 이 열린다', (tester) async {
      await _pumpAppShell(tester, roles: ['admin']);

      expect(find.byIcon(Icons.watch_outlined), findsOneWidget);

      await tester.tap(find.byIcon(Icons.watch_outlined));
      await tester.pumpAndSettle();

      expect(find.byType(RelojesScreen), findsOneWidget);
    });

    testWidgets('gerente 역할 → 아이콘이 없다', (tester) async {
      await _pumpAppShell(tester, roles: ['gerente']);

      expect(find.byIcon(Icons.watch_outlined), findsNothing);
    });
  });
}
