# Medicine Tracker mobile UX

The user's instructions and the current web app are the reference for this client. Apply web interaction rules to equivalent mobile workflows and retain native controls where they improve touch use.

- **Confirm taken is the action.** Immediately record a regular dose; do not ask for a second confirmation. Show success and Undo. Do not mark taken from a notification tap.
- Keep a **Recently recorded doses** list on Today for taken/skipped records created in the last 24 hours, using the same eligibility rule as the web. Undo directly; a second popup is unnecessary.
- A drug-name dose may ask which brand was taken. The choice must be optional: provide **Continue without specifying / Automatic stock allocation**. Selecting a brand or automatic allocation records once without another confirmation popup.
- Skipping a dose retains the web's skip confirmation. Destructive deletions and archive actions retain their relevant confirmations. API validation errors remain visible; failed saves must not dismiss the editor or discard entered values.
- Searchable, explicitly selected choices for medicines, categories, locations and units. Display readable names and strengths; never expose raw IDs or JSON to end users.
- Use native time/date pickers, removable dose-time chips, weekdays and optional schedule end dates. Do not require typing a comma-separated string of times on a phone.
- Cabinet search covers brand, medicine and strength. Nested category filters include descendants; support location, low-stock and expired-stock filtering plus name ordering.
- Preserve backend stock rules: expired batches are excluded, location and pill settings matter, amounts are not rounded, and dose confirmation is idempotent. Available quantities, batch expiry, forecast horizon and low-stock thresholds must have consistent meaning across clients.
- Routine changes give concise feedback. Busy operations prevent repeated writes. Interrupted writes explain when the user should sync/check before repeating a non-idempotent stock change.
- Reminder setup shows real OS permission/channel status, precise versus approximate timing, actual queued counts and next reminder. Failed scheduling must not silently appear successful or abort all other schedules. Show actionable errors and test buttons.
- Preserve pending delayed alarms across foreground refresh; remove obsolete alarms after taking/skipping, pausing, archiving, changing schedules/preferences or restocking. Rebuild cached reminders even when offline.
- Keep cached medical data and sessions private; clear account cache, downloaded temporary prescription copies and notifications on sign-out. Offline viewing is read-only; stock changes remain server-validated.

Tests should verify interaction outcomes: no extra taking/Undo popup, optional brand allocation, skip/destructive confirmation, retained draft on error, searchable choices, and reminder reconciliation under OS delays and permission changes.

- Show reminder diagnostics and the ‘Reminders need attention’ warning in Settings only; do not show that warning on Today/home.
- Publish and cache the server’s committed stock snapshot immediately after taking, undoing or syncing, before waiting for forecasts or notification work. Clear stale estimates until refreshed. A persistence/estimate failure must not roll back or hide a committed stock update.
