import 'choice_field.dart';
import 'package:flutter/material.dart';
import '../data/controller.dart';
import '../data/models.dart';

Future<void> openEditor(
  BuildContext context, {
  required String title,
  required Json initial,
  required List<Widget> Function(EditorState editor) fields,
  required Future<void> Function(EditorState editor) save,
}) async {
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          Editor(title: title, initial: initial, fields: fields, save: save),
    ),
  );
}

class Editor extends StatefulWidget {
  const Editor({
    super.key,
    required this.title,
    required this.initial,
    required this.fields,
    required this.save,
  });
  final String title;
  final Json initial;
  final List<Widget> Function(EditorState editor) fields;
  final Future<void> Function(EditorState editor) save;
  @override
  State<Editor> createState() => EditorState();
}

class EditorState extends State<Editor> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  late Json values;
  bool saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    values = {...widget.initial};
  }

  String value(String key) =>
      _controllers[key]?.text.trim() ?? str(values[key]);
  double numeric(String key) => double.parse(value(key));
  Widget field(
    String key,
    String label, {
    bool required = false,
    bool numeric = false,
    int lines = 1,
    String? hint,
    double min = 0,
  }) {
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: str(values[key])),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        enabled: !saving,
        maxLines: lines,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          helperMaxLines: 3,
        ),
        validator: (text) {
          if (required && (text ?? '').trim().isEmpty) return 'Enter $label';
          if (numeric && (text ?? '').isNotEmpty) {
            final n = double.tryParse(text!);
            if (n == null || !n.isFinite || n < min || n > 10000000) {
              return 'Enter a number from $min to 10,000,000';
            }
          }
          return null;
        },
      ),
    );
  }

  Widget select(
    String key,
    String label,
    Map<String, String> options, {
    void Function(String)? onChanged,
  }) {
    var selected = str(values[key]);
    if (!options.containsKey(selected)) selected = options.keys.first;
    values[key] = selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ChoiceField(
        label: label,
        value: selected,
        options: options,
        enabled: !saving,
        onChanged: (value) => setState(() {
          values[key] = value;
          onChanged?.call(value);
        }),
      ),
    );
  }

  Widget time(String key, String label) {
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: str(values[key])),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.schedule),
        ),
        validator: (value) =>
            RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value ?? '')
            ? null
            : 'Choose a reminder time',
        onTap: saving
            ? null
            : () async {
                final parts = controller.text.split(':');
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: int.tryParse(parts.first) ?? 9,
                    minute: parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
                  ),
                );
                if (picked != null && mounted) {
                  setState(
                    () => controller.text =
                        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
                  );
                }
              },
      ),
    );
  }

  Widget times(String key) {
    final current =
        value(
            key,
          ).split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList()
          ..sort();
    return FormField<String>(
      validator: (_) =>
          current.isEmpty ? 'Choose at least one dose time' : null,
      builder: (field) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Dose times'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final time in current)
                  InputChip(
                    label: Text(time),
                    onDeleted: saving
                        ? null
                        : () => setState(
                            () => values[key] =
                                (current.where((t) => t != time).toList()
                                      ..sort())
                                    .join(', '),
                          ),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('Add time'),
                  onPressed: saving || current.length >= 12
                      ? null
                      : () async {
                          final picked = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.now(),
                          );
                          if (picked == null || !mounted) return;
                          final time =
                              '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          if (!current.contains(time)) {
                            setState(
                              () => values[key] = ([
                                ...current,
                                time,
                              ]..sort()).join(', '),
                            );
                          }
                        },
                ),
              ],
            ),
            if (field.errorText != null)
              Text(
                field.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Widget toggle(String key, String label, {String? subtitle}) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: values[key] == true,
        onChanged: saving
            ? null
            : (value) => setState(() => values[key] = value),
      );
  Widget date(String key, String label, {bool optional = false}) {
    final controller = _controllers.putIfAbsent(
      key,
      () => TextEditingController(text: str(values[key])),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        readOnly: true,
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: optional && controller.text.isNotEmpty
              ? IconButton(
                  onPressed: saving
                      ? null
                      : () => setState(() => controller.clear()),
                  icon: const Icon(Icons.clear),
                )
              : const Icon(Icons.calendar_today_outlined),
        ),
        onTap: saving
            ? null
            : () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate:
                      DateTime.tryParse(controller.text) ?? DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (picked != null && mounted) {
                  setState(() => controller.text = dateText(picked));
                }
              },
        validator: (_) =>
            !optional && controller.text.isEmpty ? 'Choose a date' : null,
      ),
    );
  }

  void update(VoidCallback change) => setState(change);
  Future<void> submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.save(this);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title)),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ...widget.fields(this),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: saving ? null : submit,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(saving ? 'Saving…' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}

