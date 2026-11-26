import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medicine_tracker/data/models.dart';
import 'package:medicine_tracker/services/reminders.dart';

CabinetState reminderState() => CabinetState({
  'medicines': <Json>[
    {'id': 'med', 'name': 'Example', 'archivedAt': null, 'lowStock': 3},
  ],
  'schedules': <Json>[
    {
      'id': 'plan',
      'medicineId': 'med',
      'active': true,
      'zone': 'UTC',
      'start': '2036-11-01',
      'end': '',
      'times': ['09:00', '20:00'],
      'days': [0, 1, 2, 3, 4, 5, 6],
    },
  ],
  'doses': [],
  'occurrences': [],
});
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late Map<int, Map<String, dynamic>> pending;
  late List<int> cancelled;
  late Map<int, Map<String, dynamic>> active;
  late List<MethodCall> calls;
  late DateTime now;
  late bool exact, enabled, failOne, blockedChannel;
  late ReminderService service;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    pending = {};
    active = {};
    cancelled = [];
    calls = [];
    now = DateTime.utc(2036, 11, 20, 8, 59);
    exact = false;
    enabled = true;
    failOne = false;
    blockedChannel = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          final args = call.arguments is Map
              ? Map<String, dynamic>.from(call.arguments as Map)
              : <String, dynamic>{};
          switch (call.method) {
            case 'initialize':
              return true;
            case 'getNotificationAppLaunchDetails':
              return {'notificationLaunchedApp': false};
            case 'areNotificationsEnabled':
              return enabled;
            case 'requestNotificationsPermission':
              return enabled;
            case 'canScheduleExactNotifications':
              return exact;
            case 'requestExactAlarmsPermission':
              exact = true;
              return true;
            case 'createNotificationChannel':
              return null;
            case 'getNotificationChannels':
              return blockedChannel
                  ? [
                      {
                        'id': 'medicine_doses',
                        'name': 'Dose reminders',
                        'importance': 0,
                        'showBadge': true,
                        'bypassDnd': false,
                        'playSound': true,
                        'enableLights': false,
                        'enableVibration': true,
                        'ledColor': 0,
                        'audioAttributesUsage': 5,
                      },
                    ]
                  : [];
            case 'getActiveNotifications':
              return active.values.toList();
            case 'pendingNotificationRequests':
              return pending.values.toList();
            case 'zonedSchedule':
              if (failOne) {
                failOne = false;
                throw PlatformException(code: 'schedule_failed');
              }
              pending[args['id'] as int] = {
                'id': args['id'],
                'title': args['title'],
                'body': args['body'],
                'payload': args['payload'],
              };
              return null;
            case 'cancel':
              final id = args['id'] as int;
              cancelled.add(id);
              pending.remove(id);
              active.remove(id);
              return null;
            case 'cancelAll':
              pending.clear();
              return null;
            case 'show':
              active[args['id'] as int] = args;
              return null;
            default:
              throw PlatformException(code: 'unexpected_${call.method}');
          }
        });
    service = ReminderService(
      android: true,
      ios: false,
      deviceTimeZone: () async => 'UTC',
      clock: () => now,
    );
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('simultaneous doses share an alert which updates and clears', () async {
    final state = reminderState();
    state.json['medicines'].add({'id': 'med2', 'archivedAt': null});
    state.json['schedules'].add({
      ...state.schedules.first,
      'id': 'plan2',
      'medicineId': 'med2',
    });
    await service.reconcile(state, {}, doses: true, stock: false);
    final due = pending.entries.first;
    expect(due.value['body'], contains('2 medicines'));
    active[due.key] = pending.remove(due.key)!;
    now = DateTime.utc(2036, 11, 20, 9, 1);
    state.json['doses'] = [
      {
        'scheduleId': 'plan',
        'date': '2036-11-20',
        'time': '09:00',
        'status': 'taken',
      },
    ];
    await service.reconcile(state, {}, doses: true, stock: false);
    expect(active[due.key]!['body'], contains('1 medicine'));
    state.json['doses'].add({
      'scheduleId': 'plan2',
      'date': '2036-11-20',
      'time': '09:00',
      'status': 'taken',
    });
    await service.reconcile(state, {}, doses: true, stock: false);
    expect(active.containsKey(due.key), false);
  });
  test(
    'sync just after due time preserves a delayed approximate Android alarm',
    () async {
      final state = reminderState();
      await service.reconcile(state, {}, doses: true, stock: false);
      expect(pending.length, 60);
      final due = pending.entries
          .firstWhere(
            (entry) =>
                jsonDecode(entry.value['payload'])['date'] == '2036-11-20' &&
                jsonDecode(entry.value['payload'])['time'] == '09:00',
          )
          .key;
      now = DateTime.utc(2036, 11, 20, 9, 0, 30);
      await service.reconcile(state, {}, doses: true, stock: false);
      expect(cancelled, isNot(contains(due)));
      expect(pending.containsKey(due), true);
      expect(service.pending, pending.length);
    },
  );
  test(
    'taken doses and paused schedules still cancel their delayed alarms',
    () async {
      final state = reminderState();
      await service.reconcile(state, {}, doses: true, stock: false);
      final due = pending.entries
          .firstWhere(
            (entry) =>
                jsonDecode(entry.value['payload'])['time'] == '09:00' &&
                jsonDecode(entry.value['payload'])['date'] == '2036-11-20',
          )
          .key;
      now = DateTime.utc(2036, 11, 20, 9, 1);
      state.json['doses'] = [
        {
          'scheduleId': 'plan',
          'date': '2036-11-20',
          'time': '09:00',
          'status': 'taken',
        },
      ];
      await service.reconcile(state, {}, doses: true, stock: false);
      expect(cancelled, contains(due));
      state.json['schedules'][0]['active'] = false;
      await service.reconcile(state, {}, doses: true, stock: false);
      expect(pending, isEmpty);
    },
  );
  test(
    'disabled reminders cancel delayed alarms and hour-old alarms expire',
    () async {
      await service.reconcile(reminderState(), {}, doses: true, stock: false);
      now = DateTime.utc(2036, 11, 20, 9, 1);
      await service.reconcile(reminderState(), {}, doses: false, stock: false);
      expect(pending, isEmpty);
      now = DateTime.utc(2036, 11, 20, 8, 59);
      await service.reconcile(reminderState(), {}, doses: true, stock: false);
      final ids = pending.entries
          .where(
            (e) =>
                jsonDecode(e.value['payload'])['date'] == '2036-11-20' &&
                jsonDecode(e.value['payload'])['time'] == '09:00',
          )
          .map((e) => e.key)
          .toList();
      now = DateTime.utc(2036, 11, 20, 10, 1);
      await service.reconcile(reminderState(), {}, doses: true, stock: false);
      expect(pending.keys, isNot(contains(ids.single)));
    },
  );
  test(
    'permissions are visible and granting precise alarms re-arms pending alarms',
    () async {
      await service.reconcile(reminderState(), {}, doses: true, stock: false);
      expect(service.exactAlarmsAllowed, false);
      expect(service.warning, contains('may arrive late'));
      final original = calls.where((c) => c.method == 'zonedSchedule').length;
      await service.requestExactAlarms();
      await service.reconcile(reminderState(), {}, doses: true, stock: false);
      expect(
        calls.where((c) => c.method == 'zonedSchedule').length,
        greaterThan(original),
      );
      expect(
        pending.values.every(
          (p) => jsonDecode(p['payload'])['precision'] == 'exact',
        ),
        true,
      );
      enabled = false;
      await service.reconcile(reminderState(), {}, doses: true, stock: false);
      expect(service.notificationsEnabled, false);
      expect(service.warning, contains('blocked'));
    },
  );
  test(
    'one alarm failure does not abandon remaining alarms or exaggerate count',
    () async {
      failOne = true;
      await service.reconcile(reminderState(), {}, doses: true, stock: false);
      expect(pending.length, 59);
      expect(service.pending, 59);
      expect(service.warning, contains('1 reminders could not be scheduled'));
      await service.reconcile(
        reminderState(),
        {},
        doses: true,
        stock: false,
        force: true,
      );
      expect(pending.length, 60);
      expect(service.warning, isNot(contains('could not be scheduled')));
    },
  );
  test(
    'timezone lookup failure does not disable notification initialization',
    () async {
      service = ReminderService(
        android: true,
        ios: false,
        deviceTimeZone: () async => throw StateError('timezone'),
        clock: () => now,
      );
      await service.reconcile(reminderState(), {}, doses: true, stock: false);
      expect(service.ready, true);
      expect(pending.length, 60);
      expect(service.warning, contains('time zone is unavailable'));
    },
  );
  test(
    'scheduled test survives sync and immediate test exercises the dose channel',
    () async {
      exact = true;
      await service.testNotification(scheduled: true);
      final id = pending.keys.single;
      await service.reconcile(reminderState(), {}, doses: false, stock: false);
      expect(pending.containsKey(id), true);
      await service.testNotification();
      expect(calls.any((c) => c.method == 'show'), true);
    },
  );
  test(
    'blocked dose notification channel is reported and test fails clearly',
    () async {
      blockedChannel = true;
      await service.reconcile(reminderState(), {}, doses: true, stock: false);
      expect(service.doseChannelBlocked, true);
      expect(service.warning, contains('notification channel is blocked'));
      await expectLater(service.testNotification(), throwsStateError);
    },
  );
  test(
    'delayed stock alarms survive sync and restocking cancels them',
    () async {
      final state = reminderState();
      final insights = <String, dynamic>{
        'calculatedAt': now.toIso8601String(),
        'medicines': <Json>[
          {'medicineId': 'med', 'daysOfSupply': 2},
        ],
      };
      await service.reconcile(state, insights, doses: false, stock: true);
      final due = pending.entries
          .firstWhere(
            (e) => jsonDecode(e.value['payload'])['date'] == '2036-11-20',
          )
          .key;
      now = DateTime.utc(2036, 11, 20, 9, 0, 30);
      await service.reconcile(state, insights, doses: false, stock: true);
      expect(pending.containsKey(due), true);
      insights['medicines'] = [
        {'medicineId': 'med', 'daysOfSupply': 100},
      ];
      await service.reconcile(state, insights, doses: false, stock: true);
      expect(pending, isEmpty);
    },
  );
}
