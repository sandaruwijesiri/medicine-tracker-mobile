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
          (state.medicine(s['medicineId'])?['archivedAt'] == null ||
              anyBrandSchedule(s)),
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
    final groups = <String, List<dynamic>>{};
    for (final medicine in state.activeMedicines) {
      final settings = stockAlertSettings(medicine);
      if (settings['enabled'] != true) continue;
      final time = str(settings['time']);
      final parts = time.split(':');
      if (parts.length != 2) continue;
      final hour = int.tryParse(parts[0]);
      final minute = int.tryParse(parts[1]);
      if (hour == null || minute == null || hour > 23 || minute > 59) continue;
      for (var offset = 0; offset < 7; offset++) {
        final at = tz.TZDateTime(
          location,
          local.year,
          local.month,
          local.day + offset,
          hour,
          minute,
        );
        if (!at.isAfter(now) || at.hour != hour || at.minute != minute) {
          continue;
        }
        final alert = stockAlertStatus(
          state,
          medicine,
          insights,
          local,
          futureDays: offset,
        );
        if (alert['low'] != true) continue;
        final key = '${dateText(at)}/$time';
        final list = groups.putIfAbsent(
          key,
          () => [at, <String>[], <String>{}],
        );
        final dedupe =
            '${alert['groupKey']}/${settings['metric']}/${settings['threshold']}';
        if ((list[2] as Set<String>).add(dedupe)) {
          (list[1] as List<String>).add(str(medicine['id']));
        }
      }
    }
    for (final group in groups.entries) {
      result.add(
        LocalReminder(
          key: 'stock/${group.key}',
          when: group.value[0] as tz.TZDateTime,
          type: 'low_stock',
          data: {
            'date': dateText(group.value[0] as tz.TZDateTime),
            'medicineIds': group.value[1],
            'time': group.key.split('/').last,
          },
        ),
      );
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
          (medicine['archivedAt'] != null && !anyBrandSchedule(schedule))) {
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
      if (dateText(local) != data['date']) return false;
      final time =
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
      final ids = data['medicineIds'] as List?;
      return state.activeMedicines.any((medicine) {
        if (ids != null && !ids.contains(medicine['id'])) return false;
        final alert = stockAlertStatus(
          state,
          medicine,
          insights,
          tz.TZDateTime.from(now, tz.getLocation(deviceZone)),
        );
        return alert['low'] == true &&
            (alert['settings'] as Map)['time'] == time;
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
