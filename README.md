# Shift Blocks

An offline personal shift calendar built with Flutter. Create named/color-coded presets, repeat an anchored rotation, preview a constrained seeded random draft, protect dates, and undo changes. Overnight work is counted on its start date; hours use the selected IANA timezone and subtract breaks. Export and restore user-selected JSON backups.

Schedules remain on the device. This version has no automatic cloud sync, employer-system connection, team staffing solver, OCR import, or reminders. Drafts are personal plans to check against an employer's official roster.

The initial UI and store materials are English. Strings are separated in lib/strings.dart. Production Google Mobile Ads and regional UMP messages are configured independently for Android and iOS. Core use remains available offline or when advertising consent is declined. Debug builds use test ads; integration tests disable ad initialization.

## Checks

Use Flutter 3.47.5, then flutter pub get, flutter analyze, and flutter test test. Native screenshot/persistence checks use flutter drive --no-start-paused --driver=test_driver/screenshots.dart --target=integration_test/native_flow_test.dart -d DEVICE_ID. CI exercises iPhone and iPad simulators; Android is checked on an API 35 emulator.

Tests cover anchors, protected/past dates, undo, random target/rest/run constraints, impossible drafts, DST/overnight duration, and backup validation. Store screenshots come from actual native rendering.

Release builds require the platform's production ADMOB_BANNER_ID and signing inputs. Private signing assets and control state are excluded from Git. CI preserves the existing signing identity with an app-specific profile. Upload success, review acceptance, and public availability are tracked separately; this repository does not imply either store has published the app.

[Privacy](https://wjb127.github.io/shift-blocks/privacy.html) · [Support](https://wjb127.github.io/shift-blocks/)
