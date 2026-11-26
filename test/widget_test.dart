import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicine_tracker/data/api.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_tracker/data/controller.dart';
import 'package:medicine_tracker/data/models.dart';
import 'package:medicine_tracker/main.dart';

class RecordingController extends AppController {
  final calls = <Json>[];
  @override
  Future<void> mutate(String command, Json input) async {
    calls.add({'command': command, ...input});
    if (command == 'dose') {
      state!.json['occurrences'][0]['status'] = input['status'];
      state!.json['doses'] = [
        {
          'id': 'recorded',
          'scheduleId': input['scheduleId'],
          'date': input['date'],
          'time': input['time'],
          'status': input['status'],
          'createdAt': DateTime.now().toUtc().toIso8601String(),
          'allocations': '[]',
        },
      ];
      if (input['status'] == 'taken') state!.json['stocks'][0]['quantity'] = 19;
    }
    if (command == 'dose-undo') {
      state!.json['occurrences'][0]['status'] = 'pending';
      state!.json['doses'] = [];
      state!.json['stocks'][0]['quantity'] = 20;
    }
    notifyListeners();
  }
}

RecordingController demo() => RecordingController()
  ..loading = false
  ..user = {'id': 'u', 'name': 'Alex', 'email': 'alex@example.test'}
  ..lastSync = DateTime(2026, 11, 19, 9)
  ..state = CabinetState({
    'medicines': [
      {
        'id': 'm',
        'name': 'Vitamin D',
        'brandName': 'Daily care',
        'strength': '1000 IU',
        'unit': 'tablets',
        'lowStock': 10,
        'archivedAt': null,
      },
    ],
    'stocks': [
      {
        'id': 'b',
        'medicineId': 'm',
        'locationId': 'l',
        'quantity': 20,
        'expiry': '2027-12-01',
      },
    ],
    'locations': [
      {'id': 'l', 'name': 'Home cabinet'},
    ],
    'occurrences': [
      {
        'id': 'o',
        'scheduleId': 's',
        'medicineId': 'm',
        'date': '2026-11-19',
        'time': '09:00',
        'zone': 'Asia/Colombo',
        'amount': 1,
        'locationId': null,
        'status': 'pending',
        'due': true,
        'overdue': false,
        'instructions': 'After breakfast',
      },
    ],
    'schedules': [],
    'categories': [],
    'history': [],
    'doses': [],
    'prescriptions': [],
  });
