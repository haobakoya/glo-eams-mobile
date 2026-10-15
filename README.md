# GLO EAMS Mobile (merged and enhanced)

The Globacom-branded EAMS app UI combined with a working attendance engine. Everything the screens show comes from the
phone's real state or the server. Nothing is simulated.

## What came from where
| From the original GLO EAMS UI | From the attendance engine |
|---|---|
| GLO green design system (`core/theme`, `core/widgets`), logo, login layout, dashboard, identity enrolment wizard, stage-by-stage attendance journey, profile and security centre | Active Directory sign-in, geofenced clock in/out, encrypted offline queue with background sync, device checks, face enrolment and automatic matching with manager confirmation, photo review for managers, shifts and roster, leave/overtime/correction requests with approvals, history with hours worked |

## Screens
Login, Home (today, shift, security posture, recent activity), Clock in/out journey (device, location, face, record),
Identity enrolment, History, Requests, Team (managers: approvals, photo checks, enrolment confirmation), Profile.
Pull down on Home, History, Requests and Team to refresh and sync.

## Changes from the original UI project
- The fixed text ("Identity verified", "Device trusted", "HR-approved identity V1", "Software Development", a named user,
  "Accepted") is gone. Those labels now reflect live checks or server results.
- The simulated login, enrolment and attendance delays were replaced by real calls.
- Android: INTERNET permission added to the main manifest (release builds had no network), `allowBackup` off, `minSdk 24`,
  CAMERA and location permissions kept; unused BIOMETRIC permission removed.
- iOS: camera and location usage descriptions added (iOS closes the app without them).
- Removed the unused packages `local_auth`, `crypto`, `shared_preferences`, `uuid` (now used for punch ids), `image_picker`
  (the camera screen with the blink/head-turn check replaced it), and the unused `ApiClient`.
- Dart package renamed to `glo_eams_mobile`; the broken counter test was replaced with real unit tests; build output,
  IDE files and caches are not included.

## Run
```bash
flutter pub get
# set AppConfig.baseUrl in lib/core/config/app_config.dart
flutter devices        # pick an Android phone (USB debugging on) or an Android emulator
flutter run -d <device-id>   # NOT chrome or windows: the app needs Android or iOS
```
Run `dart run flutter_launcher_icons` to generate the app icons.
Backend: `e_attendance_api.zip` (ASP.NET Core + PostgreSQL, includes the HR web portal at `/portal/`) and `face_service.zip` (face matching container).
Dev logins on the API: `demo`, `shiftdemo`, `boss`.

## Before release (not done for you)
- Change the Android `applicationId` (`com.example.gloattendance`) and the iOS bundle identifier to your own.
- Add a release keystore: release builds are still signed with the debug key.
- iOS: after the first `flutter build ios`, set `platform :ios, '15.5'` in `ios/Podfile` (ML Kit needs it). Face checks need a real iPhone.
- The Android build toolchain in this project is very new (AGP 9, Gradle 9.3). If a plugin fails to build, run
  `flutter pub upgrade --major-versions` and send the error.
- Play Integrity / App Attest, push reminders, and the admin web dashboard are not built yet.

## Known limits
- The blink or head-turn check stops a held-up photo, but a replayed video could pass. Managers review flagged and sampled photos.
- Root and emulator detection runs on the phone and can be bypassed by a determined attacker; the server also flags suspicious punches.
- Photos of faces and face templates are personal data: consent wording, retention and a data protection impact assessment
  are needed before rollout. Staff see a notice at enrolment.

## Tests and CI
`flutter analyze && flutter test`. GitHub Actions (`.github/workflows/ci.yml`) or `azure-pipelines.yml` runs them on every push,
and builds a debug Android APK. Commit `pubspec.lock` once you have run `flutter pub get`.

## "Flutter Web engine failed to fetch assets/certs/server_ca.pem" or the app closes in Chrome
The app does not run in a browser (encrypted database, camera and device checks need Android or iOS). Run it on a phone or an Android
emulator. The `server_ca.pem` message was the optional certificate pinning looking for a file that is not there; pinning is now off by default
(`AppConfig.pinServerCertificate`).

## Who does what
- **Employees** use this app: clock in/out, history, requests, roster (shift staff).
- **Managers** use the Team tab in this app: approve requests, spot-check clock-in photos, and confirm their team's face enrolments.
- **HR** uses the web portal on the API (`/portal/`): defines and approves work locations, assigns people to them, handles enrolments nobody can confirm, audits manager approvals, and reads the audit trail.
The app never creates or approves locations. It only shows the approved ones assigned to you. Rule of thumb: the location tick is green only when you are inside an approved site.
