# Medicine Tracker — Flutter

AWS integration is prepared: Cognito email verification/password recovery/temporary-password flows use the shared API, and cloud prescription files transfer directly to private S3 without forwarding the API session. The app connects directly to the fixed production HTTPS API; on-device reminders and the existing package ID are preserved. The full AWS runbook is `D:/Projects/Programming/Fullstack/MedicineTracker/medicine-tracker/docs/deploy-aws.md`.


Android and iOS client for the existing Medicine Tracker API, with **on-device local notifications**. Uses the same accounts, medicines and schedules as the web app. The app has no Firebase, SNS, or cloud push dependency and never registers an FCM device token.

## Run

This project was built with Flutter 3.32.4 / Dart 3.8.1. Dependencies are locked in `pubspec.lock` for that SDK.

```powershell
flutter pub get
flutter run
```

The backend address is fixed in `MedicineApi.productionBaseUrl`:
`https://14ht6ah4ql.execute-api.ap-south-1.amazonaws.com`.
There is no server selector or build-time endpoint override. The API appends `/api` to this origin. A session saved for a different server is discarded on upgrade; sign in with the production account. This does not change records on either backend.

Android and iOS launcher assets and the sign-in logo use the web favicon artwork, retained in `assets/branding/app-icon.svg`.

## Implemented workflows

- Existing-account sign-in and account creation through mobile bearer authentication.
- Secure session storage; cached state for offline viewing; refresh on resume, pull-to-refresh and 30-second foreground polling.
- Today timeline with upcoming and unresolved doses. One-tap dose taking with no confirmation popup; skip confirmation and an optional brand choice/automatic allocation for drug-name schedules. Recent records offer direct Undo for 24 hours. Stock is deducted only by the backend after confirmation.
- Cabinet search, category filters including descendants, low-stock and expired-batch filters.
- Medicine creation/editing, units, notes, category assignment, initial stock, pill fractions and permitted multiples, prescribed-strength settings.
- Stock addition/reduction/exact count, expiry dates, batch editing and deletion with stale-quantity protection.
- Schedules with per-schedule IANA zones, weekdays, multiple dose times, start/end bounds, quantity/strength entry, drug-name pooling and pause/resume.
- Server-calculated days of supply and per-schedule forecasts.
- Archive/restore, preserved stock batches, and explicit permanent-deletion confirmation.
- Category hierarchy and stock locations.
- Prescription upload (PDF/PNG/JPEG, up to 5 MiB), authenticated download/open and deletion.
- Latest 100 stock movements and dose records, including undo.
- Separate local dose/stock reminder switches, runtime permission requests, precise-alarm opt-in on Android, scheduled-count and coverage display.

Offline viewing does not queue writes. Reconnect and sync before changing stock or confirming doses, so multiple clients share the backend's atomic stock rules. Authentication sessions expire after 30 days; sign in again when prompted. No password is saved. Cached state, tokens and reminder preferences use platform secure storage. Signing out removes account cache, locally downloaded prescription copies and all scheduled notifications; files explicitly saved/exported by another viewer app are outside this app's storage. Offline sign-out clears this phone; the inaccessible server session expires normally.

## Local notification behavior

Enable reminders under **More → Settings & reminders**, then grant phone notification permission. On Android, **Allow precise alarms** opens the system setting for exact alarms. Without that permission the app schedules approximate alarms instead. Android manifest setup includes reboot/package-update receivers; a monochrome notification icon is bundled. iOS foreground notification delegation is configured in `AppDelegate.swift`.

After a successful sync, a mutation or a reminder preference change, the app reconciles pending one-shot alarms with the current state. Disabling reminders, pausing schedules, archiving medicines or recording doses removes obsolete pending reminders. Notification taps open Today or Cabinet and trigger a fresh sync; they never take a dose automatically. Bodies are generic and avoid medicine names on the lock screen.

- Dose occurrences are calculated in the schedule's IANA zone, independent of the phone's zone. Weekdays, start/end dates and recorded/skipped doses are respected. Nonexistent daylight-saving times are skipped. Past doses are shown in the timeline after sync and do not create a flood of overdue notifications.
- The app plans dose alarms up to 30 days ahead and stock summaries up to seven days ahead, then queues the earliest **60 total** reminders to remain below iOS's pending-alarm limit. The Settings screen shows the last queued reminder. Open/sync regularly to refill the queue, especially with several doses per day.
- Stock summaries occur at 09:00 in the phone's zone when projected days of supply cross the medicine's threshold. They use the server's last supply estimate and expected future use, and can become stale without a sync. No active schedule/no finite supply estimate means no stock alarm for that medicine.
- The OS delivers already-scheduled reminders while offline/closed, subject to phone notification settings, power restrictions, time changes and force-stop behavior. There is no background service continuously syncing web edits or refilling the queue while the app is closed. Changes on the web or another phone reach this phone on its next sync.

