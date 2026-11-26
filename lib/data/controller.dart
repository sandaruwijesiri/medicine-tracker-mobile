import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api.dart';
import 'models.dart';
import '../services/reminders.dart';

class AppController extends ChangeNotifier {
  AppController({
    MedicineApi? api,
    FlutterSecureStorage? storage,
    ReminderService? reminders,
  }) : api = api ?? MedicineApi(),
       storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions(encryptedSharedPreferences: true),
           ),
       reminders = reminders ?? ReminderService();
  final MedicineApi api;
  final FlutterSecureStorage storage;
  final ReminderService reminders;
  Json? user;
  CabinetState? state;
  Json insights = {};
  bool loading = true, syncing = false, busy = false, offline = false;
  bool doseReminders = false, stockReminders = false;
  String? error;
  DateTime? lastSync;
  Timer? _timer;
  int _accountVersion = 0;
  bool get signedIn => user != null;
  Future<void> initialize() async {
    try {
      await reminders.initialize();
      api.baseUrl = MedicineApi.productionBaseUrl;
      final previousServer = await storage.read(key: 'server');
      if (previousServer != null && previousServer != api.baseUrl) {
        await _clearAccount();
      }
      doseReminders = await storage.read(key: 'doseReminders') == 'true';
      stockReminders = await storage.read(key: 'stockReminders') == 'true';
      final session = await storage.read(key: 'session');
      if (session != null) {
        final auth = jsonDecode(session) as Map;
        final expires = DateTime.tryParse(str(auth['expiresAt']));
        if (expires == null || !expires.isAfter(DateTime.now())) {
          await _clearAccount();
          error = 'Your session expired. Sign in again.';
        } else {
          api.token = str(auth['accessToken']);
          user = Map<String, dynamic>.from(auth['user'] as Map);
          final cache = await storage.read(key: 'cache');
          if (cache != null) {
            final saved = jsonDecode(cache) as Map;
            state = CabinetState(
              Map<String, dynamic>.from(saved['state'] as Map),
            );
            insights = Map<String, dynamic>.from(
              saved['insights'] as Map? ?? {},
            );
            lastSync = DateTime.tryParse(str(saved['lastSync']));
          }
          await refreshReminders(force: true);
          loading = false;
          notifyListeners();
          await sync(forceReminders: true);
        }
      } else {
        await reminders.clear();
      }
    } catch (_) {
      error =
          'Could not restore the saved session. Check device storage or sign in again.';
    }
    loading = false;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (signedIn && !busy) unawaited(sync());
    });
  }

  Future<Json?> authenticate({
    required String email,
    required String password,
    String? name,
    String? action,
    String? code,
    String? newPassword,
    String? challengeSession,
    String? challengeUsername,
  }) async {
    _accountVersion++;
    api.baseUrl = MedicineApi.productionBaseUrl;
    api.token = null;
    final auth = await api.post(
      action == null
          ? (name == null ? 'mobile/login' : 'mobile/register')
          : 'mobile/auth/$action',
      {
        'email': email.trim(),
        'password': password,
        if (name != null) 'name': name.trim(),
        if (code != null) 'code': code,
        if (newPassword != null) 'newPassword': newPassword,
        if (challengeSession != null) 'session': challengeSession,
        if (challengeUsername != null) 'username': challengeUsername,
      },
    );
    if (auth['confirmationRequired'] == true ||
        auth['challenge'] != null ||
        auth['ok'] == true) {
      return auth;
    }
    await reminders.clear();
    // A new account must never see the previous user's cache/preferences.
    await storage.delete(key: 'cache');
    state = null;
    insights = {};
    lastSync = null;
    api.token = str(auth['accessToken']);
    user = Map<String, dynamic>.from(auth['user'] as Map);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (signedIn && !busy) unawaited(sync());
    });
    await storage.write(key: 'server', value: api.baseUrl);
    await storage.write(key: 'session', value: jsonEncode(auth));
    error = null;
    notifyListeners();
    await sync(forceReminders: true);
    return null;
  }

  Future<void> setUsername(String username) async {
    final accountVersion = _accountVersion;
    final updated = await api.post('account/username', {'username': username});
    if (accountVersion != _accountVersion || !signedIn) return;
    final savedSession = await storage.read(key: 'session');
    if (accountVersion != _accountVersion || !signedIn) return;
    user = updated;
    if (savedSession != null) {
      final session = Map<String, dynamic>.from(
        jsonDecode(savedSession) as Map,
      );
      await storage.write(
        key: 'session',
        value: jsonEncode({...session, 'user': updated}),
      );
    }
    notifyListeners();
  }

  Future<void> sync({bool forceReminders = false}) async {
    if (!signedIn || syncing || busy) return;
    final accountVersion = _accountVersion;
    syncing = true;
    notifyListeners();
    try {
      final data = await api.get('state');
      if (accountVersion != _accountVersion) return;
      _publishState(data);
      await _persistState();
      if (accountVersion != _accountVersion) return;
      try {
        final result = await api.get('mobile/insights');
        if (accountVersion != _accountVersion) return;
        insights = result;
        notifyListeners();
      } catch (_) {
        if (accountVersion != _accountVersion) return;
        insights = {};
        error = 'Data synced, but supply estimates are unavailable.';
      }
      await _persistState();
      if (accountVersion != _accountVersion) return;
      await reminders.reconcile(
        state!,
        insights,
        doses: doseReminders,
        stock: stockReminders,
        force: forceReminders,
      );
    } on ApiException catch (e) {
      if (accountVersion != _accountVersion) return;
      if (e.status == 401) {
        await _clearAccount();
        error = 'Your session expired. Sign in again.';
      } else {
        offline = true;
        error = e.message;
      }
    } catch (_) {
      if (accountVersion != _accountVersion) return;
      error = 'Could not sync. Your last synced data is available.';
      offline = true;
    }
    if (offline && state != null && signedIn) {
      await refreshReminders(force: forceReminders);
    }
    syncing = false;
    notifyListeners();
  }

  // Publish the authoritative server response before optional estimates, secure
  // persistence or OS reminder work. A slow follow-up must not hide a committed
  // stock restoration or leave the visible cabinet on its previous snapshot.
  void _publishState(Json fresh) {
    state = CabinetState(fresh);
    insights = {};
    lastSync = DateTime.now();
    offline = false;
    error = null;
    notifyListeners();
  }

  Future<void> _persistState() async {
    try {
      await _cache();
    } catch (_) {
      error =
          'Server data is up to date, but this phone could not update its offline copy.';
      notifyListeners();
    }
  }

  Future<void> _cache() async {
    if (state != null) {
      await storage.write(
        key: 'cache',
        value: jsonEncode({
          'state': state!.json,
          'insights': insights,
          'lastSync': lastSync?.toIso8601String(),
        }),
      );
    }
  }

  Future<void> mutate(String command, Json input) async {
    if (busy || syncing) {
      throw const ApiException('Wait for the current sync to finish.');
    }
    if (offline) {
      throw const ApiException('Reconnect and sync before making changes.');
    }
    final accountVersion = _accountVersion;
    busy = true;
    notifyListeners();
    try {
      final result = await api.post(command, input);
      if (accountVersion != _accountVersion) return;
      _publishState(result);
      await _persistState();
      if (accountVersion != _accountVersion) return;
      try {
        final result = await api.get('mobile/insights');
        if (accountVersion != _accountVersion) return;
        insights = result;
        notifyListeners();
      } catch (_) {
        if (accountVersion != _accountVersion) return;
        error = 'Saved. Supply estimates will update on the next sync.';
      }
      await _persistState();
      if (accountVersion != _accountVersion) return;
      await reminders.reconcile(
        state!,
        insights,
        doses: doseReminders,
        stock: stockReminders,
      );
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _clearAccount();
      }
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> setReminders({required bool doses, required bool stock}) async {
    if ((doses || stock) && !await reminders.requestPermission()) {
      throw const ApiException(
        'Notifications are disabled. Allow them in your phone settings and try again.',
      );
    }
    if (doses && reminders.isAndroid && reminders.exactAlarmsAllowed != true) {
      await reminders.requestExactAlarms();
    }
    doseReminders = doses;
    stockReminders = stock;
    await storage.write(key: 'doseReminders', value: '$doses');
    await storage.write(key: 'stockReminders', value: '$stock');
    if (state != null) {
      await reminders.reconcile(state!, insights, doses: doses, stock: stock);
    }
    notifyListeners();
  }

  Future<void> refreshReminders({bool force = false}) async {
    if (state != null) {
      await reminders.reconcile(
        state!,
        insights,
        doses: doseReminders,
        stock: stockReminders,
        force: force,
      );
    } else {
      await reminders.refreshStatus();
    }
    notifyListeners();
  }

  Future<void> testReminder({bool scheduled = false}) async {
    await reminders.testNotification(scheduled: scheduled);
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      await api.post('logout', {});
    } catch (_) {
      /* Local sign-out still clears credentials and reminders offline. */
    }
    await _clearAccount();
    error = null;
    notifyListeners();
  }

  Future<void> _clearAccount() async {
    _accountVersion++;
    syncing = false;
    _timer?.cancel();
    await reminders.clear();
    try {
      final root = await getTemporaryDirectory();
      final files = Directory('${root.path}/medicine-prescriptions');
      if (await files.exists()) await files.delete(recursive: true);
    } catch (_) {
      /* An unopened prescription has no local copy. */
    }
    await storage.delete(key: 'session');
    await storage.delete(key: 'cache');
    api.token = null;
    user = null;
    state = null;
    insights = {};
    lastSync = null;
  }

  Json? supply(String id) => records(
    insights['medicines'],
  ).where((m) => m['medicineId'] == id).firstOrNull;
  @override
  void dispose() {
    _timer?.cancel();
    api.close();
    super.dispose();
  }
}
