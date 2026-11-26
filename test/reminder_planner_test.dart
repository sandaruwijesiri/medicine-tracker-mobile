import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:medicine_tracker/data/models.dart';
import 'package:medicine_tracker/services/reminder_planner.dart';

CabinetState sample({
  List<int> days = const [0, 1, 2, 3, 4, 5, 6],
  String start = '2026-11-01',
  String end = '',
  String zone = 'Asia/Colombo',
  bool active = true,
  bool archived = false,
  List<Json> doses = const [],
}) => CabinetState({
  'medicines': [
    {
      'id': 'med',
      'name': 'Example',
      'archivedAt': archived ? '2026-01-01' : null,
      'lowStock': 3,
    },
  ],
  'schedules': [
    {
      'id': 'plan',
      'medicineId': 'med',
      'active': active,
      'zone': zone,
      'start': start,
      'end': end,
      'times': ['09:00', '20:00'],
      'days': days,
    },
  ],
  'doses': doses,
  'occurrences': [],
});
void main() {
  setUpAll(tzdata.initializeTimeZones);
  test('timeline sorts pending doses before completed doses', () {
    final state = CabinetState({
      'occurrences': [
        {
          'id': 'taken',
          'date': '2026-11-20',
          'time': '07:00',
          'status': 'taken',
        },
        {
          'id': 'later',
          'date': '2026-11-20',
          'time': '20:00',
          'status': 'pending',
        },
        {
          'id': 'due',
          'date': '2026-11-20',
          'time': '09:00',
          'status': 'pending',
        },
      ],
    });
    expect(state.todayTimeline().map((d) => d['id']), [
      'due',
      'later',
      'taken',
    ]);
  });
  test('schedule zone determines the instant independently of phone zone', () {
    final list = planReminders(
      sample(),
      {},
      DateTime.utc(2026, 11, 19, 3),
      'America/New_York',
      stock: false,
    );
    expect(list.first.when.toUtc(), DateTime.utc(2026, 11, 19, 3, 30));
    expect(list.first.data['time'], '09:00');
  });
  test('future one-shot reminders honor weekday and date bounds', () {
    final list = planReminders(
      sample(days: [5], start: '2026-11-20', end: '2026-11-20'),
      {},
      DateTime.utc(2026, 11, 19),
      'UTC',
      stock: false,
    );
    expect(list.length, 2);
    expect(list.every((n) => n.data['date'] == '2026-11-20'), true);
  });
  test('confirmed/skipped, inactive and archived doses do not schedule', () {
    final now = DateTime.utc(2026, 11, 19, 3);
    final done = sample(
      end: '2026-11-19',
      doses: [
        {
          'scheduleId': 'plan',
          'date': '2026-11-19',
          'time': '09:00',
          'status': 'taken',
        },
        {
          'scheduleId': 'plan',
          'date': '2026-11-19',
          'time': '20:00',
          'status': 'skipped',
        },
      ],
    );
    expect(planReminders(done, {}, now, 'UTC', stock: false), isEmpty);
    expect(
      planReminders(sample(active: false), {}, now, 'UTC', stock: false),
      isEmpty,
    );
    expect(
      planReminders(sample(archived: true), {}, now, 'UTC', stock: false),
      isEmpty,
    );
  });
  test(
    'overdue reminders never flood and future queue respects platform cap',
    () {
      final list = planReminders(
        sample(),
        {},
        DateTime.utc(2026, 11, 19, 4),
        'UTC',
        stock: false,
        limit: 10,
      );
      expect(list.length, 10);
      expect(list.first.data['time'], '20:00');
      expect(list.map((n) => n.id).toSet().length, list.length);
      expect(
        list.first.id,
        planReminders(
          sample(),
          {},
          DateTime.utc(2026, 11, 19, 4),
          'UTC',
          stock: false,
          limit: 10,
        ).first.id,
      );
    },
  );
  test(
    'stock alerts estimate future threshold crossings at device-local 09:00',
    () {
      final now = DateTime.utc(2026, 11, 19, 1);
      final insights = {
        'calculatedAt': now.toIso8601String(),
        'medicines': [
          {'medicineId': 'med', 'daysOfSupply': 5},
        ],
      };
      final list = planReminders(
        sample(),
        insights,
        now,
        'Asia/Colombo',
        doses: false,
      );
      expect(list.first.when.toUtc(), DateTime.utc(2026, 11, 21, 3, 30));
      expect(list.first.data['medicineIds'], ['med']);
      expect(planReminders(sample(), {}, now, 'UTC', doses: false), isEmpty);
      expect(
        planReminders(
          sample(),
          insights,
          now,
          'UTC',
          doses: false,
          stock: false,
        ),
        isEmpty,
      );
    },
  );
  test('DST spring-forward nonexistent dose time is skipped', () {
    final state = sample(
      zone: 'America/New_York',
      start: '2027-03-14',
      end: '2027-03-14',
    );
    state.json['schedules'][0]['times'] = ['02:30', '09:00'];
    final list = planReminders(
      state,
      {},
      DateTime.utc(2027, 3, 14),
      'UTC',
      stock: false,
    );
    expect(list.length, 1);
    expect(list.first.data['time'], '09:00');
  });
  test('stock totals exclude expired batches and retain undated stock', () {
    final state = CabinetState({
      'stocks': [
        {'medicineId': 'm', 'quantity': 5, 'expiry': '2026-11-18'},
        {'medicineId': 'm', 'quantity': 2.5, 'expiry': '2026-11-19'},
        {'medicineId': 'm', 'quantity': 1, 'expiry': ''},
      ],
    });
    expect(state.available('m', now: DateTime(2026, 11, 19)), 3.5);
    expect(quantity(10), '10');
    expect(quantity(0.125), '0.125');
  });
}
