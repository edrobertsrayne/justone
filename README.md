# Just One

A one-task-a-day chore app. It surfaces the single chore that matters most right now and mutes
everything else — the whole product personality is **restraint**. Built with Flutter + Firebase
(Cloud Firestore, Firebase Auth) and Riverpod.

This README focuses on **running the app locally against the Firebase Emulator Suite** for
hand-testing. For the product spec see `docs/design/HANDOFF.md`; for the build sequencing and
architecture decisions see `docs/IMPLEMENTATION-ROADMAP.md` and `docs/design/backend-decisions.md`.

---

## Prerequisites

| Tool | Notes |
|------|-------|
| **Flutter SDK** | Dart `^3.13` (see `pubspec.yaml` `environment:`). `flutter --version` should show a recent stable. |
| **Firebase CLI** | `npm i -g firebase-tools`. Provides the Emulator Suite. |
| **Java JDK 11+** | Required by the Firestore emulator. |
| A device/emulator to run on | Android emulator, iOS simulator, or `-d chrome` for web. |

The Firebase project is **`just-one-db69c`** (`.firebaserc`). You don't need access to it for
emulator-based local testing — the emulator runs entirely offline.

One-time install of Dart deps:

```bash
flutter pub get
```

---

## How the emulator wiring works

`lib/main.dart` points the app at the local emulators automatically **in debug builds**:

```dart
const kUseEmulator = bool.fromEnvironment('USE_EMULATOR', defaultValue: kDebugMode);
// ...
if (kUseEmulator) {
  await FirebaseAuth.instance.useAuthEmulator('localhost', 9099);
  FirebaseFirestore.instance.useFirestoreEmulator('localhost', 8080);
}
```

So `flutter run` (a debug build) talks to the emulator with no flags. Ports (from `firebase.json`):

| Service | Port |
|---------|------|
| Auth | `9099` |
| Firestore | `8080` |
| Emulator UI | `4000` (default) |

To force a build to talk to the **real** `just-one-db69c` project instead, pass
`--dart-define=USE_EMULATOR=false` (needed for real Google Sign-In and push — see the limitation
below).

---

## Picking a device (`-d <device>`)

Every `flutter run` below takes `-d <device>`. List what's attached with `flutter devices`. There
are three kinds of target, with one Android-only catch.

### Desktop / web — zero setup

`-d linux` (or `-d chrome`) runs on your machine, where `localhost` already *is* the emulator host,
so nothing extra is needed. This is the quickest smoke test.

### Android (phone **or** emulator) — needs `adb reverse`

The app points Firebase at `localhost:9099` / `:8080` (see "How the emulator wiring works" above).
On Android, `localhost` is the *device's own* loopback — not your machine — so a tethered phone or
an Android emulator can't reach the running Firebase emulator until you tunnel those two ports back
over adb:

```bash
adb reverse tcp:9099 tcp:9099   # Auth
adb reverse tcp:8080 tcp:8080   # Firestore
```

Run these once the device is connected, **and re-run them after any unplug/replug or emulator
restart**. Without them an Android target just hangs on a blank screen trying to reach an emulator
that isn't on the device.

`adb` ships with the Android SDK platform-tools. If it's not on your PATH:

```bash
export PATH="$PATH:$HOME/Android/Sdk/platform-tools"   # add to ~/.zshrc to persist
adb devices                                            # should list your target as "device"
```

**Emulated Android device:**

1. Create/launch an AVD — Android Studio's Device Manager, or `flutter emulators --launch <id>`
   (`flutter emulators` lists them).
2. Run the two `adb reverse` commands above.
3. `flutter run -t tool/seed_emulator.dart -d <emulator-id>` (or any of the run recipes below).

**Tethered Android phone (e.g. a Pixel 8):**

1. One-time on the phone: enable **Developer options** (Settings → About phone → tap **Build
   number** 7×), then turn on **USB debugging** (Settings → System → Developer options).
