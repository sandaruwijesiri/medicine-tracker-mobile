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
    return tz.TZDateTime(tz.getLocation(str(dose['zone'])), local.year,
        local.month, local.day, local.hour, local.minute);
  } catch (_) {
    return local;
  }
}
