# Science Signal — ICA 16 / Class B (Flutter + OpenTDB + Firebase)

Five medium Science & Nature true/false questions from Open Trivia DB, scored in
Flutter, committed with a create-once Firestore transaction to
`users/{uid}/attempts/{roundId}` and confirmed with a **server-only** read.

## What is in this folder

| Path | Purpose |
|---|---|
| `lib/services/trivia_validator.dart` | Validates + decodes the OpenTDB response (`Uri.decodeComponent`) |
| `lib/services/trivia_service.dart` | HTTP GET, 10 s timeout, 5 s minimum gap, no auto-retry |
| `lib/services/attempt_repository.dart` | Transaction (create-once), server read, error mapping, dev fault hooks |
| `lib/state/quiz_controller.dart` | The state machine (all phases and guards) |
| `lib/screens/*` | Sign-in, quiz + review, saved attempts, DEV lab |
| `firestore.rules` | The owner-only rules from the assignment (deploy these) |
| `test/` | Unit tests for decoding/validation |
| `docs/STATE_DIAGRAM.md` | State machine diagram (use / redraw for your evidence doc) |
| `docs/EVIDENCE_TEMPLATE.md` | Test records T01–T12, G01–G03, answer outlines |


### 1. Android manifest + minSdk
* Open `android/app/src/main/AndroidManifest.xml` and add, just **above** `<application`:
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  ```
* If the build complains about `minSdkVersion`, in `android/app/build.gradle(.kts)` set
  `minSdk = 23` (Kotlin DSL) / `minSdkVersion 23` (Groovy).
* After any native change do a **full rebuild**: `flutter clean && flutter pub get`.

---

## Build the APK for submission
```bash
flutter build apk --release --dart-define=DEV_TOOLS=true
```

