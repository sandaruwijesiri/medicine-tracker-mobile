import 'dart:convert';
import 'package:timezone/timezone.dart' as tz;
import '../data/models.dart';

class LocalReminder {
  const LocalReminder({
    required this.key,
    required this.when,
    required this.type,
    required this.data,
  });
  final String key;
  final tz.TZDateTime when;
  final String type;
  final Json data;
  String get payload => jsonEncode({'key': key, 'type': type, ...data});
  int get id {
    var hash = 0x811c9dc5;
    for (final byte in utf8.encode(key)) {
      hash = ((hash ^ byte) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}

// Pure planner, shared by sync and tests. Finite one-shot alarms respect start/end
// dates, recorded doses, weekdays and each schedule's own IANA time zone.
List<LocalReminder> planReminders(
  CabinetState state,
  Json insights,
  DateTime now,
  String deviceZone, {
  bool doses = true,
  bool stock = true,
  int limit = 60,
}) {
  final result = <LocalReminder>[];
  final done = {
    for (final d in [
      ...state.doses,
      ...state.occurrences.where((d) => d['status'] != 'pending'),
    ])
      '${d['scheduleId']}/${d['date']}/${d['time']}',
  };
  if (doses) {
    for (final schedule in state.schedules.where(
      (s) =>
          s['active'] == true &&
          state.medicine(s['medicineId']) != null &&
          state.medicine(s['medicineId'])?['archivedAt'] == null,
    )) {
      final location = tz.getLocation(str(schedule['zone']));
      final local = tz.TZDateTime.from(now, location);
      for (var offset = 0; offset < 30; offset++) {
        final day = tz.TZDateTime(
          location,
          local.year,
          local.month,
          local.day + offset,
        );
        final date = dateText(day);
        final end = str(schedule['end']);
        if (date.compareTo(str(schedule['start'])) < 0 ||
            (end.isNotEmpty && date.compareTo(end) > 0) ||
            !(schedule['days'] as List).contains(day.weekday % 7)) {
          continue;
        }
        for (final value in schedule['times'] as List) {
          final time = str(value);
          final parts = time.split(':').map(int.parse).toList();
          final at = tz.TZDateTime(
            location,
            day.year,
            day.month,
            day.day,
            parts[0],
            parts[1],
          );
          // Skip nonexistent spring-forward times instead of moving a medicine dose.
          if (at.hour != parts[0] || at.minute != parts[1]) continue;
          final key = '${schedule['id']}/$date/$time';
          if (!at.isAfter(now) || done.contains(key)) continue;
          result.add(
            LocalReminder(
              key: 'dose/$key',
              when: at,
              type: 'dose_due',
              data: {
                'scheduleId': schedule['id'],
                'medicineId': schedule['medicineId'],
                'date': date,
                'time': time,
              },
            ),
          );
        }
      }
    }
  }
  if (stock) {
    final location = tz.getLocation(deviceZone);
    final local = tz.TZDateTime.from(now, location);
    final calculated = DateTime.tryParse(str(insights['calculatedAt'])) ?? now;
    final elapsed = now.difference(calculated).inDays.clamp(0, 366);
    final supply = records(insights['medicines']);
    for (var offset = 0; offset < 7; offset++) {
      final at = tz.TZDateTime(
        location,
        local.year,
        local.month,
        local.day + offset,
        9,
      );
      if (!at.isAfter(now)) continue;
      final low = supply.where((s) {
        final medicine = state.medicine(s['medicineId']);
        return medicine != null &&
            medicine['archivedAt'] == null &&
            s['daysOfSupply'] != null &&
            number(s['daysOfSupply']) - elapsed - offset <=
                number(medicine['lowStock']);
      }).toList();
      if (low.isNotEmpty) {
        result.add(
          LocalReminder(
            key: 'stock/${dateText(at)}',
            when: at,
            type: 'low_stock',
            data: {
              'date': dateText(at),
              'medicineIds': low.map((m) => m['medicineId']).toList(),
            },
          ),
        );
      }
    }
  }
  final groups = <int, List<LocalReminder>>{};
  for (final reminder in result.where((r) => r.type == 'dose_due')) {
    groups
        .putIfAbsent(reminder.when.millisecondsSinceEpoch, () => [])
        .add(reminder);
  }
  result.removeWhere((r) => r.type == 'dose_due');
  for (final entry in groups.entries) {
    final members = entry.value..sort((a, b) => a.key.compareTo(b.key));
    result.add(
      LocalReminder(
        key: 'dose-group/${entry.key}',
        when: members.first.when,
        type: 'dose_due',
        data: {
          ...members.first.data,
          'items': members.map((r) => r.data).toList(),
        },
      ),
    );
  }
  result.sort((a, b) {
    final order = a.when.compareTo(b.when);
    return order == 0 ? a.key.compareTo(b.key) : order;
  });
  return result.take(limit).toList();
}

/// A delayed Android alarm can still be pending after its nominal time. Keep it
/// for an hour instead of cancelling it at the next foreground refresh. Changed,
/// paused, archived, recorded or disabled reminders are still cancelled at once.
bool retainPendingReminder(
  String? payload,
  CabinetState state,
  Json insights,
  DateTime now,
  String deviceZone, {
  required bool doses,
  required bool stock,
}) {
  if (payload == null) return false;
  try {
    final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
    final at = DateTime.tryParse(str(data['at']));
    if (at == null || now.difference(at) > const Duration(hours: 1)) {
      return false;
    }
    if (data['type'] == 'test_reminder') return true;
    if (at.isAfter(now)) return false;
    if (data['type'] == 'dose_due' && doses) {
      if (data['items'] is List) {
        return remainingDoseItems(data, state).isNotEmpty;
      }
      final schedule = CabinetState.find(state.schedules, data['scheduleId']);
      final medicine = state.medicine(schedule?['medicineId']);
      if (schedule == null ||
          schedule['active'] != true ||
          medicine == null ||
          medicine['archivedAt'] != null) {
        return false;
      }
      if (!(schedule['times'] as List).contains(data['time'])) return false;
      final location = tz.getLocation(str(schedule['zone']));
      final local = tz.TZDateTime.from(at, location);
      final date = dateText(local);
      final time =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      if (date != data['date'] ||
          time != data['time'] ||
          !(schedule['days'] as List).contains(local.weekday % 7) ||
          date.compareTo(str(schedule['start'])) < 0 ||
          (str(schedule['end']).isNotEmpty &&
              date.compareTo(str(schedule['end'])) > 0)) {
        return false;
      }
      return ![...state.doses, ...state.occurrences].any(
        (d) =>
            d['scheduleId'] == data['scheduleId'] &&
            d['date'] == date &&
            d['time'] == time &&
            d['status'] != 'pending',
      );
    }
    if (data['type'] == 'low_stock' && stock) {
      final local = tz.TZDateTime.from(at, tz.getLocation(deviceZone));
      if (local.hour != 9 ||
          local.minute != 0 ||
          dateText(local) !=
              (data['date'] ?? str(data['key']).split('/').last)) {
        return false;
      }
      final calculated =
          DateTime.tryParse(str(insights['calculatedAt'])) ?? now;
      final elapsed = now.difference(calculated).inDays.clamp(0, 366);
      return records(insights['medicines']).any((s) {
        final medicine = state.medicine(s['medicineId']);
        return medicine != null &&
            medicine['archivedAt'] == null &&
            s['daysOfSupply'] != null &&
            number(s['daysOfSupply']) - elapsed <= number(medicine['lowStock']);
      });
    }
  } catch (_) {
    return false;
  }
  return false;
}

/// Revalidate each member against current schedules and confirmations.
List<Json> remainingDoseItems(Json payload, CabinetState state) {
  final at = DateTime.tryParse(str(payload['at']));
  if (at == null) return [];
  final items = payload['items'] is List
      ? records(payload['items'])
      : [payload];
  return items
      .where(
        (item) => retainPendingReminder(
          jsonEncode({...item, 'type': 'dose_due', 'at': payload['at']}),
          state,
          {},
          at,
          'UTC',
          doses: true,
          stock: false,
        ),
      )
      .toList();
}

String doseReminderBody(Json payload) {
  final items = payload['items'] is List
      ? records(payload['items'])
      : [payload];
  final count = items.map((d) => d['medicineId']).toSet().length;
  return '$count ${count == 1 ? 'medicine needs' : 'medicines need'} taking. Open your schedule to review.';
}
