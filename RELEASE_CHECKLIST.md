# Release checklist: GLO EAMS Mobile

Work through this before giving the app to anyone outside the pilot group.

## Build and identity
- [ ] `flutter pub get`, `flutter analyze` and `flutter test` are clean. Commit `pubspec.lock`.
- [ ] Android `applicationId` changed from `com.example.gloattendance` to your own (also move `MainActivity` to the matching package folder).
- [ ] iOS bundle identifier changed in Xcode; Apple team and provisioning set.
- [ ] Release keystore created and referenced in `android/app/build.gradle.kts` (release builds still use the debug key until you do this). Keep the keystore and passwords in your secret store.
- [ ] iOS: `platform :ios, '15.5'` in `ios/Podfile` after the first `flutter build ios`.
- [ ] If an Android plugin fails to build (the Gradle and AGP versions are very new), run `flutter pub upgrade --major-versions` and fix what it reports.
- [ ] `dart run flutter_launcher_icons` run with the official high-resolution logo in `assets/icon/`.

## Configuration
- [ ] `AppConfig.baseUrl` points at the production API over HTTPS.
- [ ] Optional: server CA certificate in `assets/certs/server_ca.pem` and `AppConfig.pinServerCertificate = true`.
- [ ] `AppConfig.faceMode` is `match` and the face service is running; or `selfie` if you chose photo-only.

## Pilot (4 to 6 weeks, about 300 staff across regular, shift and field)
- [ ] Locations created and approved by two HR officers in the portal; people assigned.
- [ ] Every pilot user has a manager; every manager has their own approver (or HR confirms them in the portal).
- [ ] Tune `Face:MatchThreshold` from real score data (see the face service README).
- [ ] Run the old attendance process in parallel for one pay cycle and reconcile.
- [ ] Load test the 08:00 rush (about 3,000 clock-ins in 15 minutes) against staging.
- [ ] Test on low-end Android phones, in poor light, with glasses, with no signal (offline queue), and after a lost-phone rebind.

## People and legal
- [ ] Data protection impact assessment for face data and clock-in photos; consent and notice wording approved by Legal and the DPO.
- [ ] Retention period agreed (the API deletes clock-in photos after `Storage:SelfieRetentionDays`, default 90).
- [ ] Staff and managers briefed on what is recorded, who can see photos, and how to ask HR to reset an enrolment.
- [ ] Independent penetration test completed and findings fixed.

## Known gaps (decide whether they block your release)
- Play Integrity (Android) and App Attest (iOS) are not built; root and emulator checks run on the phone and can be bypassed.
- The blink or head-turn check does not stop a replayed video; managers and HR review flagged and sampled photos.
- No push reminders for missed clock-outs.
