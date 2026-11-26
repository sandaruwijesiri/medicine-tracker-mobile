import 'past_doses.dart';
import 'choice_field.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../data/controller.dart';
import '../data/models.dart';
import 'forms.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.app});
  final AppController app;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int tab = 0;
  String search = '', category = '', locationFilter = '';
  bool sortAscending = true;
  bool onlyLow = false, onlyExpired = false;
  AppController get app => widget.app;
  CabinetState get data => app.state!;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    app.reminders.onTap = notification;
    final launch = app.reminders.launchPayload;
    if (launch != null) {
      app.reminders.launchPayload = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => notification(launch));
    }
  }

  void notification(Json payload) {
    if (mounted) {
      setState(() => tab = payload['type'] == 'low_stock' ? 1 : 0);
      unawaited(app.sync());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(app.sync(forceReminders: true));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    app.reminders.onTap = null;
    super.dispose();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> perform(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      message(e.toString());
    }
  }

  Future<bool> confirm(
    String title,
    String body, {
    String action = 'Confirm',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Widget empty(String title, String detail) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
    child: Column(
      children: [
        Icon(
          Icons.medication_outlined,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(detail, textAlign: TextAlign.center),
      ],
    ),
  );
  Widget heading(String title, String subtitle, {Widget? trailing}) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(subtitle, style: const TextStyle(color: Color(0xff62736e))),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    ),
  );
  Widget badge(String text, {bool warning = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: warning ? const Color(0xffffefcf) : const Color(0xffe8f4ee),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: warning ? const Color(0xff855b10) : const Color(0xff176b60),
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Future<void> page(String title, List<Widget> Function() contents) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ListenableBuilder(
            listenable: app,
            builder: (ctx, _) => Scaffold(
              appBar: AppBar(title: Text(title)),
              body: app.state == null
                  ? const Center(child: Text('Sign in to continue.'))
                  : RefreshIndicator(
                      onRefresh: app.sync,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(20),
                        children: contents(),
                      ),
                    ),
            ),
          ),
        ),
      );
  Future<void> recordDose(Json dose, String status) async {
    String? brand;
    final medicine = data.medicine(dose['medicineId']);
    if (status == 'taken' &&
        (dose['doseCalculation'] as Map?)?['drugNameOnly'] == true) {
      final options = data.activeMedicines
          .where(
            (m) =>
                str(m['name']).trim().toLowerCase() ==
                    str(medicine?['name']).trim().toLowerCase() &&
                data.available(str(m['id'])) > 0,
          )
          .toList();
      brand = await showDialog<String>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Which brand did you take?'),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text(
                'Continue without specifying\nAutomatic stock allocation',
              ),
            ),
            for (final m in options)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, str(m['id'])),
                child: Text(
                  '${medicineName(m)} · ${m['strength']}\n${quantity(data.available(str(m['id'])))} ${m['unit']} available',
                ),
              ),
          ],
        ),
      );
      if (brand == null) return;
    }
    if (status == 'skipped' &&
        !await confirm(
          'Skip this dose?',
          '${medicineName(medicine)} · ${medicine?['strength']}\n${dose['date']} at ${dose['time']}\n\nThis records the dose as skipped without changing stock.',
          action: 'Confirm skip',
        )) {
      return;
    }
    await perform(() async {
      await app.mutate('dose', {
        'scheduleId': dose['scheduleId'],
        'date': dose['date'],
        'time': dose['time'],
        'status': status,
        if (brand != null && brand.isNotEmpty) 'takenMedicineId': brand,
      });
      final recorded = data
          .recentDoses()
          .where(
            (d) =>
                d['scheduleId'] == dose['scheduleId'] &&
                d['date'] == dose['date'] &&
                d['time'] == dose['time'],
          )
          .firstOrNull;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            status == 'taken'
                ? 'Dose taken. Stock updated.'
                : 'Dose skipped. Stock unchanged.',
          ),
          action: recorded == null
              ? null
              : SnackBarAction(
                  label: 'Undo',
                  onPressed: () => undoDose(recorded),
                ),
        ),
      );
    });
  }

  Future<void> undoDose(Json dose) => perform(() async {
    await app.mutate('dose-undo', {'id': dose['id']});
    message(
      dose['status'] == 'taken'
          ? 'Dose undone. Stock restored.'
          : 'Skip undone. Dose is pending again.',
    );
  });
  List<Widget> recentDoses() {
    final doses = data.recentDoses();
    if (doses.isEmpty) return [];
    return [
      const SizedBox(height: 24),
      heading(
        'Recently recorded doses',
        'Undo taken or skipped doses recorded in the last 24 hours.',
      ),
      for (final d in doses)
        Card(
          child: ListTile(
            title: Text(
              medicineName(
                data.medicine(
                  CabinetState.find(
                    data.schedules,
                    d['scheduleId'],
                  )?['medicineId'],
                ),
              ),
            ),
            subtitle: Text(
              '${d['date']} · ${d['time']} · ${d['status'] == 'taken' ? 'Taken' : 'Skipped'}',
            ),
            trailing: TextButton(
              onPressed: app.busy || app.offline || app.syncing
                  ? null
                  : () => undoDose(d),
              child: const Text('Undo'),
            ),
          ),
        ),
    ];
  }

  Widget doseCard(Json dose) {
    final m = data.medicine(dose['medicineId']);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  str(dose['time']),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 12),
                if (dose['overdue'] == true)
                  badge(str(dose['date']), warning: true),
                const Spacer(),
                const Icon(Icons.medication_outlined),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              (dose['doseCalculation'] as Map?)?['drugNameOnly'] == true
                  ? str(m?['name'])
                  : medicineName(m),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              '${m?['strength']} · ${quantity(dose['amount'])} ${m?['unit']}',
            ),
            Text(
              '${data.location(dose['locationId'])} · ${dose['zone']}',
              style: const TextStyle(fontSize: 12),
            ),
            if (str(dose['instructions']).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(str(dose['instructions'])),
              ),
            const SizedBox(height: 14),
            if (dose['status'] != 'pending')
              badge(dose['status'] == 'taken' ? 'Taken' : 'Skipped')
            else if (dose['due'] == true)
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: app.busy || app.offline || app.syncing
                          ? null
                          : () => recordDose(dose, 'taken'),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Confirm taken'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: app.busy || app.offline || app.syncing
                        ? null
                        : () => recordDose(dose, 'skipped'),
                    child: const Text('Skip'),
                  ),
                ],
              )
            else
              badge('Upcoming'),
          ],
        ),
      ),
    );
  }

  List<Widget> today() {
    final due = data.occurrences
        .where((d) => d['due'] == true && d['status'] == 'pending')
        .length;
    final low = records(
      app.insights['medicines'],
    ).where((m) => m['lowStock'] == true).length;
    final expired = data.stocks.where(expiredBatch).length;
    return [
      heading('Your daily care', 'A clear view of what’s next.'),
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xff176b60),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$due',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 44,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Text(
                    'doses waiting for you',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
            const Icon(Icons.spa_outlined, size: 64, color: Color(0xffbedbd1)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      if (low > 0 || expired > 0)
        Card(
          child: ListTile(
            leading: const Icon(Icons.inventory_2_outlined),
            title: Text('$low low-stock medicines · $expired expired batches'),
            subtitle: const Text('Review your cabinet before the next dose'),
            onTap: () => setState(() => tab = 1),
          ),
        ),
      if (!app.doseReminders && !app.stockReminders)
        Card(
          child: ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Set up reminders'),
            subtitle: const Text('Get dose and stock alerts on this phone'),
            trailing: const Icon(Icons.chevron_right),
            onTap: settings,
          ),
        ),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PastDosesScreen(app: app)),
        ),
        icon: const Icon(Icons.history),
        label: const Text('View all past doses'),
      ),
      Text('Dose timeline', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (data.occurrences.isEmpty)
        empty(
          'No doses scheduled',
          'Add a medicine, then create a schedule to see your daily doses here.',
        )
      else
        ...data.todayTimeline().map(doseCard),
      ...recentDoses(),
    ];
  }

  bool expiredBatch(Json b) =>
      number(b['quantity']) > 0 &&
      str(b['expiry']).isNotEmpty &&
      str(b['expiry']).compareTo(dateText(DateTime.now())) < 0;
  bool inCategory(Json m) {
    if (category.isEmpty) return true;
    var id = m['categoryId'];
    final seen = <String>{};
    while (id != null && seen.add(str(id))) {
      if (id == category) return true;
      id = CabinetState.find(data.categories, id)?['parentId'];
    }
    return false;
  }

  Widget medicineCard(Json m) {
    final available = data.available(str(m['id']));
    final supply = app.supply(str(m['id']));
    final low = supply?['lowStock'] == true;
    final expired = data.stocks.any(
      (b) => b['medicineId'] == m['id'] && expiredBatch(b),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => medicineDetails(m),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(child: Icon(Icons.medication_outlined)),
                  const Spacer(),
                  badge(
                    available == 0
                        ? 'Out of stock'
                        : low
                        ? 'Low stock'
                        : 'In stock',
                    warning: available == 0 || low,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                medicineName(m),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '${m['strength']} · ${data.category(m['categoryId'])}',
                style: const TextStyle(color: Color(0xff62736e)),
              ),
              const SizedBox(height: 18),
              Text(
                '${quantity(available)} ${m['unit']} available',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                supply == null
                    ? 'Supply estimate unavailable'
                    : supply['daysOfSupply'] == null
                    ? 'No shortage forecast in the next year'
                    : '${quantity(supply['daysOfSupply'])} days of supply',
              ),
              if (expired)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Expired stock needs attention',
                    style: TextStyle(color: Color(0xff995923)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> cabinet() {
    final medicines =
        data.activeMedicines
            .where(
              (m) =>
                  '${medicineName(m)} ${m['strength']}'.toLowerCase().contains(
                    search.toLowerCase(),
                  ) &&
                  inCategory(m) &&
                  (locationFilter.isEmpty ||
                      data.stocks.any(
                        (b) =>
                            b['medicineId'] == m['id'] &&
                            b['locationId'] == locationFilter,
                      )) &&
                  (!onlyLow || app.supply(str(m['id']))?['lowStock'] == true) &&
                  (!onlyExpired ||
                      data.stocks.any(
                        (b) => b['medicineId'] == m['id'] && expiredBatch(b),
                      )),
            )
            .toList()
          ..sort(
            (a, b) => sortAscending
                ? medicineName(
                    a,
                  ).toLowerCase().compareTo(medicineName(b).toLowerCase())
                : medicineName(
                    b,
                  ).toLowerCase().compareTo(medicineName(a).toLowerCase()),
          );
    return [
      heading(
        'Your cabinet',
        '${data.activeMedicines.length} medicines, organized for you.',
        trailing: IconButton.filled(
          onPressed: app.offline || app.busy
              ? null
              : () => MedicineForms.medicine(context, app),
          icon: const Icon(Icons.add),
          tooltip: 'Add medicine',
        ),
      ),
      TextField(
        decoration: const InputDecoration(
          hintText: 'Search medicines or brands',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      const SizedBox(height: 12),
      ChoiceField(
        label: 'Category',
        value: category,
        options: {
          '': 'All categories',
          for (final c in data.categories) str(c['id']): data.category(c['id']),
        },
        onChanged: (v) => setState(() => category = v),
      ),
      const SizedBox(height: 12),
      ChoiceField(
        label: 'Stock location',
        value: locationFilter,
        options: {
          '': 'All locations',
          for (final l in data.locations) str(l['id']): str(l['name']),
        },
        onChanged: (v) => setState(() => locationFilter = v),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: () => setState(() => sortAscending = !sortAscending),
          icon: Icon(
            sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
            size: 18,
          ),
          label: Text(sortAscending ? 'Name A–Z' : 'Name Z–A'),
        ),
      ),
      Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('Low stock'),
            selected: onlyLow,
            onSelected: (v) => setState(() => onlyLow = v),
          ),
          FilterChip(
            label: const Text('Expired stock'),
            selected: onlyExpired,
            onSelected: (v) => setState(() => onlyExpired = v),
          ),
        ],
      ),
      const SizedBox(height: 14),
      if (medicines.isEmpty)
        empty(
          'No medicines here',
          'Add a medicine or change your search and filters.',
        )
      else
        ...medicines.map(medicineCard),
    ];
  }

  Future<void> medicineDetails(Json initial) => page(medicineName(initial), () {
    final m = data.medicine(initial['id']);
    if (m == null) {
      return [
        empty(
          'Medicine removed',
          'This medicine is no longer in your cabinet.',
        ),
      ];
    }
    final batches =
        data.stocks.where((b) => b['medicineId'] == m['id']).toList()..sort(
          (a, b) => (str(a['expiry']).isEmpty ? '9999' : str(a['expiry']))
              .compareTo(str(b['expiry']).isEmpty ? '9999' : str(b['expiry'])),
        );
    return [
      heading(
        medicineName(m),
        '${m['strength']} · ${data.category(m['categoryId'])}',
      ),
      Text(
        '${quantity(data.available(str(m['id'])))} ${m['unit']} available',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      if (str(m['notes']).isNotEmpty) Text(str(m['notes'])),
      const SizedBox(height: 16),
      Wrap(
        spacing: 8,
        children: [
          FilledButton.icon(
            onPressed: app.busy || app.offline
                ? null
                : () => MedicineForms.stock(context, app, m),
            icon: const Icon(Icons.add),
            label: const Text('Update stock'),
          ),
          OutlinedButton(
            onPressed: app.busy || app.offline
                ? null
                : () => MedicineForms.medicine(
                    context,
                    app,
                    medicine: m,
                    archived: m['archivedAt'] != null,
                  ),
            child: const Text('Edit medicine'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      Text('Stock batches', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (batches.isEmpty) const Text('No stock added yet.'),
      for (final b in batches)
        Card(
          child: ListTile(
            title: Text(
              '${quantity(b['quantity'])} ${m['unit']} · ${data.location(b['locationId'])}',
            ),
            subtitle: Text(
              str(b['expiry']).isEmpty
                  ? 'Expiry not recorded'
                  : '${expiredBatch(b) ? 'Expired' : 'Expires'} ${b['expiry']}',
            ),
            trailing: PopupMenuButton<String>(
              enabled: !app.busy && !app.offline,
              onSelected: (v) async {
                if (v == 'edit') {
                  await MedicineForms.stock(context, app, m, batch: b);
                } else if (await confirm(
                  'Delete stock batch?',
                  'Remove ${quantity(b['quantity'])} ${m['unit']} at ${data.location(b['locationId'])}? This is recorded in stock history.',
                  action: 'Delete batch',
                )) {
                  await perform(
                    () => app.mutate('stock-delete', {
                      'id': b['id'],
                      'expectedQuantity': b['quantity'],
                    }),
                  );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit batch')),
                PopupMenuItem(value: 'delete', child: Text('Delete batch')),
              ],
            ),
          ),
        ),
      const SizedBox(height: 24),
      OutlinedButton.icon(
        onPressed: app.busy || app.offline
            ? null
            : () async {
                final archived = m['archivedAt'] == null;
                if (await confirm(
                  archived ? 'Archive medicine?' : 'Restore medicine?',
                  archived
                      ? 'Stock is preserved. Specific-brand schedules pause. Any-brand schedules continue while eligible active brands remain.'
                      : 'The medicine returns to your cabinet. Previously paused schedules remain paused.',
                )) {
                  await perform(
                    () => app.mutate('medicine-archive', {
                      'id': m['id'],
                      'archived': archived,
                    }),
                  );
                }
              },
        icon: const Icon(Icons.archive_outlined),
        label: Text(
          m['archivedAt'] == null ? 'Archive medicine' : 'Restore medicine',
        ),
      ),
      TextButton(
        onPressed: app.busy || app.offline
            ? null
            : () async {
                if (await confirm(
                  'Permanently delete medicine?',
                  'This deletes stock, schedules, doses and stock movements. Prescription files remain unattached. This cannot be undone.',
                  action: 'Delete permanently',
                )) {
                  await perform(
                    () => app.mutate('medicine-delete', {'id': m['id']}),
                  );
                }
              },
        child: Text(
          'Delete permanently',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    ];
  });
  List<Widget> schedules() => [
    heading(
      'Your schedules',
      'A routine that works for you.',
      trailing: IconButton.filled(
        onPressed: app.busy || app.offline || data.activeMedicines.isEmpty
            ? null
            : () => MedicineForms.schedule(context, app),
        icon: const Icon(Icons.add),
        tooltip: 'Add schedule',
      ),
    ),
    if (data.schedules.isEmpty)
      empty(
        'Make room for a routine',
        'Add a medicine, then choose its dose times and weekdays.',
      ),
    for (final s in data.schedules)
      Card(
        margin: const EdgeInsets.only(bottom: 14),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      scheduleMedicineName(data.medicine(s['medicineId']), s),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  badge(
                    s['active'] == true ? 'Active' : 'Paused',
                    warning: s['active'] != true,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${quantity(s['amount'])} ${data.medicine(s['medicineId'])?['unit']} · ${data.location(s['locationId'])}',
              ),
              if (s['doseCalculation'] != null)
                Text(
                  str(s['doseCalculation']['explanation']),
                  style: const TextStyle(fontSize: 12),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final t in s['times'] as List) badge(str(t))],
              ),
              const SizedBox(height: 12),
              Text(
                '${(s['days'] as List).map((d) => ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'][d as int]).join(', ')} · ${s['zone']}',
              ),
              Text(
                '${s['start']} → ${str(s['end']).isEmpty ? 'Ongoing' : s['end']}',
              ),
              if (str(s['instructions']).isNotEmpty)
                Text(str(s['instructions'])),
              ...records(app.insights['schedules'])
                  .where((f) => f['scheduleId'] == s['id'])
                  .map(
                    (f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        str(f['shortage']).isNotEmpty
                            ? 'Estimated shortage: ${f['shortage']}'
                            : '${f['doses']} doses covered${f['horizon'] == true ? ' in the next year' : ''}',
                      ),
                    ),
                  ),
              Row(
                children: [
                  TextButton(
                    onPressed: app.busy || app.offline
                        ? null
                        : () =>
                              MedicineForms.schedule(context, app, schedule: s),
                    child: const Text('Edit schedule'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: app.busy || app.offline
                        ? null
                        : () => perform(
                            () => app.mutate('schedule-status', {
                              'id': s['id'],
                              'active': s['active'] != true,
                            }),
                          ),
                    child: Text(s['active'] == true ? 'Pause' : 'Resume'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
  ];
  Future<void> uploadPrescription() async {
    try {
      final chosen = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
        withData: true,
      );
      if (chosen == null || !mounted) return;
      final file = chosen.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
        message('Select a PDF, PNG or JPEG smaller than 5 MB.');
        return;
      }
      final ext = file.extension?.toLowerCase();
      final mime = ext == 'pdf'
          ? 'application/pdf'
          : ext == 'png'
          ? 'image/png'
          : 'image/jpeg';
      await openEditor(
        context,
        title: 'Add prescription',
        initial: {
          'name': file.name,
          'date': dateText(DateTime.now()),
          'medicineId': '',
          'doctor': '',
        },
        fields: (e) => [
          e.field('name', 'File name', required: true),
          e.date('date', 'Prescription date'),
          e.field('doctor', 'Doctor (optional)'),
          e.select('medicineId', 'Medicine (optional)', {
            '': 'No medicine attached',
            for (final m in data.medicines) str(m['id']): medicineName(m),
          }),
        ],
        save: (e) => app.mutate('prescriptions', {
          'name': e.value('name'),
          'date': e.value('date'),
          'doctor': e.value('doctor'),
          'medicineId': e.values['medicineId'] == ''
              ? null
              : e.values['medicineId'],
          'mime': mime,
          'base64': base64Encode(bytes),
        }),
      );
    } catch (e) {
      message(e.toString());
    }
  }

  Future<void> openPrescription(Json file) => perform(() async {
    final bytes = await app.api.file(str(file['id']));
    final dir = await getTemporaryDirectory();
    final ext = file['mime'] == 'application/pdf'
        ? 'pdf'
        : file['mime'] == 'image/png'
        ? 'png'
        : 'jpg';
    final id = str(file['id']).replaceAll(RegExp('[^a-zA-Z0-9_-]'), '');
    final folder = Directory('${dir.path}/medicine-prescriptions');
    await folder.create(recursive: true);
    final target = File('${folder.path}/$id.$ext');
    await target.writeAsBytes(bytes, flush: true);
    final result = await OpenFilex.open(target.path, type: str(file['mime']));
    if (result.type != ResultType.done) message(result.message);
  });
  Future<void> prescriptions() => page(
    'Prescriptions',
    () => [
      heading(
        'Your prescriptions',
        'Keep the details close at hand.',
        trailing: IconButton.filled(
          onPressed: app.busy || app.offline ? null : uploadPrescription,
          icon: const Icon(Icons.upload_file),
        ),
      ),
      if (data.prescriptions.isEmpty)
        empty(
          'No prescriptions yet',
          'Upload a PDF or a photo of your prescription.',
        ),
      for (final f in data.prescriptions)
        Card(
          child: ListTile(
            leading: const Icon(Icons.description_outlined),
            title: Text(str(f['name'])),
            subtitle: Text(
              '${f['date']} · ${f['doctor']}\n${f['medicineId'] == null ? 'Unattached' : medicineName(data.medicine(f['medicineId']))}',
            ),
            isThreeLine: true,
            onTap: () => openPrescription(f),
            trailing: IconButton(
              tooltip: 'Delete prescription',
              icon: const Icon(Icons.delete_outline),
              onPressed: app.busy || app.offline
                  ? null
                  : () async {
                      if (await confirm(
                        'Delete prescription?',
                        str(f['name']),
                        action: 'Delete',
                      )) {
                        await perform(
                          () => app.mutate('delete-prescription', {
                            'id': f['id'],
                          }),
                        );
                      }
                    },
            ),
          ),
        ),
    ],
  );
  Future<void> activity() => page(
    'Activity',
    () => [
      heading('Dose history', 'Latest 100 confirmations and skips.'),
      if (data.doses.isEmpty) const Text('No doses recorded yet.'),
      for (final d in data.doses)
        Card(
          child: ListTile(
            title: Text(
              medicineName(
                data.medicine(
                  CabinetState.find(
                    data.schedules,
                    d['scheduleId'],
                  )?['medicineId'],
                ),
              ),
            ),
            subtitle: Text('${d['date']} · ${d['time']} · ${d['status']}'),
            trailing: IconButton(
              tooltip: 'Undo dose record',
              icon: const Icon(Icons.undo),
              onPressed:
                  app.busy ||
                      app.offline ||
                      !data.recentDoses().any((r) => r['id'] == d['id'])
                  ? null
                  : () async {
                      await undoDose(d);
                    },
            ),
          ),
        ),
      const SizedBox(height: 24),
      heading('Stock history', 'Latest 100 stock changes.'),
      if (data.history.isEmpty) const Text('No stock changes yet.'),
      for (final h in data.history)
        Card(
          child: ListTile(
            title: Text(medicineName(data.medicine(h['medicineId']))),
            subtitle: Text(
              '${h['reason']}\n${data.location(h['locationId'])} · ${str(h['createdAt']).replaceFirst('T', ' ')}',
            ),
            isThreeLine: true,
            trailing: Text(
              '${number(h['change']) > 0 ? '+' : ''}${quantity(h['change'])}',
            ),
          ),
        ),
    ],
  );
  Future<void> categories() => page(
    'Categories',
    () => [
      heading(
        'Organize your cabinet',
        'Nested categories keep related medicines together.',
        trailing: IconButton.filled(
          onPressed: app.busy || app.offline
              ? null
              : () => MedicineForms.category(context, app),
          icon: const Icon(Icons.add),
        ),
      ),
      if (data.categories.isEmpty)
        empty(
          'No categories yet',
          'Create a category such as Daily care or First aid.',
        ),
      for (final c in data.categories)
        Card(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(data.category(c['id'])),
            trailing: const Icon(Icons.edit_outlined),
            onTap: app.offline
                ? null
                : () => MedicineForms.category(context, app, category: c),
          ),
        ),
    ],
  );
  Future<void> locations() => page(
    'Locations',
    () => [
      heading(
        'A place for everything',
        'Know where your medicine is stored.',
        trailing: IconButton.filled(
          onPressed: app.busy || app.offline
              ? null
              : () => MedicineForms.location(context, app),
          icon: const Icon(Icons.add),
        ),
      ),
      if (data.locations.isEmpty)
        empty(
          'Add your first location',
          'For example, Home cabinet, Travel bag or Office.',
        ),
      for (final l in data.locations)
        Card(
          child: ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(str(l['name'])),
            subtitle: str(l['description']).isEmpty
                ? null
                : Text(str(l['description'])),
          ),
        ),
    ],
  );
  Future<void> archive() => page(
    'Archive',
    () => [
      heading(
        'Archived medicines',
        'Saved medicines and their stock.',
        trailing: IconButton.filled(
          onPressed: app.busy || app.offline
              ? null
              : () => MedicineForms.medicine(context, app, archived: true),
          icon: const Icon(Icons.add),
        ),
      ),
      for (final m in data.medicines.where((m) => m['archivedAt'] != null))
        medicineCard(m),
      if (!data.medicines.any((m) => m['archivedAt'] != null))
        empty(
          'Archive is empty',
          'Archived medicines keep their stock and expiry dates.',
        ),
    ],
  );
  Future<void> editUsername() async {
    var draft = str(app.user?['username']);
    final formKey = GlobalKey<FormState>();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign-in username'),
        content: Form(
          key: formKey,
          child: TextFormField(
            initialValue: draft,
            onChanged: (value) => draft = value,
            autofocus: true,
            maxLength: 30,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              helperText:
                  '3–30 characters. Start with a letter.\nLetters, numbers, dots, underscores or hyphens.',
            ),
            validator: (value) =>
                RegExp(
                  r'^[a-z][a-z0-9_.-]{2,29}$',
                ).hasMatch((value ?? '').trim().toLowerCase())
                ? null
                : 'Enter a valid username',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(context, draft.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null && mounted) await perform(() => app.setUsername(value));
  }

  Future<void> settings() => page(
    'Settings',
    () => [
      heading('Make it yours', str(app.user?['email'])),
      Card(
        child: ListTile(
          title: const Text('Sign-in username'),
          subtitle: Text(
            '${str(app.user?['username']).isEmpty ? 'Choose a username' : str(app.user?['username'])}\nEmail sign-in and password recovery remain available.',
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: editUsername,
        ),
      ),
      Card(
        child: Column(
          children: [
            SwitchListTile.adaptive(
              title: const Text('Dose reminders'),
              subtitle: const Text(
                'Scheduled on this phone, even when offline',
              ),
              value: app.doseReminders,
              onChanged: (v) => perform(
                () => app.setReminders(doses: v, stock: app.stockReminders),
              ),
            ),
            SwitchListTile.adaptive(
              title: const Text('Low-stock reminders'),
              subtitle: const Text(
                'At each medicine’s configured time, using your last synced stock and supply',
              ),
              value: app.stockReminders,
              onChanged: (v) => perform(
                () => app.setReminders(doses: app.doseReminders, stock: v),
              ),
            ),
          ],
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                app.reminders.notificationsEnabled == false
                    ? 'Notifications are blocked'
                    : '${app.reminders.pending} reminders queued on this phone',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(
                'Notification permission: ${app.reminders.notificationsEnabled == true
                    ? 'Allowed'
                    : app.reminders.notificationsEnabled == false
                    ? 'Blocked'
                    : 'Not checked'}',
              ),
              if (Platform.isAndroid)
                Text(
                  'Precise alarms: ${app.reminders.exactAlarmsAllowed == true ? 'Allowed' : 'Not allowed — reminders may be delayed'}',
                ),
              if (app.reminders.nextReminder != null)
                Text('Next reminder: ${app.reminders.nextReminder!.toLocal()}'),
              Text('Phone time zone: ${app.reminders.zone}'),
              if (app.reminders.coverage != null)
                Text(
                  'Last queued reminder: ${app.reminders.coverage!.toLocal()}',
                ),
              const SizedBox(height: 12),
              const Text(
                'Open and sync regularly to extend coverage. Changes on other devices apply after the next sync. Stock alerts estimate planned use from the last synced data.',
              ),
              if (app.reminders.warning != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    app.reminders.warning!,
                    style: const TextStyle(color: Color(0xff855b10)),
                  ),
                ),
              if (Platform.isAndroid) ...[
                TextButton.icon(
                  onPressed: () => perform(() async {
                    await app.reminders.requestExactAlarms();
                    await app.refreshReminders(force: true);
                  }),
                  icon: const Icon(Icons.alarm),
                  label: const Text('Allow precise alarms'),
                ),
                TextButton(
                  onPressed: () =>
                      perform(() => app.reminders.openNotificationSettings()),
                  child: const Text('Open notification settings'),
                ),
              ],
              TextButton(
                onPressed: () => perform(() async {
                  await app.reminders.requestPermission();
                  await app.refreshReminders(force: true);
                }),
                child: const Text('Check permissions and rebuild reminders'),
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => perform(() => app.testReminder()),
                    icon: const Icon(Icons.notifications_active_outlined),
                    label: const Text('Test notification now'),
                  ),
                  OutlinedButton(
                    onPressed: () => perform(() async {
                      await app.testReminder(scheduled: true);
                      message(
                        app.reminders.exactAlarmsAllowed == true
                            ? 'Test scheduled for 10 seconds from now. You can close the app.'
                            : 'Test scheduled. Android may delay it because precise alarms are disabled.',
                      );
                    }),
                    child: const Text('Test reminder in 10 seconds'),
                  ),
                ],
              ),
              if (Platform.isAndroid) ...[
                const SizedBox(height: 16),
                const Text(
                  'Redmi / Xiaomi phones',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const Text(
                  'If reminders are still delayed, open this app’s phone settings: enable notifications, allow background autostart, and choose No restrictions under battery saver. Menu names vary by MIUI/HyperOS version.',
                ),
                TextButton(
                  onPressed: () =>
                      perform(() => app.reminders.openAppSettings()),
                  child: const Text('Open phone app settings'),
                ),
              ],
            ],
          ),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Connected server'),
          subtitle: Text(app.api.baseUrl),
        ),
      ),
      Card(
        child: ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Sync now'),
          subtitle: Text(
            app.lastSync == null
                ? 'Not synced yet'
                : 'Last synced: ${app.lastSync!.toLocal()}',
          ),
          onTap: app.sync,
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () async {
          if (await confirm(
            'Sign out?',
            'This clears cached account data and local reminders from this phone.',
            action: 'Sign out',
          )) {
            await perform(() async {
              await app.signOut();
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            });
          }
        },
        icon: const Icon(Icons.logout),
        label: const Text('Sign out'),
      ),
    ],
  );
  List<Widget> more() => [
    heading('Everything else', 'Keep your care organized.'),
    Card(
      child: Column(
        children: [
          for (final entry in <(IconData, String, Future<void> Function())>[
            (Icons.description_outlined, 'Prescriptions', prescriptions),
            (Icons.history, 'Activity & dose history', activity),
            (Icons.folder_outlined, 'Categories', categories),
            (Icons.place_outlined, 'Stock locations', locations),
            (Icons.archive_outlined, 'Archived medicines', archive),
            (Icons.settings_outlined, 'Settings & reminders', settings),
          ])
            ListTile(
              leading: Icon(entry.$1),
              title: Text(entry.$2),
              trailing: const Icon(Icons.chevron_right),
              onTap: entry.$3,
            ),
        ],
      ),
    ),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Row(
        children: [
          const Icon(Icons.medication_outlined),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              'Hello, ${str(app.user?['name']).split(' ').first}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          onPressed: app.syncing || app.busy ? null : app.sync,
          icon: const Icon(Icons.sync),
          tooltip: 'Sync',
        ),
        IconButton(
          onPressed: app.state == null ? () => perform(app.signOut) : settings,
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (app.syncing || app.busy)
            const LinearProgressIndicator(minHeight: 2),
          if (app.error != null || app.offline)
            Material(
              color: const Color(0xffffefcf),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        app.offline
                            ? 'Offline · showing last synced data. Changes need a connection.'
                            : app.error!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: app.syncing ? null : app.sync,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: app.state == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Connect to load your cabinet.'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: app.sync,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: app.sync,
                    child: ListView(
                      key: ValueKey(tab),
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(20),
                      children: [
                        if (app.lastSync != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              'Last synced ${app.lastSync!.toLocal().toString().substring(0, 16)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xff62736e),
                              ),
                            ),
                          ),
                        ...switch (tab) {
                          0 => today(),
                          1 => cabinet(),
                          2 => schedules(),
                          _ => more(),
                        },
                      ],
                    ),
                  ),
          ),
        ],
      ),
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: tab,
      onDestinationSelected: (v) => setState(() => tab = v),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.today_outlined),
          selectedIcon: Icon(Icons.today),
          label: 'Today',
        ),
        NavigationDestination(
          icon: Icon(Icons.medication_outlined),
          selectedIcon: Icon(Icons.medication),
          label: 'Cabinet',
        ),
        NavigationDestination(
          icon: Icon(Icons.calendar_month_outlined),
          selectedIcon: Icon(Icons.calendar_month),
          label: 'Schedules',
        ),
        NavigationDestination(
          icon: Icon(Icons.grid_view_outlined),
          selectedIcon: Icon(Icons.grid_view),
          label: 'More',
        ),
      ],
    ),
  );
}