The previous backend's optional cloud-push sender is not used. Leave `FCM_SERVICE_ACCOUNT_PATH` unset for a local-notification-only deployment. No Firebase configuration files, APNs push certificates or SNS endpoints are needed for these local reminders.

## Code

| Location | Responsibility |
| --- | --- |
| `lib/data/api.dart` | Typed API errors, bearer headers, JSON and authenticated file requests |
| `lib/data/controller.dart` | Session lifecycle, secure cache, sync/mutations, account transition guards |
| `lib/data/models.dart` | Shared JSON record helpers, categories, expiry-aware stock totals |
| `lib/services/reminder_planner.dart` | Pure time-zone-aware one-shot reminder planning |
| `lib/services/reminders.dart` | OS permissions, pending-alarm reconciliation and notification taps |
| `lib/ui/auth.dart` | Sign-in, account creation and server connection |
| `lib/ui/home.dart` | Main tabs, detail screens, prescriptions, history and settings |
| `lib/ui/forms.dart` | Validated medicine, stock, schedule, category and location editors |

The backend API guide is `D:\Projects\Programming\Fullstack\MedicineTracker\medicine-tracker\docs\mobile-backend.md`; shared API types and mutation validation remain authoritative. The backend's 100-record history limits apply here as on the web.

## Checks

```powershell
flutter analyze
flutter test
flutter build apk --debug
```

Tests cover bearer requests, errors, URL validation, expiry-aware stock, time zones, DST, date bounds, recorded-dose exclusion, queue limits, stock thresholds, Android delayed-alarm retention, notification permissions, scheduling failures, offline re-arming, one-tap taking/Undo, searchable selectors and skip confirmation. Widget tests also generate `artifacts/today.png` and `artifacts/cabinet.png` using synthetic data for visual review. The Android debug APK is a development build using the starter app ID and debug signing. Configure your own app ID and release signing before distribution.

On-device verification is still required: enable reminders, create a schedule a few minutes ahead, close the app, verify arrival, edit/pause/confirm and verify cancellation, then verify reboot behavior and permission denial. Verify stock summaries with a threshold-crossing forecast. iOS compilation and physical iOS notification checks require macOS/Xcode and an iOS device.

## Reminder troubleshooting and UX alignment

Open **More → Settings & reminders**. Check the actual notification-permission and precise-alarm statuses, next queued reminder and any channel errors. **Test notification now** tests display on the dose channel. **Test reminder in 10 seconds** tests scheduling; close the app after scheduling. With approximate alarms, Android may deliver later than ten seconds. **Check permissions and rebuild reminders** works from cached state without requiring the API to be online.

On Android, enabling dose reminders requests notification and precise-alarm permissions. If precise alarms are declined the app clearly reports approximate timing. For existing installations, use **Allow precise alarms**, then rebuild. Permission changes and app resume re-arm future alarms. An in-flight alarm delayed beyond its nominal due time is retained for up to one hour; a foreground sync does not silently cancel it. Recorded, paused, archived, disabled or restocked reminders still cancel immediately. Pending counts come from the phone plugin rather than the desired plan. A failure for one alarm does not abandon every remaining alarm.

For Redmi/Xiaomi devices, **Open phone app settings** provides access to battery/autostart settings: enable notifications and background autostart, and choose **No restrictions** under the app's battery settings if delivery remains unreliable. Names vary by MIUI/HyperOS version. See [Xiaomi's background autostart guidance](https://www.mi.com/global/support/faq/details/KA-497677/) and the [notification plugin's device restrictions](https://pub.dev/packages/flutter_local_notifications/versions/19.5.0). No phone was connected over ADB during this fix; actual delivery on the Redmi still needs checking with the two test buttons.

Native Android settings buttons require a full stop/rebuild/install; hot reload or Dart hot restart alone cannot update Java code. Install the updated APK or stop `flutter run` and run it again. User data remains in the same app sandbox when updating the existing app; do not uninstall just to update.

The mobile UX follows the current web app: see [UX.md](UX.md) for the rules maintained alongside this client.
