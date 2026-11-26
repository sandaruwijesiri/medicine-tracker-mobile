import 'dart:io';
import 'dart:convert';
import 'package:medicine_tracker/data/api.dart';
import 'package:medicine_tracker/data/models.dart';

// Run only through the disposable, in-memory server in backend_smoke.mjs.
Future<void> main(List<String> args) async {
  final api = MedicineApi()..baseUrl = args.single;
  void check(bool value, String message) {
    if (!value) throw StateError(message);
  }

  try {
    final auth = await api.post('mobile/register', {
      'name': 'Mobile integration',
      'email': 'flutter-${DateTime.now().microsecondsSinceEpoch}@example.test',
      'password': 'integration-test-123',
    });
    api.token = str(auth['accessToken']);
    check(
      (await api.get('me'))['id'] == auth['user']['id'],
      'Bearer account mismatch',
    );
    var state = await api.post('locations', {'name': 'Home'});
    final location = state['locations'][0]['id'];
    state = await api.post('medicines', {
      'name': 'Integration medicine',
      'strength': '10 mg',
      'unit': 'tablets',
      'lowStock': 5,
    });
    final medicine = state['medicines'][0]['id'];
    state = await api.post('stock', {
      'medicineId': medicine,
      'locationId': location,
      'mode': 'add',
      'quantity': 10,
    });
    final date = dateText(DateTime.now().toUtc());
    state = await api.post('schedules', {
      'medicineId': medicine,
      'amount': 1,
      'times': ['00:00'],
      'days': [0, 1, 2, 3, 4, 5, 6],
      'start': date,
      'zone': 'UTC',
    });
    final schedule = state['schedules'][0]['id'];
    state = await api.post('dose', {
      'scheduleId': schedule,
      'date': date,
      'time': '00:00',
      'status': 'taken',
    });
    check(
      number(state['stocks'][0]['quantity']) == 9,
      'Dose did not deduct exactly once',
    );
    state = await api.post('dose', {
      'scheduleId': schedule,
      'date': date,
      'time': '00:00',
      'status': 'taken',
    });
    check(number(state['stocks'][0]['quantity']) == 9, 'Retry deducted twice');
    final takenId = str(state['doses'][0]['id']);
    check(
      jsonDecode(state['doses'][0]['allocations']).isNotEmpty,
      'Taken dose has no saved stock allocation',
    );
    state = await api.post('dose-undo', {'id': takenId});
    check(
      number(state['stocks'][0]['quantity']) == 10,
      'Undo response did not restore stock',
    );
    check(state['doses'].isEmpty, 'Undo response still contains dose');
    final persisted = await api.get('state');
    check(
      number(persisted['stocks'][0]['quantity']) == 10,
      'Server did not persist the restored stock',
    );
    final insights = await api.get('mobile/insights');
    check(
      insights['medicines'][0]['medicineId'] == medicine,
      'Missing mobile supply insights',
    );
    final file = base64Encode(utf8.encode('%PDF-1.4\n%%EOF'));
    state = await api.post('prescriptions', {
      'name': 'integration.pdf',
      'date': date,
      'mime': 'application/pdf',
      'base64': file,
      'medicineId': medicine,
    });
    check(
      utf8
          .decode(await api.file(str(state['prescriptions'][0]['id'])))
          .startsWith('%PDF-'),
      'Authenticated file download failed',
    );
    state = await api.post('medicine-archive', {
      'id': medicine,
      'archived': true,
    });
    check(
      state['schedules'][0]['active'] == false,
      'Archive did not pause schedule',
    );
    await api.post('logout', {});
    try {
      await api.get('state');
      throw StateError('Logged-out token remained valid');
    } on ApiException catch (e) {
      check(e.status == 401, 'Unexpected logout response');
    }
    stdout.writeln(
      'Flutter HTTP integration passed: auth, stock, schedules, idempotent dose, Undo response/persisted stock, supply insights, files, archive and logout.',
    );
  } finally {
    api.close();
  }
}
