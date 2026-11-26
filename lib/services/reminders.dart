import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../data/models.dart';
import 'reminder_planner.dart';

class ReminderService {
  ReminderService({
    FlutterLocalNotificationsPlugin? plugin,
    Future<String> Function()? deviceTimeZone,
    DateTime Function()? clock,
    bool? android,
    bool? ios,
  }) : plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       deviceTimeZone = deviceTimeZone ?? FlutterTimezone.getLocalTimezone,
       clock = clock ?? DateTime.now,
       isAndroid = android ?? Platform.isAndroid,
       isIOS = ios ?? Platform.isIOS;
  final FlutterLocalNotificationsPlugin plugin;
  final Future<String> Function() deviceTimeZone;
  final DateTime Function() clock;
  final bool isAndroid, isIOS;
  static const deviceSettings = MethodChannel(
    'medicine_tracker/device_settings',
  );
  String zone = 'UTC';
  String? warning, initializationError;
  int pending = 0;
  DateTime? coverage, nextReminder;
  bool ready = false;
  bool? notificationsEnabled, exactAlarmsAllowed;
  bool doseChannelBlocked = false, stockChannelBlocked = false;
  Future<void> _operation = Future.value();
  void Function(Json data)? onTap;
  Json? launchPayload;
  AndroidFlutterLocalNotificationsPlugin? get androidPlugin => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> initialize() async {
    tzdata.initializeTimeZones();
    if (!isAndroid && !isIOS) {
      warning = 'Local reminders require Android or iOS.';
      return;
    }
    try {
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('ic_stat_medicine'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) => _tap(response.payload),
      );
      ready = true;
      initializationError = null;
      if (isAndroid) {
        for (final channel in const [
          AndroidNotificationChannel(
            'medicine_doses',
            'Dose reminders',
            importance: Importance.high,
          ),
          AndroidNotificationChannel(
            'medicine_stock',
            'Stock reminders',
            importance: Importance.high,
          ),
        ]) {
          await androidPlugin?.createNotificationChannel(channel);
        }
      }
      final launch = await plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null) {
        try {
          launchPayload = Map<String, dynamic>.from(jsonDecode(payload) as Map);
        } catch (_) {
          /* Obsolete notification. */
        }
      }
      await refreshStatus();
    } catch (error) {
      ready = false;
      initializationError = _errorText(error);
      warning =
          'Local reminders could not start: $initializationError. Tap Rebuild reminders to retry.';
    }
    // An OS time-zone lookup failure must not prevent the notification plugin
    // from initializing; dose alarms already carry their own schedule zones.
    try {
      zone = await deviceTimeZone();
      tz.getLocation(zone);
    } catch (_) {
      zone = 'UTC';
      warning =
          'Phone time zone is unavailable. Stock reminders currently use UTC.';
    }
  }

  String _errorText(Object error) => error is PlatformException
      ? error.code
      : 'phone notification service unavailable';
  void _tap(String? payload) {
    if (payload == null) return;
    try {
      onTap?.call(Map<String, dynamic>.from(jsonDecode(payload) as Map));
    } catch (_) {
      /* Obsolete notification. */
    }
  }

  Future<void> refreshStatus() async {
    if (!ready) return;
    if (isAndroid) {
      notificationsEnabled = await androidPlugin?.areNotificationsEnabled();
      exactAlarmsAllowed = await androidPlugin?.canScheduleExactNotifications();
      final channels = await androidPlugin?.getNotificationChannels() ?? [];
      doseChannelBlocked = channels.any(
        (c) => c.id == 'medicine_doses' && c.importance == Importance.none,
      );
      stockChannelBlocked = channels.any(
        (c) => c.id == 'medicine_stock' && c.importance == Importance.none,
      );
    } else if (isIOS) {
      final permissions = await plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions();
      notificationsEnabled = permissions?.isEnabled;
      exactAlarmsAllowed = true;
    }
    final requests = await plugin.pendingNotificationRequests();
    pending = requests.length;
    final times = <DateTime>[];
    for (final request in requests) {
      try {
        final date = DateTime.tryParse(
          str(jsonDecode(request.payload ?? '{}')['at']),
        );
        if (date != null && date.isAfter(clock())) times.add(date);
      } catch (_) {
        /* Old payload. */
      }
    }
    times.sort();
    nextReminder = times.firstOrNull;
    coverage = times.lastOrNull;
  }

  Future<bool> requestPermission() async {
    if (!ready) await initialize();
    if (!ready) return false;
    final granted = isAndroid
        ? await androidPlugin?.requestNotificationsPermission() ?? false
        : await plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(alert: true, badge: true, sound: true) ??
              false;
    await refreshStatus();
    return granted && notificationsEnabled != false;
  }

  Future<void> requestExactAlarms() async {
    if (!ready) await initialize();
    if (isAndroid && ready) {
      await androidPlugin?.requestExactAlarmsPermission();
      await refreshStatus();
    }
  }

  Future<void> openNotificationSettings({String? channel}) async {
    if (isAndroid) {
      await deviceSettings.invokeMethod<void>('notificationSettings', {
        'channel': channel,
      });
    }
  }

  Future<void> openAppSettings() async {
    if (isAndroid) await deviceSettings.invokeMethod<void>('appSettings');
  }

  NotificationDetails _details(String type, {bool silent = false}) =>
      NotificationDetails(
        android: AndroidNotificationDetails(
          type == 'low_stock' ? 'medicine_stock' : 'medicine_doses',
          type == 'low_stock' ? 'Stock reminders' : 'Dose reminders',
          importance: Importance.high,
          priority: Priority.high,
          visibility: NotificationVisibility.private,
          onlyAlertOnce: true,
          autoCancel: type != 'dose_due',
          playSound: !silent,
          enableVibration: !silent,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentSound: !silent,
        ),
      );

  Future<void> reconcile(
    CabinetState state,
    Json insights, {
    required bool doses,
    required bool stock,
    bool force = false,
  }) {
    _operation = _operation
        .catchError((Object _) {})
        .then(
          (_) => _reconcile(
            state,
            insights,
            doses: doses,
            stock: stock,
            force: force,
          ),
        );
    return _operation;
  }

  Future<void> _reconcile(
    CabinetState state,
    Json insights, {
    required bool doses,
    required bool stock,
    required bool force,
  }) async {
    if (!ready) await initialize();
    if (!ready) return;
    final issues = <String>[];
    try {
      try {
        zone = await deviceTimeZone();
        tz.getLocation(zone);
      } catch (_) {
        zone = 'UTC';
        issues.add('Phone time zone is unavailable; stock reminders use UTC.');
      }
      await refreshStatus();
      if (notificationsEnabled == false && (doses || stock)) {
        issues.add('Notifications are blocked in phone settings.');
      }
      if (doses && doseChannelBlocked) {
        issues.add('The Dose reminders notification channel is blocked.');
      }
      if (stock && stockChannelBlocked) {
        issues.add('The Stock reminders notification channel is blocked.');
      }
      var exact = exactAlarmsAllowed == true;
      if (!exact && doses) {
        issues.add(
          'Precise alarms are not allowed. Dose reminders may arrive late.',
        );
      }
      final now = clock();
      final existing = {
        for (final n in await plugin.pendingNotificationRequests())
          n.id: n.payload,
      };
      // Delivered notifications are no longer in the pending alarm queue.
      for (final active in await plugin.getActiveNotifications()) {
        if (active.id == null || active.payload == null) continue;
        final payload = Map<String, dynamic>.from(
          jsonDecode(active.payload!) as Map,
        );
        if (payload['type'] != 'dose_due') continue;
        final remaining = doses ? remainingDoseItems(payload, state) : <Json>[];
        if (remaining.isEmpty) {
          await plugin.cancel(active.id!);
        } else if (jsonEncode(remaining) != jsonEncode(payload['items'])) {
          final updated = {...payload, 'items': remaining};
          await plugin.show(
            active.id!,
            'Medicine reminder',
            doseReminderBody(updated),
            _details('dose_due', silent: true),
            payload: jsonEncode(updated),
          );
        }
      }
      // A delayed alarm may still be queued when some of its doses are taken.
      for (final entry in existing.entries.toList()) {
        if (entry.value == null) continue;
        final payload = Map<String, dynamic>.from(
          jsonDecode(entry.value!) as Map,
        );
        final at = DateTime.tryParse(str(payload['at']));
        if (payload['type'] != 'dose_due' || at == null || at.isAfter(now)) {
          continue;
        }
        final remaining = doses ? remainingDoseItems(payload, state) : <Json>[];
        if (remaining.isNotEmpty &&
            jsonEncode(remaining) != jsonEncode(payload['items'])) {
          await plugin.cancel(entry.key);
          final updated = {...payload, 'items': remaining};
          await plugin.show(
            entry.key,
            'Medicine reminder',
            doseReminderBody(updated),
            _details('dose_due', silent: true),
            payload: jsonEncode(updated),
          );
          existing.remove(entry.key);
        }
      }
      final retained = existing.entries
          .where(
            (e) => retainPendingReminder(
              e.value,
              state,
              insights,
              now,
              zone,
              doses: doses,
              stock: stock,
            ),
          )
          .map((e) => e.key)
          .toSet();
      final plan = planReminders(
        state,
        insights,
        now,
        zone,
        doses: doses,
        stock: stock,
        limit: (60 - retained.length).clamp(0, 60),
      );
      final desired = {...retained, for (final n in plan) n.id};
      for (final id in existing.keys.where((id) => !desired.contains(id))) {
        await plugin.cancel(id);
      }
      var failures = 0;
      for (final reminder in plan) {
        final payload = jsonEncode({
          ...jsonDecode(reminder.payload) as Map<String, dynamic>,
          'at': reminder.when.toUtc().toIso8601String(),
          'precision': exact ? 'exact' : 'approximate',
        });
        if (!force && existing[reminder.id] == payload) continue;
        try {
          await plugin.zonedSchedule(
            reminder.id,
            reminder.type == 'dose_due'
                ? 'Medicine reminder'
                : 'Medicine stock reminder',
            reminder.type == 'dose_due'
                ? doseReminderBody(reminder.data)
                : 'Your estimated medicine supply is running low. Review your cabinet.',
            reminder.when,
            _details(reminder.type),
            androidScheduleMode: exact
                ? AndroidScheduleMode.exactAllowWhileIdle
                : AndroidScheduleMode.inexactAllowWhileIdle,
            payload: payload,
          );
        } on PlatformException catch (e) {
          // Permission can change while scheduling. Retry this alarm approximately
          // instead of silently abandoning the rest of the medicine schedule.
          if (e.code == 'exact_alarms_not_permitted' && exact) {
            exact = false;
            exactAlarmsAllowed = false;
            issues.add(
              'Precise alarm permission changed. Using approximate reminders.',
            );
            try {
              await plugin.zonedSchedule(
                reminder.id,
                'Medicine reminder',
                'Open Medicine Tracker to review your reminders.',
                reminder.when,
                _details(reminder.type),
                androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
                payload: jsonEncode({
                  ...jsonDecode(payload) as Map<String, dynamic>,
                  'precision': 'approximate',
                }),
              );
            } catch (_) {
              failures++;
            }
          } else {
            failures++;
          }
        } catch (_) {
          failures++;
        }
      }
      await refreshStatus();
      if (failures > 0) {
        issues.add(
          '$failures reminders could not be scheduled. Tap Rebuild reminders to retry.',
        );
      }
      if (pending >= 60) {
        issues.add(
          'The next 60 reminders are queued. Open the app regularly to extend coverage.',
        );
      }
      warning = issues.isEmpty ? null : issues.toSet().join('\n');
    } catch (error) {
      warning =
          'Could not update reminders: ${_errorText(error)}. Tap Rebuild reminders to retry.';
    }
  }

  Future<void> testNotification({bool scheduled = false}) {
    _operation = _operation.catchError((Object _) {}).then((_) async {
      if (!await requestPermission()) {
        throw StateError('Allow notifications in phone settings first.');
      }
      if (doseChannelBlocked) {
        throw StateError(
          'Enable the Dose reminders channel in phone notification settings.',
        );
      }
      final at = clock().add(const Duration(seconds: 10));
      final payload = jsonEncode({
        'type': 'test_reminder',
        'key': 'test',
        'at': at.toUtc().toIso8601String(),
      });
      if (scheduled) {
        await plugin.zonedSchedule(
          2147483646,
          'Test reminder',
          'This is your scheduled Medicine Tracker test.',
          tz.TZDateTime.from(at, tz.getLocation(zone)),
          _details('dose_due'),
          androidScheduleMode: exactAlarmsAllowed == true
              ? AndroidScheduleMode.exactAllowWhileIdle
              : AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      } else {
        await plugin.show(
          2147483645,
          'Test notification',
          'Medicine Tracker notifications are working on this phone.',
          _details('dose_due'),
          payload: payload,
        );
      }
      await refreshStatus();
    });
    return _operation;
  }

  Future<void> clear() {
    _operation = _operation.catchError((Object _) {}).then((_) async {
      if (ready) await plugin.cancelAll();
      pending = 0;
      coverage = null;
      nextReminder = null;
    });
    return _operation;
  }
}
