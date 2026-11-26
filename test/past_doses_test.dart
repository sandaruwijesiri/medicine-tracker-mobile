import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:medicine_tracker/data/api.dart';
import 'package:medicine_tracker/data/controller.dart';
import 'package:medicine_tracker/data/models.dart';
import 'package:medicine_tracker/ui/past_doses.dart';

class PastController extends AppController {
  PastController(MedicineApi api) : super(api: api);
  final calls = <Json>[];
  @override
  Future<void> mutate(String command, Json input) async {
    calls.add({'command': command, ...input});
  }
}

void main() {
  testWidgets(
    'past doses cycle all states, retain drafts across pages and filters, and keep controls visible',
    (tester) async {
      tester.view.physicalSize = const Size(390, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final queries = <Json>[];
      final api = MedicineApi(
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Json;
          queries.add(body);
          final page = body['page'] as int;
          return http.Response(
            jsonEncode({
              'page': page,
              'pages': body['pageSize'] == 'all' ? 1 : 3,
              'total': 60,
              'rows': List.generate(
                25,
                (i) => {
                  'id': 's/$page/$i',
                  'scheduleId': 's',
                  'medicineId': 'm',
                  'date': '2020-01-01',
                  'time': '08:00',
                  'zone': 'Asia/Colombo',
                  'amount': 1,
                  'status': 'pending',
                },
              ),
            }),
            200,
          );
        }),
      )..baseUrl = 'http://test.local';
      final app = PastController(api)
        ..state = CabinetState({
          'medicines': [
            {
              'id': 'm',
              'name': 'Medicine A',
              'strength': '500 mg',
              'unit': 'tablets',
            },
          ],
        });
      await tester.pumpWidget(MaterialApp(home: PastDosesScreen(app: app)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('?'), findsWidgets);
      expect(queries.last['sort'], 'desc');
      final legendBoxes = find.byWidgetPredicate(
        (w) => w is IconButton && w.onPressed == null && w.icon is Container,
      );
      expect(legendBoxes, findsNWidgets(3));
      await tester.tap(legendBoxes.first);
      await tester.pump();
      expect(find.text('Save changes'), findsOneWidget);
      final sortDropdown = find.byType(DropdownButtonFormField<String>).at(1);
      await tester.tap(sortDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ascending (oldest first)').last);
      await tester.pumpAndSettle();
      expect(queries.last['sort'], 'asc');
      expect(queries.last['page'], 1);

      await tester.drag(find.byType(ListView), const Offset(0, -350));
      await tester.pumpAndSettle();
      final first = find.byTooltip('Not recorded').first;
      await tester.tap(first);
      await tester.pump();
      expect(find.byTooltip('Taken'), findsOneWidget);
      await tester.tap(find.byTooltip('Taken'));
      await tester.pump();
      expect(find.byTooltip('Not taken'), findsOneWidget);
      await tester.tap(find.byTooltip('Not taken'));
      await tester.pump();
      expect(find.text('Save changes'), findsOneWidget);
      await tester.tap(find.byTooltip('Not recorded').first);
      await tester.pump();
      expect(find.text('Save changes (1)'), findsOneWidget);
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      expect(queries.last['page'], 2);
      expect(find.text('Save changes (1)'), findsOneWidget);
      await tester.drag(find.byType(ListView), const Offset(0, 1500));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descending (newest first)').last);
      await tester.pumpAndSettle();
      expect(queries.last['sort'], 'desc');
      expect(queries.last['page'], 1);
      expect(find.text('Save changes (1)'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(
        tester.getBottomLeft(find.text('Save changes (1)')).dy,
        lessThan(700),
      );
      expect(find.byTooltip('Next page').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Save changes (1)'));
      await tester.pumpAndSettle();
      expect(app.calls.single['command'], 'past-doses-save');
      expect((app.calls.single['changes'] as List).single['status'], 'taken');
      await tester.tap(find.byType(DropdownButton<String>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('All').last);
      await tester.pumpAndSettle();
      expect(queries.last['pageSize'], 'all');
      expect(queries.last['page'], 1);
      expect(tester.takeException(), isNull);
    },
  );
}
