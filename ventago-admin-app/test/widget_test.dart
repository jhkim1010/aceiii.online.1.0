import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ventago_admin_app/main.dart';

void main() {
  testWidgets('App arranca en login', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: VentagoAdminApp()));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
