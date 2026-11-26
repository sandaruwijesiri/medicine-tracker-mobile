import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicine_tracker/data/api.dart';
import 'package:medicine_tracker/data/controller.dart';
import 'package:medicine_tracker/ui/auth.dart';

void main() {
  testWidgets(
    'username and temporary password reach sign-in; new password still needs ten',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final requests = <http.Request>[];
      final api = MedicineApi(
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              'challenge': {
                'type': 'NEW_PASSWORD_REQUIRED',
                'session': 'fresh-session',
                'username': 'canonical-user',
              },
            }),
            202,
          );
        }),
      )..baseUrl = 'https://example.test';
      final app = AppController(api: api);
      addTearDown(app.dispose);
      await tester.pumpWidget(MaterialApp(home: AuthScreen(app: app)));
      await tester.enterText(find.byType(TextFormField).at(0), 'Alice.Cabinet');
      await tester.enterText(find.byType(TextFormField).at(1), 'Temp8abc');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(requests.length, 1);
      expect(requests.single.url.origin, MedicineApi.productionBaseUrl);
      expect(find.text('Server connection'), findsNothing);
      expect(jsonDecode(requests.single.body)['password'], 'Temp8abc');
      expect(jsonDecode(requests.single.body)['email'], 'Alice.Cabinet');
      expect(find.text('New password'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(1), 'Short123');
      await tester.tap(find.widgetWithText(FilledButton, 'Save new password'));
      await tester.pumpAndSettle();
      expect(find.text('Use 10–128 characters'), findsOneWidget);
      expect(requests.length, 1);
    },
  );

  testWidgets('registration keeps its ten-character minimum', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var requests = 0;
    final api = MedicineApi(
      client: MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      }),
    )..baseUrl = 'https://example.test';
    final app = AppController(api: api);
    addTearDown(app.dispose);
    await tester.pumpWidget(MaterialApp(home: AuthScreen(app: app)));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), 'Alice');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'alice@example.test',
    );
    await tester.enterText(find.byType(TextFormField).at(2), 'Temp8abc');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Use 10–128 characters'), findsOneWidget);
    expect(requests, 0);
  });
}
