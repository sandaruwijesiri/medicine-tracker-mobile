import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_tracker/data/controller.dart';
import 'package:medicine_tracker/data/models.dart';
import 'package:medicine_tracker/ui/forms.dart';
import 'package:medicine_tracker/ui/choice_field.dart';

class ScheduleController extends AppController {
  Json? saved;
  @override
  Future<void> mutate(String action, Json input) async {
    saved = {'action': action, ...input};
  }
}

CabinetState fixture({bool archived = false}) => CabinetState({
  'medicines': [
    {
      'id': 'a',
      'name': 'Example',
      'brandName': 'Brand A',
      'strength': '10 mg',
      'unit': 'tablets',
      'archivedAt': archived ? '2026-01-01' : null,
    },
    {
      'id': 'b',
      'name': 'Example',
      'brandName': 'Brand B',
      'strength': '10 mg',
      'unit': 'tablets',
      'archivedAt': null,
    },
  ],
  'locations': [],
});
Json plan() => {
  'id': 'plan',
  'medicineId': 'a',
  'locationId': null,
  'amount': 1,
  'times': ['08:00'],
  'days': [0, 1, 2, 3, 4, 5, 6],
  'start': '2026-01-01',
  'end': '',
  'zone': 'UTC',
  'active': true,
  'instructions': '',
  'doseCalculation': {'drugNameOnly': true, 'mode': 'quantity', 'value': 1},
};

Future<void> open(
  WidgetTester tester,
  ScheduleController app, {
  Json? schedule,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () =>
                MedicineForms.schedule(context, app, schedule: schedule),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  test(
    'any-brand options group names and preserve the archived reference ID',
    () {
      final state = fixture(archived: true);
      final options = scheduleMedicineOptions(
        state,
        anyBrand: true,
        referenceId: 'a',
      );
      expect(options.keys, ['', 'a']);
      expect(options['a'], 'Example · 10 mg · tablets');
      expect(
        scheduleMedicineName(state.medicine('a'), plan()),
        'Example · Any brand',
      );
      final specific = scheduleMedicineOptions(state, anyBrand: false);
      expect(specific.keys, ['', 'b']);
      expect(specific['b'], contains('Brand B'));
    },
  );
  testWidgets('new schedules offer any-brand and specific-brand selection', (
    tester,
  ) async {
    final app = ScheduleController()..state = fixture();
    addTearDown(app.dispose);
    await open(tester, app);
    expect(
      find.text('Drug name and pill strength — any brand'),
      findsOneWidget,
    );
    expect(find.textContaining('Brand A'), findsNothing);
    await tester.tap(find.byType(ChoiceField).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Specific brand / medicine'));
    await tester.pumpAndSettle();
    expect(find.text('Specific brand / medicine'), findsOneWidget);
    expect(find.textContaining('Brand A'), findsOneWidget);
  });
  testWidgets(
    'editing an any-brand schedule retains its mode and reference ID on save',
    (tester) async {
      final app = ScheduleController()..state = fixture(archived: true);
      addTearDown(app.dispose);
      await open(tester, app, schedule: plan());
      expect(
        find.text('Drug name and pill strength — any brand'),
        findsOneWidget,
      );
      expect(find.textContaining('Brand A'), findsNothing);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Save'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(app.saved?['medicineId'], 'a');
      expect(app.saved?['drugNameOnly'], true);
      expect(app.saved?['id'], 'plan');
    },
  );
}
