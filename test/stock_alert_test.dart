import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:medicine_tracker/data/controller.dart';
import 'package:medicine_tracker/data/models.dart';
import 'package:medicine_tracker/services/reminder_planner.dart';
import 'package:medicine_tracker/ui/forms.dart';

const config = {
  'enabled': true,
  'scope': 'drug',
  'metric': 'quantity',
  'threshold': 6,
  'time': '17:45',
};
CabinetState sample() => CabinetState({
  'medicines': [
    {
      'id': 'a',
      'name': 'Example',
      'brandName': 'A',
      'strength': '10 mg',
      'unit': 'tablets',
      'lowStock': 10,
      'lowStockAlert': config,
      'archivedAt': null,
    },
    {
      'id': 'b',
      'name': 'Example',
      'brandName': 'B',
      'strength': '10 mg',
      'unit': 'tablets',
      'lowStock': 10,
      'lowStockAlert': config,
      'archivedAt': null,
    },
    {
      'id': 'c',
      'name': 'Example',
      'brandName': 'C',
      'strength': '20 mg',
      'unit': 'tablets',
      'lowStock': 10,
      'archivedAt': null,
    },
  ],
  'stocks': [
    {'id': 'one', 'medicineId': 'a', 'quantity': 2, 'expiry': ''},
    {'id': 'two', 'medicineId': 'b', 'quantity': 3, 'expiry': ''},
    {'id': 'three', 'medicineId': 'c', 'quantity': 100, 'expiry': ''},
    {
      'id': 'expired',
      'medicineId': 'a',
      'quantity': 100,
      'expiry': '2000-01-01',
    },
  ],
});

class AlertController extends AppController {
  Json? saved;
  @override
  Future<void> mutate(String action, Json input) async {
    saved = input;
  }
}

void main() {
  setUpAll(tzdata.initializeTimeZones);
  test(
    'drug quantity alerts exclude expiry and other strengths and honor custom local time',
    () {
      final state = sample();
      final now = DateTime.utc(2026, 11, 26, 1);
      expect(
        stockAlertStatus(state, state.medicines[0], {}, now)['quantity'],
        5,
      );
      final list = planReminders(state, {}, now, 'Asia/Colombo', doses: false);
      expect(list.length, 7);
      expect(list.first.when.hour, 17);
      expect(list.first.when.minute, 45);
      expect(list.first.data['medicineIds'], ['a']);
      expect(
        retainPendingReminder(
          jsonEncode({
            ...jsonDecode(list.first.payload) as Map,
            'at': list.first.when.toIso8601String(),
          }),
          state,
          {},
          list.first.when,
          'Asia/Colombo',
          doses: false,
          stock: true,
        ),
        true,
      );
      state.json['stocks'][0]['quantity'] = 20;
      expect(
        retainPendingReminder(
          jsonEncode({
            ...jsonDecode(list.first.payload) as Map,
            'at': list.first.when.toIso8601String(),
          }),
          state,
          {},
          list.first.when,
          'Asia/Colombo',
          doses: false,
          stock: true,
        ),
        false,
      );
      expect(
        planReminders(state, {}, now, 'Asia/Colombo', doses: false),
        isEmpty,
      );
    },
  );
  test(
    'brand-only and disabled settings are respected without a supply estimate',
    () {
      final state = sample();
      final medicine = state.medicines[0];
      medicine['lowStockAlert'] = {...config, 'scope': 'brand', 'threshold': 2};
      expect(
        stockAlertStatus(
          state,
          medicine,
          {},
          DateTime.utc(2026, 11, 26),
        )['low'],
        true,
      );
      medicine['lowStockAlert'] = {...config, 'enabled': false};
      expect(
        stockAlertStatus(
          state,
          medicine,
          {},
          DateTime.utc(2026, 11, 26),
        )['low'],
        false,
      );
      medicine['lowStockAlert'] = {...config, 'metric': 'days'};
      expect(
        stockAlertStatus(
          state,
          medicine,
          {},
          DateTime.utc(2026, 11, 26),
        )['low'],
        false,
      );
    },
  );
  test('fractional quantities trigger exactly at the configured threshold', () {
    final state = sample();
    state.json['stocks'][0]['quantity'] = 0.1;
    state.json['stocks'][1]['quantity'] = 0.2;
    final medicine = state.medicines[0];
    medicine['lowStockAlert'] = {...config, 'threshold': 0.3};
    expect(
      stockAlertStatus(state, medicine, {}, DateTime.utc(2026, 11, 26))['low'],
      true,
    );
  });
  test(
    'global defaults are inherited and explicit medicine overrides take priority',
    () {
      final state = sample();
      state.json['stockAlertDefaults'] = {
        ...config,
        'time': '18:30',
        'threshold': 1,
      };
      for (final medicine in state.json['medicines']) {
        medicine['lowStockAlert'] = null;
      }
      final now = DateTime.utc(2026, 11, 26, 1);
      var alert = stockAlertStatus(state, state.medicines[0], {}, now);
      expect((alert['settings'] as Map)['threshold'], 1);
      expect(alert['low'], false);
      state.json['stockAlertDefaults']['threshold'] = 6;
      final list = planReminders(state, {}, now, 'Asia/Colombo', doses: false);
      expect(list.first.when.hour, 18);
      expect(list.first.when.minute, 30);
      state.json['medicines'][0]['lowStockAlert'] = {
        ...config,
        'enabled': false,
      };
      alert = stockAlertStatus(state, state.medicines[0], {}, now);
      expect(alert['low'], false);
      state.json['stockAlertDefaults']['enabled'] = false;
      state.json['medicines'][1]['lowStockAlert'] = config;
      alert = stockAlertStatus(state, state.medicines[1], {}, now);
      expect(alert['low'], true);
      expect((alert['settings'] as Map)['time'], '17:45');
    },
  );
  testWidgets('global alert editor saves account defaults', (tester) async {
    final app = AlertController()..state = sample();
    addTearDown(app.dispose);
    app.state!.json['stockAlertDefaults'] = config;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => MedicineForms.stockAlertDefaults(context, app),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(app.saved, config);
  });
  testWidgets('use-global-defaults removes a medicine override on save', (
    tester,
  ) async {
    final app = AlertController()..state = sample();
    addTearDown(app.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => MedicineForms.medicine(
                context,
                app,
                medicine: app.state!.medicines[0],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Use global defaults'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Use global defaults'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(app.saved?['lowStockAlert'], null);
    expect(app.saved?['lowStock'], 10);
  });
  testWidgets(
    'medicine editor preserves custom scope threshold and reminder time on save',
    (tester) async {
      final app = AlertController()..state = sample();
      addTearDown(app.dispose);
      final medicine = app.state!.medicines[0];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    MedicineForms.medicine(context, app, medicine: medicine),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Daily reminder time'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('17:45'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Save'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(app.saved?['lowStockAlert'], config);
    },
  );
}