class MedicineForms {
  static Future<void> medicine(
    BuildContext context,
    AppController app, {
    Json? medicine,
    bool archived = false,
  }) {
    final state = app.state!;
    final initial = <String, dynamic>{
      'name': '',
      'brandName': '',
      'strength': '',
      'unit': 'tablets',
      'lowStock': 10,
      'categoryId': '',
      'notes': '',
      'allowArchivedDuplicate': false,
      'initialQuantity': 0,
      'initialLocation': state.locations.firstOrNull?['id'] ?? '',
      ...?medicine,
    };
    final alert = stockAlertSettings(medicine ?? initial);
    initial.addAll({
      'alertEnabled': alert['enabled'],
      'alertScope': alert['scope'],
      'alertMetric': alert['metric'],
      'lowStock': alert['threshold'],
      'alertTime': alert['time'],
    });
    final rules = medicine?['doseRules'] as Map?;
    initial['strengthAmount'] = rules?['strengthAmount'] ?? '';
    initial['strengthUnit'] = rules?['strengthUnit'] ?? 'mg';
    for (final denominator in [1, 2, 4, 5, 8, 10]) {
      final fraction = records(
        rules?['fractions'],
      ).where((f) => f['denominator'] == denominator).firstOrNull;
      initial['fraction$denominator'] =
          fraction != null || (rules == null && denominator == 1);
      initial['maximum$denominator'] = fraction?['maxMultiple'] ?? '';
    }
    final unitLocked =
        medicine != null &&
        (state.stocks.any((b) => b['medicineId'] == medicine['id']) ||
            state.schedules.any((s) => s['medicineId'] == medicine['id']) ||
            state.history.any((m) => m['medicineId'] == medicine['id']));
    return openEditor(
      context,
      title: medicine == null ? 'Add medicine' : 'Edit medicine',
      initial: initial,
      fields: (e) => [
        e.field('brandName', 'Brand name'),
        e.field(
          'name',
          'Medicine / drug name',
          hint: 'Enter a brand name, medicine name, or both.',
        ),
        e.field(
          'strength',
          'Dosage / strength',
          required: true,
          hint: 'For example, 500 mg',
        ),
        if (!unitLocked)
          e.select('unit', 'Stock unit', {
            for (final unit in [
              'tablets',
              'capsules',
              'ml',
              'drops',
              'doses',
              'sachets',
              'units',
            ])
              unit: unit,
          })
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('Stock unit: ${medicine['unit']}'),
          ),
        e.select('categoryId', 'Category', {
          '': 'Uncategorized',
          for (final c in state.categories)
            str(c['id']): state.category(c['id']),
        }),
        const Text('Low-stock alerts'),
        e.toggle('alertEnabled', 'Enable alerts for this medicine'),
        e.select('alertScope', 'Stock to monitor', {
          'brand': 'This brand / medicine only',
          'drug': 'Drug and strength — all brands',
        }),
        e.select('alertMetric', 'Threshold type', {
          'days': 'Days of supply',
          'quantity': 'Stock quantity',
        }),
        e.field(
          'lowStock',
          e.values['alertMetric'] == 'days'
              ? 'Days remaining threshold'
              : 'Quantity threshold (stock units)',
          required: true,
          numeric: true,
        ),
        e.time('alertTime', 'Daily reminder time'),
        const Text(
          'Drug alerts combine active brands of the same drug, strength and stock unit. Expired stock is excluded. Reminders use your phone time zone and last synced data.',
        ),
        e.field('notes', 'Notes', lines: 3),
        if (medicine == null &&
            state.medicines.any((m) => m['archivedAt'] != null))
          e.toggle(
            'allowArchivedDuplicate',
            'Create separately from archived matches',
            subtitle:
                'Check the archive first. Enable only when you intend to keep a separate medicine.',
          ),
        if (medicine == null && state.locations.isNotEmpty) ...[
          const Text(
            'Initial stock',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          e.field('initialQuantity', 'Initial quantity', numeric: true),
          e.select('initialLocation', 'Location', {
            for (final l in state.locations) str(l['id']): str(l['name']),
          }),
          e.date('initialExpiry', 'Expiry date (optional)', optional: true),
        ],
        if (medicine == null && state.locations.isEmpty)
          const Text('Add a location under More before adding stock.'),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Pill fractions and strength'),
          subtitle: const Text('Optional dose calculation settings'),
          children: [
            e.field(
              'strengthAmount',
              'Strength per whole pill',
              numeric: true,
              hint: 'Leave blank to infer from the strength label.',
            ),
            e.field('strengthUnit', 'Strength unit', hint: 'For example, mg'),
            for (final d in [1, 2, 4, 5, 8, 10]) ...[
              e.toggle('fraction$d', d == 1 ? 'Whole pill' : '1/$d pill'),
              if (e.values['fraction$d'] == true)
                e.field(
                  'maximum$d',
                  'Maximum multiple (optional)',
                  numeric: true,
                  min: 1,
                  hint: 'Leave blank for no maximum.',
                ),
            ],
          ],
        ),
      ],
      save: (e) async {
        final fractions = [
          for (final d in [1, 2, 4, 5, 8, 10])
            if (e.values['fraction$d'] == true)
              {
                'denominator': d,
                'maxMultiple': e.value('maximum$d').isEmpty
                    ? null
                    : int.parse(e.value('maximum$d')),
              },
        ];
        final body = <String, dynamic>{
          for (final key in ['name', 'brandName', 'strength', 'notes'])
            key: e.value(key),
          'unit': unitLocked ? medicine['unit'] : e.values['unit'],
          'lowStock': e.numeric('lowStock'),
          'lowStockAlert': {
            'enabled': e.values['alertEnabled'] == true,
            'scope': e.values['alertScope'],
            'metric': e.values['alertMetric'],
            'threshold': e.numeric('lowStock'),
            'time': e.value('alertTime'),
          },
          'categoryId': e.values['categoryId'] == ''
              ? null
              : e.values['categoryId'],
          'archived': archived,
          'allowArchivedDuplicate': e.values['allowArchivedDuplicate'] == true,
          if (medicine != null) 'id': medicine['id'],
        };
        if (rules != null ||
            e.value('strengthAmount').isNotEmpty ||
            fractions.length != 1 ||
            (fractions.isNotEmpty && fractions[0]['denominator'] != 1) ||
            (fractions.isNotEmpty && fractions[0]['maxMultiple'] != null)) {
          body['doseRules'] = {
            'fractions': fractions,
            'strengthAmount': e.value('strengthAmount').isEmpty
                ? null
                : e.numeric('strengthAmount'),
            'strengthUnit': e.value('strengthUnit'),
          };
        }
        if (medicine == null &&
            state.locations.isNotEmpty &&
            (double.tryParse(e.value('initialQuantity')) ?? 0) > 0) {
          body['initialStock'] = {
            'quantity': e.numeric('initialQuantity'),
            'locationId': e.values['initialLocation'],
            'expiry': e.value('initialExpiry'),
          };
        }
        await app.mutate(
          medicine == null ? 'medicines' : 'medicine-edit',
          body,
        );
      },
    );
  }

  static Future<void> stock(
    BuildContext context,
    AppController app,
    Json medicine, {
    Json? batch,
  }) {
    final state = app.state!;
    return openEditor(
      context,
      title: batch == null ? 'Update stock' : 'Edit stock batch',
      initial: {
        'mode': 'add',
        'quantity': '',
        'locationId':
            batch?['locationId'] ?? state.locations.firstOrNull?['id'] ?? '',
        'expiry': batch?['expiry'] ?? '',
        'reason': '',
      },
      fields: (e) => [
        Text(
          medicineName(medicine),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 20),
        e.select('mode', 'Stock change', {
          'add': 'Add stock',
          'remove': 'Reduce stock',
          'set': 'Set exact count',
        }),
        if (batch == null)
          e.select('locationId', 'Location', {
            '': 'Choose location',
            for (final l in state.locations) str(l['id']): str(l['name']),
          })
        else
          Text(
            '${state.location(batch['locationId'])} · ${quantity(batch['quantity'])} ${medicine['unit']} recorded',
          ),
        const SizedBox(height: 16),
        e.field(
          'quantity',
          'Quantity (${medicine['unit']})',
          required: true,
          numeric: true,
        ),
        e.date('expiry', 'Expiry date (optional)', optional: true),
        e.field('reason', 'Reason (optional)'),
      ],
      save: (e) => app.mutate(batch == null ? 'stock' : 'stock-edit', {
        'medicineId': medicine['id'],
        'locationId': e.values['locationId'],
        'mode': e.values['mode'],
        'quantity': e.numeric('quantity'),
        'expiry': e.value('expiry'),
        'reason': e.value('reason'),
        if (batch != null) 'id': batch['id'],
        if (batch != null) 'expectedQuantity': batch['quantity'],
      }),
    );
  }

  static Future<void> schedule(
    BuildContext context,
    AppController app, {
    Json? schedule,
  }) {
    final state = app.state!;
    final calculation = schedule?['doseCalculation'] as Map?;
    return openEditor(
      context,
      title: schedule == null ? 'Add schedule' : 'Edit schedule',
      initial: {
        'medicineId': state.activeMedicines.firstOrNull?['id'] ?? '',
        'locationId': '',
        'zone': app.reminders.zone,
        'timesText': '08:00, 20:00',
        'days': [0, 1, 2, 3, 4, 5, 6],
        'start': dateText(DateTime.now()),
        'end': '',
        'instructions': '',
        'doseMode': 'quantity',
        'doseValue': 1,
        'medicineSelection':
            schedule == null || calculation?['drugNameOnly'] == true
            ? 'drug'
            : 'brand',
        ...?schedule,
        if (schedule != null)
          'timesText': (schedule['times'] as List).join(', '),
        if (calculation != null) 'doseMode': calculation['mode'],
        if (calculation != null) 'doseValue': calculation['value'],
      },
      fields: (e) => [
        e.select('medicineSelection', 'Medicine selection', {
          'drug': 'Drug name and pill strength — any brand',
          'brand': 'Specific brand / medicine',
        }),
        e.select(
          'medicineId',
          'Medicine',
          scheduleMedicineOptions(
            state,
            anyBrand: e.values['medicineSelection'] == 'drug',
            referenceId: str(schedule?['medicineId']),
          ),
        ),
        e.select('doseMode', 'Dose entry', {
          'quantity': 'Stock quantity',
          'strength': 'Prescribed strength',
        }),
        e.field(
          'doseValue',
          'Dose per time',
          required: true,
          numeric: true,
          min: 0.001,
        ),
        e.select('locationId', 'Take stock from', {
          '': 'Any location',
          for (final l in state.locations) str(l['id']): str(l['name']),
        }),
        e.times('timesText'),
        const Text('Repeat on'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (var day = 0; day < 7; day++)
              FilterChip(
                label: Text(
                  ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][day],
                ),
                selected: (e.values['days'] as List).contains(day),
                onSelected: e.saving
                    ? null
                    : (selected) => e.update(() {
                        final days = List<int>.from(e.values['days'] as List);
                        selected ? days.add(day) : days.remove(day);
                        e.values['days'] = days;
                      }),
              ),
          ],
        ),
        const SizedBox(height: 16),
        e.date('start', 'Start date'),
        e.date('end', 'End date (optional)', optional: true),
        e.field(
          'zone',
          'Time zone',
          required: true,
          hint:
              'For example, Asia/Colombo. Times follow this zone when traveling.',
        ),
        e.field('instructions', 'Instructions (optional)', lines: 3),
      ],
      save: (e) =>
          app.mutate(schedule == null ? 'schedules' : 'schedule-edit', {
            if (schedule != null) 'id': schedule['id'],
            'medicineId': e.values['medicineId'],
            'locationId': e.values['locationId'] == ''
                ? null
                : e.values['locationId'],
            'drugNameOnly': e.values['medicineSelection'] == 'drug',
            'doseMode': e.values['doseMode'],
            'doseValue': e.numeric('doseValue'),
            'times': e
                .value('timesText')
                .split(',')
                .map((t) => t.trim())
                .toList(),
            'days': e.values['days'],
            'start': e.value('start'),
            'end': e.value('end'),
            'zone': e.value('zone'),
            'instructions': e.value('instructions'),
          }),
    );
  }

  static Future<void> category(
    BuildContext context,
    AppController app, {
    Json? category,
  }) => openEditor(
    context,
    title: category == null ? 'Add category' : 'Edit category',
    initial: {
      'name': category?['name'] ?? '',
      'parentId': category?['parentId'] ?? '',
    },
    fields: (e) => [
      e.field('name', 'Name', required: true),
      e.select('parentId', 'Parent category', {
        '': 'Top level',
        for (final c in app.state!.categories.where(
          (c) => c['id'] != category?['id'],
        ))
          str(c['id']): app.state!.category(c['id']),
      }),
    ],
    save: (e) => app.mutate('categories', {
      if (category != null) 'id': category['id'],
      'name': e.value('name'),
      'parentId': e.values['parentId'] == '' ? null : e.values['parentId'],
    }),
  );
  static Future<void> location(BuildContext context, AppController app) =>
      openEditor(
        context,
        title: 'Add location',
        initial: {},
        fields: (e) => [
          e.field('name', 'Location name', required: true),
          e.field('description', 'Description', lines: 3),
        ],
        save: (e) => app.mutate('locations', {
          'name': e.value('name'),
          'description': e.value('description'),
        }),
      );
}
