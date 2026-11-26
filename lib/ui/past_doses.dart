import 'package:flutter/material.dart';
import '../data/controller.dart';
import '../data/models.dart';

// Adjust the visible checkbox and symbol sizes here (logical pixels).
const double pastDoseCheckboxSize = 28;
const double pastDoseCheckboxSymbolSize = 20;
const double pastDoseCheckboxColumnWidth = 60;

class PastDosesScreen extends StatefulWidget {
  const PastDosesScreen({super.key, required this.app});
  final AppController app;
  @override
  State<PastDosesScreen> createState() => _PastDosesScreenState();
}

class _PastDosesScreenState extends State<PastDosesScreen> {
  String filter = 'unrecorded', size = '25', sort = 'desc';
  DateTime date = DateTime.now();
  int page = 1, pages = 1, total = 0, generation = 0;
  bool loading = true, saving = false;
  String? error;
  List<Json> rows = [];
  final Map<String, Json> changes = {};

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final version = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.app.api.post('past-doses', {
        'filter': filter,
        'sort': sort,
        'date': dateText(date),
        'page': page,
        'pageSize': size == 'all' ? 'all' : int.parse(size),
      });
      if (!mounted || version != generation) return;
      setState(() {
        rows = records(result['rows']);
        total = result['total'] as int;
        page = result['page'] as int;
        pages = result['pages'] as int;
      });
    } catch (e) {
      if (mounted && version == generation) {
        setState(() => error = e.toString());
      }
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  void cycle(Json row) {
    final key = str(row['id']);
    final current = changes[key]?['status'] ?? row['status'];
    final next = current == 'pending'
        ? 'taken'
        : current == 'taken'
        ? 'skipped'
        : 'pending';
    setState(() {
      if (next == row['status']) {
        changes.remove(key);
      } else {
        changes[key] = {
          'scheduleId': row['scheduleId'],
          'date': row['date'],
          'time': row['time'],
          'status': next,
          'expectedStatus': row['status'],
        };
      }
    });
  }

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.app.mutate('past-doses-save', {
        'changes': changes.values.toList(),
      });
      if (!mounted) return;
      setState(changes.clear);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Past doses saved.')));
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<bool> leave() async {
    if (saving) return false;
    if (changes.isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Discard unsaved dose changes?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep editing'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: changes.isEmpty && !saving,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop && await leave() && mounted) {
        setState(changes.clear);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Past doses')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  value: filter,
                  decoration: const InputDecoration(labelText: 'Filter'),
                  items: const [
                    DropdownMenuItem(
                      value: 'unrecorded',
                      child: Text('All unrecorded'),
                    ),
                    DropdownMenuItem(value: 'date', child: Text('By date')),
                    DropdownMenuItem(value: 'all', child: Text('All')),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          setState(() {
                            filter = value!;
                            page = 1;
                          });
                          load();
                        },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: sort,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Sort by date / time',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'desc',
                      child: Text('Descending (newest first)'),
                    ),
                    DropdownMenuItem(
                      value: 'asc',
                      child: Text('Ascending (oldest first)'),
                    ),
                  ],
                  onChanged: saving
                      ? null
                      : (value) {
                          setState(() {
                            sort = value!;
                            page = 1;
                          });
                          load();
                        },
                ),
                if (filter == 'date')
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: Text(dateText(date)),
                      onPressed: saving
                          ? null
                          : () async {
                              final selected = await showDatePicker(
                                context: context,
                                initialDate: date,
                                firstDate: DateTime(1900),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 1),
                                ),
                              );
                              if (selected != null && mounted) {
                                setState(() {
                                  date = selected;
                                  page = 1;
                                });
                                load();
                              }
                            },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    children: [
                      for (final entry in const [
                        ('taken', 'Taken'),
                        ('skipped', 'Not taken'),
                        ('pending', 'Not recorded'),
                      ])
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Semantics(
                              label: entry.$2,
                              checked: entry.$1 == 'taken',
                              mixed: entry.$1 == 'pending',
                              enabled: false,
                              child: ExcludeSemantics(
                                child: IconButton(
                                  onPressed: null,
                                  padding: const EdgeInsets.all(3),
                                  constraints: const BoxConstraints(
                                    minWidth: 24,
                                    minHeight: 24,
                                  ),
                                  style: IconButton.styleFrom(
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  icon: checkboxMark(entry.$1, disabled: true),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              entry.$2,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const Text(
                  'Tap a checkbox to cycle. Times use each schedule’s time zone.',
                ),
                const Text(
                  'History follows saved schedule dates and weekdays, including paused schedules. Taken doses use current eligible stock; corrections restore the original deduction.',
                  style: TextStyle(fontSize: 12),
                ),
                if (error != null)
                  Column(
                    children: [
                      Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      TextButton(
                        onPressed: loading || saving ? null : load,
                        child: const Text('Reload'),
                      ),
                    ],
                  ),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No past doses match this filter.'),
                  )
                else
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(2),
                      2: FixedColumnWidth(pastDoseCheckboxColumnWidth),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    children: [
                      const TableRow(
                        children: [
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Date / time',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(8),
                            child: Text(
                              'Medicine',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          Center(
                            child: Text(
                              'Taken',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      for (final row in rows) doseRow(row),
                    ],
                  ),
              ],
            ),
          ),
          // Outside the scrolling list: save and pagination remain visible.
          Material(
            elevation: 8,
            color: Theme.of(context).colorScheme.surface,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      children: [
                        const Text('Rows'),
                        DropdownButton<String>(
                          value: size,
                          items: ['10', '25', '50', '100', 'all']
                              .map(
                                (n) => DropdownMenuItem(
                                  value: n,
                                  child: Text(n == 'all' ? 'All' : n),
                                ),
                              )
                              .toList(),
                          onChanged: saving
                              ? null
                              : (value) {
                                  setState(() {
                                    size = value!;
                                    page = 1;
                                  });
                                  load();
                                },
                        ),
                        IconButton(
                          tooltip: 'Previous page',
                          onPressed: saving || loading || page <= 1
                              ? null
                              : () {
                                  page--;
                                  load();
                                },
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Text('$page / $pages · $total doses'),
                        IconButton(
                          tooltip: 'Next page',
                          onPressed: saving || loading || page >= pages
                              ? null
                              : () {
                                  page++;
                                  load();
                                },
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed:
                            saving ||
                                loading ||
                                changes.isEmpty ||
                                error != null
                            ? null
                            : save,
                        child: Text(
                          saving
                              ? 'Saving…'
                              : 'Save changes${changes.isEmpty ? '' : ' (${changes.length})'}',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  TableRow doseRow(Json row) {
    final medicine = widget.app.state?.medicine(row['medicineId']);
    final status = changes[str(row['id'])]?['status'] ?? row['status'];
    final label = status == 'pending'
        ? 'Not recorded'
        : status == 'taken'
        ? 'Taken'
        : 'Not taken';
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${row['date']}\n${row['time']}\n${row['zone']}',
            style: const TextStyle(fontSize: 12),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '${medicineName(medicine)}\n${medicine?['strength'] ?? ''} · ${quantity(row['amount'])} ${medicine?['unit'] ?? ''}',
          ),
        ),
        Semantics(
          label:
              '${medicineName(medicine)}, ${row['date']} ${row['time']}: $label',
          checked: status == 'taken',
          mixed: status == 'pending',
          enabled: !saving,
          onTap: saving ? null : () => cycle(row),
          child: ExcludeSemantics(
            child: Tooltip(
              message: label,
              child: IconButton(
                onPressed: saving ? null : () => cycle(row),
                icon: checkboxMark(str(status)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget checkboxMark(String status, {bool disabled = false}) {
    final color = disabled
        ? Theme.of(context).disabledColor
        : Theme.of(context).colorScheme.primary;
    return Container(
      width: disabled ? 18 : pastDoseCheckboxSize,
      height: disabled ? 18 : pastDoseCheckboxSize,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(4),
        color: status == 'taken' ? color : null,
      ),
      alignment: Alignment.center,
      child: Text(
        status == 'pending'
            ? '?'
            : status == 'taken'
            ? '✓'
            : '',
        style: TextStyle(
          fontSize: disabled ? 12 : pastDoseCheckboxSymbolSize,
          fontWeight: FontWeight.bold,
          color: status == 'taken'
              ? Theme.of(context).colorScheme.surface
              : color,
        ),
      ),
    );
  }
}
