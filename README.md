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

---

## Setup on your laptop (VS Code + Android Studio emulator)

### 0. One-time prerequisites
1. Install the **Flutter SDK** and add `flutter/bin` to PATH.
2. Install **Android Studio** → SDK Manager: install an Android SDK, platform-tools, and
   create an emulator in Device Manager (pick a **Google APIs / Google Play** image).
3. In a terminal: `flutter doctor --android-licenses` (accept all), then `flutter doctor`
   until Flutter + Android toolchain are green.
4. In VS Code install the **Flutter** and **Dart** extensions.
5. Install **Node.js**, then `npm install -g firebase-tools`.

### 1. Open the project
Unzip, then in VS Code: **File → Open Folder →** the `science_signal` folder.
Open the VS Code terminal (Ctrl+`).

### 2. Generate the Android platform files (the zip contains only the code)
```bash
flutter create --platforms=android --project-name science_signal --org com.yourname .
```
`flutter create .` only adds the missing `android/` folder etc.; it does not overwrite `lib/` or `pubspec.yaml`.

### 3. Add dependencies (gets versions that match YOUR Flutter)
```bash
flutter pub add http firebase_core firebase_auth cloud_firestore
flutter pub get
```

### 4. Create the Firebase project (console.firebase.google.com)
Use a **separate project from Class A**.
1. Create project (Analytics not needed).
2. **Build → Authentication → Get started → Email/Password → Enable.**
3. **Authentication → Users → Add user:** create **user A** and **user B** (email + password; keep them private).
4. **Build → Firestore Database → Create database →** *Standard edition*, *Native mode*, **Production mode**, pick a region.

### 5. Connect the app to Firebase
```bash
firebase login
dart pub global activate flutterfire_cli
flutterfire configure
```
Choose your project and the **android** platform. This **overwrites `lib/firebase_options.dart`**
(and adds `android/app/google-services.json`).
If `flutterfire` is "not found", add the pub cache bin folder to PATH
(Windows: `%LOCALAPPDATA%\Pub\Cache\bin`, macOS/Linux: `$HOME/.pub-cache/bin`).

### 6. Deploy the rules (required)
```bash
firebase deploy --only firestore:rules --project YOUR_PROJECT_ID
```
Check the Rules tab in the console: you should see the owner-only rules, not test mode.

### 7. Android manifest + minSdk
* Open `android/app/src/main/AndroidManifest.xml` and add, just **above** `<application`:
  ```xml
  <uses-permission android:name="android.permission.INTERNET"/>
  ```
* If the build complains about `minSdkVersion`, in `android/app/build.gradle(.kts)` set
  `minSdk = 23` (Kotlin DSL) / `minSdkVersion 23` (Groovy).
* After any native change do a **full rebuild**: `flutter clean && flutter pub get`.

### 8. Run on the emulator
1. Start your emulator in Android Studio (Device Manager ▶).
2. In VS Code pick the device (bottom-right), then **Run and Debug → "Science Signal (DEV TOOLS on)" → F5**.
   Or in the terminal: `flutter run --dart-define=DEV_TOOLS=true`
3. Sign in as user A, answer five questions, tap **Finish → Submit score**.
   You should see **Cloud verified**, and the document in Firestore → Data →
   `users / {uid} / attempts / {roundId}`.

Run unit tests any time: `flutter test`

---

## How to produce each test (T01–T12, G01–G03)

DEV TOOLS must be on (bug icon in the app bar opens the DEV lab).

| Test | How |
|---|---|
| **T01** | Wrong password → visible `FirebaseAuthException` text. Right password → quiz loads; note user UID. |
| **T02** | Normal load. DEV lab event log shows an *encoded → decoded* pair (copy it for answer 1). |
| **T03** | DEV lab → arm *bad encoding*, *response_code 2*, *four results* one at a time → back → press Retry. Each shows a readable error and a rate-limited Retry. |
| **T04** | Tap a wrong answer, a right answer; try tapping again (disabled). Green/red banner has icon + text. |
| **T05** | Finish round → 5-row review and score. **Play again** → new round ID suffix, cleared answers. |
| **T06** | Submit, double-tap Submit (second tap is ignored). Console shows ONE doc with server timestamp; app shows **Cloud verified**. |
| **T07** | Fully stop the app, relaunch, sign in as same user → **history icon** → the same round suffix; tap the verified icon. |
| **T08** | Turn emulator **airplane mode ON** on the result screen → Submit → *Save status unknown*. Airplane OFF → **Check server** → (if absent) **Retry save (same ID)** → verified. Console shows one doc. |
| **T09** | DEV lab → *T09 verify: permission-denied* → Submit. Banner: *Write acknowledged; verification unavailable.* Then **Retry server read** → *Cloud verified*, same ID, one doc. |
| **T10** | Sign in as **B**. DEV lab → paste **A's UID** in Target → *Read path* and *Write valid doc* → both denied. |
| **T11** | As A (own UID): *Write score 6*, *Write extra field*, *Update existing* (use an existing round ID) → all rejected; console doc unchanged. |
| **T12** | DEV lab → arm *unavailable*, then *resource-exhausted* (one at a time) → Submit → distinct labels, bounded retries (5), no fake success. |
| **G01** | Two emulators/devices, **same user**, DEV lab → Concurrency: **same Round ID**, **different scores**, tick *Fire at next :00/:30* on both → press Commit on both. One shows `created`, other `COLLISION (not overwritten)`; console doc has exactly one payload. |
| **G02** | Same, but **different Round IDs** (use the dice). Each shows its own server doc; two docs in the console. |
| **G03** | DEV lab → *G03 sign out during verify* → Submit. Log: *external sign-out…* then *Stale verification response ignored*. Sign in as B: screen is a fresh round, A's result never appears. |

Second emulator: Android Studio → Device Manager → create another AVD, or run on a physical phone with USB debugging.

---

## Build the APK for submission
```bash
flutter build apk --release --dart-define=DEV_TOOLS=true
```
Output: `build/app/outputs/flutter-apk/app-release.apk` → rename to `ICA16_B_YourName.apk`
and install-test it (`adb install -r ...` or drag onto the emulator).
(With DEV_TOOLS on, the instructor can reproduce T03/T09/T12 injections. Without the flag
the lab is hidden. Say which you used in your README/evidence doc.)

If a signing error appears, check with your instructor before using a debug-signed build.

## Git repository
```bash
git init && git add . && git commit -m "ICA16 Class B Science Signal"
git branch -M main
git remote add origin https://github.com/YOU/ica16-class-b.git
git push -u origin main
```
Record the final commit hash (`git rev-parse --short HEAD`). Never commit passwords, tokens,
service-account / admin keys (`.gitignore` already blocks common ones). Make the repo accessible to the grader.

## Troubleshooting
* **"firebase_options.dart is still the placeholder"** → run step 5.
* **Sign-in works but writes fail with permission-denied** → rules not deployed to *this* project (step 6) or you are using Class A's project.
* **No internet on emulator** → manifest permission (step 7) + full rebuild.
* **Request rate-limited (response_code 5)** → wait 5+ s; the app never auto-retries.
* **Gradle / minSdk / Kotlin errors** → `flutter clean`, update Flutter (`flutter upgrade`), set `minSdk = 23`.
* **History list empty after a restart** → you must be signed in as the same user; list reads from the server.

## Academic integrity
You must disclose AI assistance and be able to explain every file and reproduce one failure
in the instructor check. Write the six answers and graduate analyses in your own words using your own run's evidence.
