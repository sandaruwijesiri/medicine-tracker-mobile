import 'package:timezone/timezone.dart' as tz;

typedef Json = Map<String, dynamic>;

List<Json> records(dynamic value) => (value as List? ?? [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();
String str(dynamic value) => value?.toString() ?? '';
double number(dynamic value) => (value as num?)?.toDouble() ?? 0;
String quantity(dynamic value) =>
    number(value).toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
String dateText(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
String medicineName(Json? m) {
  if (m == null) return 'Deleted medicine';
  final brand = str(m['brandName']);
  final name = str(m['name']);
  return brand.isEmpty
      ? name
      : name.isEmpty
      ? brand
      : '$brand · $name';
}

bool anyBrandSchedule(Json schedule) =>
    (schedule['doseCalculation'] as Map?)?['drugNameOnly'] == true;
String scheduleMedicineName(Json? medicine, Json schedule) =>
    anyBrandSchedule(schedule)
    ? '${str(medicine?['name'])} · Any brand'
    : medicineName(medicine);

// Preserve the stored reference ID when grouping interchangeable brand entries.
// Changing it would detach a schedule from its existing dose history.
Map<String, String> scheduleMedicineOptions(
  CabinetState state, {
  required bool anyBrand,
  String referenceId = '',
}) {
  final options = <String, String>{'': 'Choose medicine'};
  final medicines = [...state.activeMedicines];
  final reference = state.medicine(referenceId);
  if (anyBrand && reference != null) {
    medicines.removeWhere((m) => m['id'] == referenceId);
    medicines.insert(0, reference);
  }
  final seen = <String>{};
  for (final medicine in medicines) {
    final name = str(medicine['name']);
    if (anyBrand && name.isEmpty) continue;
    final key =
        '${name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}|${str(medicine['strength']).toLowerCase().replaceAll(RegExp(r'\s+'), '')}|${medicine['unit']}';
    if (anyBrand && !seen.add(key)) continue;
    options[str(medicine['id'])] =
        '${anyBrand ? name : medicineName(medicine)} · ${medicine['strength']} · ${medicine['unit']}';
  }
  return options;
}

class CabinetState {
  CabinetState(this.json);
  final Json json;
  List<Json> get medicines => records(json['medicines']);
  List<Json> get activeMedicines =>
      medicines.where((m) => m['archivedAt'] == null).toList();
  List<Json> get stocks => records(json['stocks']);
  List<Json> get schedules => records(json['schedules']);
  List<Json> get occurrences => records(json['occurrences']);
  List<Json> get categories => records(json['categories']);
  List<Json> get locations => records(json['locations']);
  List<Json> get prescriptions => records(json['prescriptions']);
  List<Json> get history => records(json['history']);
  List<Json> get doses => records(json['doses']);
  Json? medicine(dynamic id) => find(medicines, id);
  static Json? find(List<Json> list, dynamic id) {
    for (final row in list) {
      if (row['id'] == id) return row;
    }
    return null;
  }

  String location(dynamic id) =>
      id == null ? 'Any location' : str(find(locations, id)?['name']);
  String category(dynamic id) {
    final parts = <String>[];
    final seen = <String>{};
    while (id != null && seen.add(str(id))) {
      final row = find(categories, id);
      if (row == null) break;
      parts.insert(0, str(row['name']));
      id = row['parentId'];
    }
    return parts.isEmpty ? 'Uncategorized' : parts.join(' / ');
  }

  List<Json> todayTimeline() {
    final rows = occurrences;
    rows.sort((a, b) {
      final status = (a['status'] == 'pending' ? 0 : 1).compareTo(
        b['status'] == 'pending' ? 0 : 1,
      );
      if (status != 0) return status;
      final aAt = occurrenceTime(a);
      final bAt = occurrenceTime(b);
      if (aAt != null && bAt != null) return aAt.compareTo(bAt);
      return '${a['date']}/${a['time']}'.compareTo('${b['date']}/${b['time']}');
    });
    return rows;
  }

  List<Json> recentDoses({DateTime? now}) {
    final current = now ?? DateTime.now();
    return doses.where((dose) {
      final at = DateTime.tryParse(str(dose['createdAt']));
      if (at == null) return false;
      final age = current.difference(at);
      return !age.isNegative &&
          age < const Duration(hours: 24) &&
          (dose['status'] == 'skipped' ||
              (dose['status'] == 'taken' &&
                  str(dose['allocations']).isNotEmpty));
    }).toList();
  }

  double available(String id, {DateTime? now}) {
    final today = dateText(now ?? DateTime.now());
    return stocks
        .where(
          (b) =>
              b['medicineId'] == id &&
              (str(b['expiry']).isEmpty ||
                  str(b['expiry']).compareTo(today) >= 0),
        )
        .fold(0.0, (sum, b) => sum + number(b['quantity']));
  }
}

DateTime? occurrenceTime(Json dose) {
  final local = DateTime.tryParse('${dose['date']}T${dose['time']}');
  if (local == null) return null;
  try {
    return tz.TZDateTime(
      tz.getLocation(str(dose['zone'])),
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
  } catch (_) {
    return local;
  }
}

Json stockAlertSettings(Json medicine) => medicine['lowStockAlert'] is Map
    ? Map<String, dynamic>.from(medicine['lowStockAlert'] as Map)
    : {
        'enabled': true,
        'scope': 'brand',
        'metric': 'days',
        'threshold': medicine['lowStock'] ?? 10,
        'time': '09:00',
      };
Json stockAlertStatus(
  CabinetState state,
  Json medicine,
  Json insights,
  DateTime now, {
  int futureDays = 0,
}) {
  final settings = stockAlertSettings(medicine);
  String norm(dynamic v) =>
      str(v).trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final ids = state.activeMedicines
      .where(
        (m) => settings['scope'] == 'brand'
            ? m['id'] == medicine['id']
            : norm(m['name']).isNotEmpty &&
                  norm(m['name']) == norm(medicine['name']) &&
                  norm(m['strength']).replaceAll(' ', '') ==
                      norm(medicine['strength']).replaceAll(' ', '') &&
                  m['unit'] == medicine['unit'],
      )
      .map((m) => m['id'])
      .toSet();
  final date = dateText(now.add(Duration(days: futureDays)));
  final rawQuantity = state.stocks
      .where(
        (b) =>
            ids.contains(b['medicineId']) &&
            (str(b['expiry']).isEmpty || str(b['expiry']).compareTo(date) >= 0),
      )
      .fold(0.0, (sum, b) => sum + number(b['quantity']));
  final quantity = double.parse(rawQuantity.toStringAsFixed(3));
  final insight = CabinetState.find(
    records(
      insights['medicines'],
    ).map((s) => {...s, 'id': s['medicineId']}).toList(),
    medicine['id'],
  );
  final stock = insight?['stockAlert'] as Map?;
  final remaining = stock != null
      ? stock['daysRemaining']
      : insight?['daysOfSupply'];
  final calculated = DateTime.tryParse(str(insights['calculatedAt'])) ?? now;
  final elapsed = now.difference(calculated).inDays.clamp(0, 366);
  final days = remaining == null
      ? null
      : (number(remaining) - elapsed - futureDays).clamp(0, double.infinity);
  final value = settings['metric'] == 'quantity' ? quantity : days;
  return {
    'settings': settings,
    'quantity': quantity,
    'daysRemaining': days,
    'low':
        medicine['archivedAt'] == null &&
        settings['enabled'] == true &&
        value != null &&
        value <= number(settings['threshold']),
    'groupKey': settings['scope'] == 'brand'
        ? medicine['id']
        : '${norm(medicine['name'])}|${norm(medicine['strength']).replaceAll(' ', '')}|${medicine['unit']}',
  };
}