void main() {
  setUpAll(() async {
    final icons = FontLoader("MaterialIcons")
      ..addFont(rootBundle.load("fonts/MaterialIcons-Regular.otf"));
    await icons.load();
    final font = File(r'C:/Windows/Fonts/segoeui.ttf');
    if (await font.exists()) {
      final loader = FontLoader('Roboto')
        ..addFont(Future.value(ByteData.sublistView(await font.readAsBytes())));
      await loader.load();
    }
  });
  testWidgets('sign-in screen validates and switches account mode', (
    tester,
  ) async {
    final app = AppController()..loading = false;
    await tester.pumpWidget(MedicineTrackerApp(controller: app));
    expect(find.text('A little care,\nevery day.'), findsOneWidget);
    await tester.tap(find.text('Create account').first);
    await tester.pumpAndSettle();
    expect(find.text('Your name'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byType(FilledButton),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Enter your name'), findsOneWidget);
    app.dispose();
  });
  testWidgets(
    'taking a dose records immediately without a popup and supports one-tap Undo',
    (tester) async {
      final app = demo();
      await tester.pumpWidget(MedicineTrackerApp(controller: app));
      expect(find.text('Your daily care'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Confirm taken'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Confirm taken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm taken'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(app.calls.single['status'], 'taken');
      expect(app.state!.stocks[0]['quantity'], 19);
      await tester.tap(
        find.descendant(of: find.byType(SnackBar), matching: find.text('Undo')),
      );
      await tester.pumpAndSettle();
      expect(app.calls.last['command'], 'dose-undo');
      expect(app.state!.stocks[0]['quantity'], 20);
      await tester.tap(find.text('Cabinet'));
      await tester.pumpAndSettle();
      expect(find.text('Your cabinet'), findsOneWidget);
      expect(find.text('Daily care · Vitamin D'), findsOneWidget);
      await tester.tap(find.byTooltip('Add medicine'));
      await tester.pumpAndSettle();
      expect(find.text('Add medicine'), findsOneWidget);
      expect(tester.takeException(), isNull);
      app.dispose();
    },
  );
  testWidgets('small phone and larger text render without layout errors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final app = demo();
    await tester.pumpWidget(MedicineTrackerApp(controller: app));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Prescriptions'), findsOneWidget);
    expect(tester.takeException(), isNull);
    app.dispose();
  });
  testWidgets('capture Today and Cabinet for visual review', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = demo();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MedicineTrackerApp(controller: app),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('artifacts');
        await dir.create(recursive: true);
        await File(
          '${dir.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('today');
    await tester.tap(find.text('Cabinet'));
    await tester.pumpAndSettle();
    await capture('cabinet');
    expect(tester.takeException(), isNull);
    app.dispose();
  });
  testWidgets(
    'brand selection permits automatic allocation without another confirmation',
    (tester) async {
      final app = demo();
      app.state!.json['occurrences'][0]['doseCalculation'] = {
        'drugNameOnly': true,
      };
      await tester.pumpWidget(MedicineTrackerApp(controller: app));
      await tester.scrollUntilVisible(
        find.text('Confirm taken'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Confirm taken'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm taken'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text('Continue without specifying\nAutomatic stock allocation'),
      );
      await tester.pumpAndSettle();
      expect(app.calls.single['status'], 'taken');
      expect(app.calls.single.containsKey('takenMedicineId'), false);
      expect(find.byType(AlertDialog), findsNothing);
      app.dispose();
    },
  );
  testWidgets(
    'skipping still asks for confirmation and Undo remains available',
    (tester) async {
      final app = demo();
      await tester.pumpWidget(MedicineTrackerApp(controller: app));
      await tester.scrollUntilVisible(
        find.text('Skip'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Skip this dose?'), findsOneWidget);
      expect(app.calls, isEmpty);
      await tester.tap(find.text('Confirm skip'));
      await tester.pumpAndSettle();
      expect(app.calls.single['status'], 'skipped');
      expect(app.state!.stocks[0]['quantity'], 20);
      await tester.scrollUntilVisible(
        find.text('Recently recorded doses'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Recently recorded doses'), findsOneWidget);
      app.dispose();
    },
  );
  testWidgets('selectors can be searched and choice is explicit', (
    tester,
  ) async {
    final app = demo();
    await tester.pumpWidget(MedicineTrackerApp(controller: app));
    await tester.tap(find.text('Cabinet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All locations'));
    await tester.pumpAndSettle();
    final search = find.widgetWithText(TextField, 'Search stock location');
    await tester.enterText(search, 'Home');
    await tester.pumpAndSettle();
    expect(find.text('Home cabinet'), findsOneWidget);
    await tester.tap(find.text('Home cabinet'));
    await tester.pumpAndSettle();
    expect(find.text('Home cabinet'), findsOneWidget);
    app.dispose();
  });
  testWidgets('reminder attention warning appears in Settings, not Today', (
    tester,
  ) async {
    final app = demo()..doseReminders = true;
    app.reminders.warning =
        'Precise alarms are not allowed. Dose reminders may arrive late.';
    await tester.pumpWidget(MedicineTrackerApp(controller: app));
    await tester.pumpAndSettle();
    expect(find.text('Reminders need attention'), findsNothing);
    expect(find.text(app.reminders.warning!), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text(app.reminders.warning!),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(app.reminders.warning!), findsOneWidget);
    app.dispose();
  });

  testWidgets(
    'Cabinet renders the actual Undo response while forecasts are still loading',
    (tester) async {
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      final fixture = demo();
      final initial = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(fixture.state!.json)) as Map,
      );
      fixture.dispose();
      initial['stocks'][0]['quantity'] = 9;
      final restored = Map<String, dynamic>.from(
        jsonDecode(jsonEncode(initial)) as Map,
      );
      restored['stocks'][0]['quantity'] = 10;
      final forecast = Completer<http.Response>();
      final requested = Completer<void>();
      final api = MedicineApi(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/mobile/insights')) {
            requested.complete();
            return forecast.future;
          }
          return http.Response(jsonEncode(restored), 200);
        }),
      )..baseUrl = 'https://example.test';
      final app = AppController(api: api)
        ..loading = false
        ..user = {'id': 'u', 'name': 'Alex'}
        ..state = CabinetState(initial);
      await tester.pumpWidget(MedicineTrackerApp(controller: app));
      await tester.tap(find.text('Cabinet'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('9 tablets available'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('9 tablets available'), findsOneWidget);
      final undo = app.mutate('dose-undo', {'id': 'recorded'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      try {
        expect(requested.isCompleted, true);
        expect(find.text('10 tablets available'), findsOneWidget);
        expect(find.text('9 tablets available'), findsNothing);
      } finally {
        forecast.complete(
          http.Response('{"medicines":[],"schedules":[]}', 200),
        );
        await tester.pumpAndSettle();
        await undo;
        app.dispose();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    },
  );
}