2. Plug in over USB and accept the **Allow USB debugging?** prompt on the phone (tick "always allow
   from this computer"). `adb devices` / `flutter devices` should now list it.
3. Run the two `adb reverse` commands above.
4. `flutter run -t tool/seed_emulator.dart -d <phone-id>` (or any of the run recipes below).

> For **real Google Sign-In and push notifications**, skip the emulator entirely and run against the
> live project with `--dart-define=USE_EMULATOR=false` — see the limitation below. `adb reverse` is
> not needed in that mode (there's no local emulator to reach).

---

## Run it locally against the emulator

### 1. Start the emulators

In one terminal, from the repo root:

```bash
firebase emulators:start
```

This serves Auth (`:9099`), Firestore (`:8080`), and the Emulator UI at <http://localhost:4000>.
Leave it running.

**On an Android phone or emulator?** Also run the two `adb reverse` commands from
[Picking a device](#picking-a-device--d-device) so the device can reach these ports. Desktop/web
targets need nothing extra.

### 2. Seed a user and launch into the daily loop (recommended)

The normal app entry point uses **real Google Sign-In**, which does not route through the Auth
emulator (Google OAuth is a live service — see the limitation below). For pure local testing there
is a dev-only entry point that signs in **anonymously** against the Auth emulator and writes a
ready-made, already-onboarded pool of sample chores, so you land straight on the daily card:

```bash
# in a second terminal, with the emulators still running
flutter run -t tool/seed_emulator.dart -d <device>
```

It prints the seeded `uid` and a handful of tasks. You can now exercise the daily loop, add/edit
(the `+` FAB), manage the pool (top-left menu), and settings (the gear in Manage). Inspect the
written data live in the Emulator UI at <http://localhost:4000/firestore>.

`tool/seed_emulator.dart` is **dev-only** — it is never shipped and nothing in `lib/` references it.

### 3. (Alternative) Run the full app, including first-run onboarding

```bash
flutter run -d <device>
```

This boots the real entry point (`lib/main.dart`) → welcome screen → first-run onboarding wizard →
daily loop. See the Google Sign-In limitation immediately below.

---

## Limitation: Google Sign-In vs. the Auth emulator

The welcome screen's **"Continue with Google"** uses the `google_sign_in` plugin, which obtains a
token from **live Google OAuth** — that handshake does not go through the Auth emulator. So the
full first-run flow (welcome → onboarding) is best exercised against the **real** project on a real
device:

```bash
flutter run --dart-define=USE_EMULATOR=false -d <device>
```

(This requires the platform Firebase config to be present — `android/app/google-services.json` is
committed; iOS needs its `GoogleService-Info.plist`.)

For everyday local development against the emulator, prefer the **seed entry point** (step 2),
which bypasses Google by using anonymous auth — it's the fast path to a populated, interactive app.

---

## Building an APK to sideload onto your phone

To hand-test on a phone **without** tethering it to your machine, build a standalone APK and copy it
across. A **release** build is the right choice here:

- It has `kDebugMode == false`, so `USE_EMULATOR` defaults to `false` — the APK talks to the **real**
  `just-one-db69c` project. No emulator and no `adb reverse` are needed, and real Google Sign-In and
  push work. (A debug APK would instead try to reach an emulator on the phone's own `localhost` and
  hang — see [Picking a device](#picking-a-device--d-device).)
- `android/app/build.gradle.kts` signs the release build with the **debug key**, so it builds and
  installs with no keystore setup. That's fine for personal sideloading; it is **not** suitable for
  the Play Store, which rejects debug-signed uploads.

Build it from the repo root:

```bash
flutter build apk --release
```

The APK lands at:

```
build/app/outputs/flutter-apk/app-release.apk
```

That single file is a "fat" APK containing every ABI (~simplest, a bit larger). To produce smaller
per-architecture APKs instead (a Pixel 8 needs the `arm64-v8a` one), add `--split-per-abi`; the
outputs land alongside it as `app-arm64-v8a-release.apk` etc.

### Getting it onto the phone

**Over USB (quickest if the phone is plugged in):**

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

`-r` reinstalls over an existing copy, keeping its data. Requires USB debugging (see the tethered-
phone setup under [Picking a device](#picking-a-device--d-device)).

**Without a cable:** copy `app-release.apk` to the phone (email it to yourself, a cloud drive,
Bluetooth, etc.), then tap it in the phone's file manager. Android will prompt you to allow
**installing unknown apps** for whichever app you opened the file from — grant it, then confirm the
install.

> Because a sideloaded release build hits the live project, first launch goes through the real
> welcome → Google Sign-In → onboarding flow. There's no seeded sample data — you're onboarding a
> real account against `just-one-db69c`.

---

## Running the tests

The test suite is **Dart-fakes-only** (`fake_cloud_firestore` + `firebase_auth_mocks`) and needs
**no emulator or device**:

```bash
flutter test
flutter analyze
```

---

## Verifying the security rules

The Dart fakes have no rules engine, so the owner-isolation rules (`firestore.rules`) are checked
**by hand against the emulator** whenever they change. Follow the step-by-step in
`docs/superpowers/phase-3-manual-rules-check.md` (uses the Emulator UI's Rules Playground).

---

## Not yet wired up

- **Push notifications / reminders.** The `functions/` directory (TypeScript Cloud Functions) and
  the FCM token registration / runtime permission flow are **Phase 6** and not implemented yet. The
  settings screen currently only *writes* the reminder schedule; nothing sends reminders. FCM and
  Cloud Scheduler can't be meaningfully emulated, so that work is verified on a real device against
  `just-one-db69c`.

---

## Project layout

```
lib/
  domain/   pure Dart: models, urgency curve, selection, routing, transitions, edits
  data/     Repository seam + Firestore/in-memory implementations + mappers
  app/      Riverpod providers + action controllers (daily/onboarding/pool/settings)
  auth/     Firebase Auth boundary, bootstrap, AuthGate
  ui/       screens + widgets (welcome, onboarding, daily, manage, settings, sheets)
  theme/    colour tokens, type scale, ThemeData
tool/       dev-only scripts (seed_emulator.dart)
functions/  Cloud Functions (Phase 6 — not active)
docs/       design spec, backend decisions, implementation roadmap, plans/specs
```
