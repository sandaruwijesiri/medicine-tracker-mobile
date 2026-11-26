import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicine_tracker/data/api.dart';
import 'package:medicine_tracker/data/controller.dart';
import 'package:medicine_tracker/data/models.dart';
import 'package:medicine_tracker/services/reminders.dart';

class ReminderSpy extends ReminderService {
  ReminderSpy() : super(android: true, ios: false);
  int rebuilt = 0, preciseRequests = 0;
  bool? forced;
  @override
  Future<void> reconcile(
    CabinetState state,
    Json insights, {
    required bool doses,
    required bool stock,
    bool force = false,
  }) async {
    rebuilt++;
    forced = force;
  }

  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<void> requestExactAlarms() async {
    preciseRequests++;
    exactAlarmsAllowed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('saving a username preserves the session expiry and token', () async {
    const channel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    final session = {
      'user': {'id': 'u'},
      'accessToken': 'existing-token',
      'expiresAt': '2099-01-01T00:00:00.000Z',
      'tokenType': 'Bearer',
    };
    String saved = jsonEncode(session);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') return saved;
      if (call.method == 'write') {
        saved = (call.arguments as Map)['value'] as String;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final api = MedicineApi(
      client: MockClient(
        (request) async =>
            http.Response('{"id":"u","username":"my-name"}', 200),
      ),
    )..token = 'existing-token';
    final app = AppController(api: api)..user = {'id': 'u'};
    addTearDown(app.dispose);
    await app.setUsername('my-name');
    final restored = jsonDecode(saved) as Map;
    expect(restored['expiresAt'], session['expiresAt']);
    expect(restored['accessToken'], 'existing-token');
    expect((restored['user'] as Map)['username'], 'my-name');
  });
  test('offline resume still rebuilds locally cached reminders', () async {
    final reminders = ReminderSpy();
    final api = MedicineApi(
      client: MockClient((_) async => throw http.ClientException('offline')),
    )..baseUrl = 'https://example.test';
    final app = AppController(api: api, reminders: reminders)
      ..user = {'id': 'u'}
      ..state = CabinetState({})
      ..doseReminders = true;
    await app.sync(forceReminders: true);
    expect(app.offline, true);
    expect(reminders.rebuilt, 1);
    expect(reminders.forced, true);
    app.dispose();
  });
  test(
    'enabling Android dose reminders requests precise alarms and saves preference',
    () async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      final reminders = ReminderSpy();
      final app = AppController(reminders: reminders)
        ..user = {'id': 'u'}
        ..state = CabinetState({});
      await app.setReminders(doses: true, stock: false);
      expect(app.doseReminders, true);
      expect(reminders.preciseRequests, 1);
      expect(reminders.rebuilt, 1);
      app.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
  test(
    'Undo publishes restored stock before supply estimates finish and caches the response',
    () async {
      const storageChannel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final writes = <String, String>{};
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, (call) async {
            if (call.method == 'write') {
              final args = Map<String, dynamic>.from(call.arguments as Map);
              writes[args['key'] as String] = args['value'] as String;
            }
            return null;
          });
      final estimate = Completer<http.Response>();
      final estimateRequested = Completer<void>();
      final restored = <String, dynamic>{
        'medicines': [
          {'id': 'm'},
        ],
        'stocks': [
          {'id': 'b', 'medicineId': 'm', 'quantity': 10, 'expiry': ''},
        ],
        'doses': [],
        'occurrences': [
          {'status': 'pending'},
        ],
      };
      final api = MedicineApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/dose-undo')) {
            expect(jsonDecode(request.body), {'id': 'dose'});
            return http.Response(jsonEncode(restored), 200);
          }
          if (request.url.path.endsWith('/mobile/insights')) {
            estimateRequested.complete();
            return estimate.future;
          }
          return http.Response(jsonEncode(restored), 200);
        }),
      )..baseUrl = 'https://example.test';
      final app = AppController(api: api, reminders: ReminderSpy())
        ..user = {'id': 'u'}
        ..state = CabinetState({
          'stocks': [
            {'id': 'b', 'medicineId': 'm', 'quantity': 9, 'expiry': ''},
          ],
          'doses': [
            {'id': 'dose', 'status': 'taken'},
          ],
        });
      final seen = <double>[];
      app.addListener(() => seen.add(app.state!.available('m')));
      final undo = app.mutate('dose-undo', {'id': 'dose'});
      await estimateRequested.future;
      try {
        expect(app.state!.available('m'), 10);
        expect(
          seen,
          contains(10),
          reason:
              'Restored stock must be visible without waiting for estimates/reminders.',
        );
        expect(
          jsonDecode(writes['cache']!)['state']['stocks'][0]['quantity'],
          10,
        );
      } finally {
        estimate.complete(
          http.Response('{"medicines":[],"schedules":[]}', 200),
        );
        await undo;
        app.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(storageChannel, null);
      }
    },
  );
  test('Sync publishes the server stock before estimates finish', () async {
    const storageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storageChannel, (_) async => null);
    final estimate = Completer<http.Response>();
    final requested = Completer<void>();
    final api = MedicineApi(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/mobile/insights')) {
          requested.complete();
          return estimate.future;
        }
        return http.Response(
          '{"stocks":[{"medicineId":"m","quantity":10,"expiry":""}]}',
          200,
        );
      }),
    )..baseUrl = 'https://example.test';
    final app = AppController(api: api, reminders: ReminderSpy())
      ..user = {'id': 'u'}
      ..state = CabinetState({
        'stocks': [
          {'medicineId': 'm', 'quantity': 9, 'expiry': ''},
        ],
      });
    final seen = <double>[];
    app.addListener(() => seen.add(app.state!.available('m')));
    final sync = app.sync();
    await requested.future;
    try {
      expect(seen, contains(10));
    } finally {
      estimate.complete(http.Response('{"medicines":[]}', 200));
      await sync;
      app.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(storageChannel, null);
    }
  });

  test('failed Undo does not invent a local stock restoration', () async {
    final api = MedicineApi(
      client: MockClient(
        (_) async => http.Response('{"message":"Undo failed"}', 409),
      ),
    )..baseUrl = 'https://example.test';
    final app = AppController(api: api, reminders: ReminderSpy())
      ..user = {'id': 'u'}
      ..state = CabinetState({
        'stocks': [
          {'medicineId': 'm', 'quantity': 9, 'expiry': ''},
        ],
      });
    await expectLater(
      app.mutate('dose-undo', {'id': 'dose'}),
      throwsA(isA<ApiException>()),
    );
    expect(app.state!.available('m'), 9);
    app.dispose();
  });
}
