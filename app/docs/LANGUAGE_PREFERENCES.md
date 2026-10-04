# Language preferences

Added on 2026-10-04 at the user's request, independently of the deferred biology Phases 2–5.

## Behavior

- English is the default for new and existing profiles without a supported choice. The available choices are English (`en`), Español (`es`), 简体中文 (`zh-Hans`), and 繁體中文 (`zh-Hant`). Region/script aliases are normalized; malformed or unsupported stored values fall back to English. See [language_preference.dart](../lib/src/language_preference.dart).
- A language picker on the welcome/sign-up screen changes the interface immediately, before consent or account creation. This preview stays in memory until ordinary consented onboarding saves the profile. It neither creates a consent receipt nor opens an age/guardian gate. See [onboarding_screen.dart](../lib/src/screens/onboarding_screen.dart).
- Profile → Settings → Language updates the interface and saves the choice. The picker displays native language names so a user can recover from an accidental choice. A failed local write shows an error and restores the previous preference; queued choices cannot finish out of order. See [language_picker.dart](../lib/src/widgets/language_picker.dart) and [controller](../lib/src/app_controller.dart).
- `UserProfile.preferredLanguage` is an additive field in the existing profile JSON, local state, ordinary owner-scoped Firestore profile sync, and backups/exports. Missing fields remain compatible with existing profiles. No score, preparation, model, consent or Firestore-rules version changed. A language-only change does not invalidate score/forecast/preparation artifacts or regenerate scheduled reminders. See [models.dart](../lib/src/models.dart), [input synchronization](../lib/src/cloud_sync.dart), and [controller](../lib/src/app_controller.dart).
- Authenticated profile reload restores the account choice. Sign-out returns to the neutral English welcome, unless this session has an explicit onboarding preview. This is an account preference, not an OS-wide language setting.

## Translation coverage and limits

Bundled authored catalogs translate main navigation, sign-up/account/settings/privacy, Today and sleep observations, the main Forecast/Insights/Coach interface, and activity/sleep/check-in/reaction/history logging. Flutter's SDK localization delegates supply translated standard controls, date pickers and time pickers. Spanish activity input accepts a decimal comma while keeping zero distinct from a blank field.

Some technical diagnostics, detailed model explanations, generated guidance/evidence strings, exports, and native notification payloads remain in English. Both language pickers disclose that limitation. Unknown authored strings use a readable English fallback. Selecting a language does not reschedule or translate an already pending native reminder. These are initial interface translations; no professional linguistic or clinical review is claimed.

User names and free-text notes remain exactly as entered. Stored enum values, source identifiers, calculation versions and confirmation tokens keep their existing stable values; translations apply to presentation. The app does not send text, account details or health observations to a translation service. Simplified and Traditional Chinese are distinct saved choices; the Traditional catalog uses script conversion of the authored Simplified text.

Catalogs and shared lookup: [app_localizations.dart](../lib/src/l10n/app_localizations.dart), [account](../lib/src/l10n/account_translations.dart), [core](../lib/src/l10n/core_translations.dart), [forecast](../lib/src/l10n/forecast_translations.dart), [logging](../lib/src/l10n/logging_translations.dart). Flutter SDK localization and integration-test dependencies were resolved from the existing offline cache; previously locked package versions were retained.

## Verification

Regression cases cover normalized/default/invalid tags, catalog placeholder integrity, immediate Spanish/Chinese interface changes, ordinary adult consent and retained guardian restrictions, local failure/overlapping-save handling, account/profile reload, backup/export fields, retained raw observations and derived artifacts, decimal-comma/zero logging, unchanged user notes, and narrow-screen layout. See `test/account_language_widget_test.dart`, `test/language_preference_test.dart`, `test/language_persistence_test.dart`, `test/logging_localization_test.dart`, and `test/forecast_phase1_widget_test.dart`.

Actual command results and the native Auth/Firestore save/restart result are recorded in [BIOLOGY_UPGRADE_PROGRESS.md](BIOLOGY_UPGRADE_PROGRESS.md) and [PHASE1_EMULATOR_INTEGRATION.md](PHASE1_EMULATOR_INTEGRATION.md). Unit/widget reload tests alone do not establish physical-device restart behavior.

## Phase 2A measurement extension

The six-measure custom check-in now has bundled English, Spanish, Simplified Chinese and Traditional Chinese wording. Each response stores the exact displayed definition and its language/version. Changing the interface language later does not translate or rewrite the original response; editing retains its stored wording. Notes remain unchanged. These draft translations have not established cross-language psychometric equivalence, and the new responses are excluded from legacy model inputs. See [measurement translations](../lib/src/l10n/measurement_translations.dart) and [the measurement guide](PHASE2A_MEASUREMENT.md).
