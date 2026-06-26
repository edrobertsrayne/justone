# Phase 6 — Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the nudge layer — a scheduled Cloud Function that pushes escalating, opaque, conditional FCM reminders, plus the Flutter client plumbing (token registration, onboarding permission flow, Settings re-enable).

**Architecture:** Client gets a `MessagingService` seam (wraps `firebase_messaging`, faked in tests), one new `Repository.upsertDevice` method, a `RegistrationController`, and a `NotificationScope` mounted in the signed-in subtree; onboarding gains a 3rd rationale/permission step and Settings gains a re-enable card. Server is a single TS `onSchedule("every 15 minutes")` whose logic is a **pure `decideNotification(user, now)`** + a **pure `runScan(deps, now)`** orchestrator (both unit-tested with plain fakes), with a thin admin-SDK wiring in `index.ts`.

**Tech Stack:** Flutter + Riverpod (manual providers), `firebase_messaging` (already in `pubspec`), `fake_cloud_firestore`/`flutter_test`; TypeScript Firebase Functions v2, `firebase-admin`, jest + ts-jest.

## Global Constraints

- **YAGNI / simplest-thing-that-works**, files under ~1,000 lines (CLAUDE.md).
- **Repository seam grows by exactly one method this phase** (`upsertDevice`) — mirrors how `newTaskId()` was Phase 4's only addition.
- **No `permission_handler` dependency** — `firebase_messaging.requestPermission()` covers iOS + Android 13+.
- **Device doc id = the FCM token** (decision 4 in the spec). No new local-storage dependency.
- **Notification tap just opens the app** — no deep-link / `data` routing (decision 2).
- **Catch-up = jump to the latest passed beat** (decision 3), not literal per-run backfill.
- **FCM messages are notification-type** (`{ notification: { title, body } }`), opaque — the task name never leaves Firestore (D15).
- **Copy is server-owned**, parameterized by `index × streak`; `streak == 0` uses start-framing (decision 5). Title constant `"Clearing"`.
- **Stale user doc (`lastActiveDate` ≠ local today) is treated as cleared-for-today** (D1): `bankedToday=false`, `count=0`.
- **Real FCM send + Cloud Scheduler are NOT emulable** (D18) — covered by a documented manual device check, not automated tests.
- Real Firebase project id: **`just-one-db69c`** (from `firebase.json`).
- TDD throughout; commit after each task.

---

## Part A — Client (Dart / Flutter)

### Task A1: `Repository.upsertDevice` seam + mapper + both impls

**Files:**
- Modify: `lib/data/repository.dart` (add abstract method)
- Modify: `lib/data/firestore_mappers.dart` (add `deviceToFirestore`)
- Modify: `lib/data/firestore_repository.dart` (implement)
- Modify: `lib/data/in_memory_repository.dart` (implement + record list)
- Test: `test/data/firestore_repository_test.dart`, `test/data/in_memory_repository_test.dart`

**Interfaces:**
- Produces:
  - `abstract Repository.upsertDevice({required String token, required String platform, required DateTime now}) -> Future<void>`
  - `deviceToFirestore({required String token, required String platform, required DateTime now}) -> Map<String, dynamic>`
  - `InMemoryRepository.deviceUpserts -> List<({String token, String platform, DateTime now})>` (public, for assertions)

- [ ] **Step 1: Write the failing tests**

In `test/data/firestore_repository_test.dart`, add inside `main()`:

```dart
  test('upsertDevice writes a device doc keyed by token', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreRepository(db, 'u1');
    await repo.upsertDevice(token: 'tok-1', platform: 'android', now: DateTime(2026, 6, 26, 8));
    final snap = await db.doc('users/u1/devices/tok-1').get();
    expect(snap.data()!['token'], 'tok-1');
    expect(snap.data()!['platform'], 'android');
  });
```

In `test/data/in_memory_repository_test.dart`, add inside `main()`:

```dart
  test('upsertDevice records the upsert for assertions', () async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 26)),
      tasks: const [],
    );
    await repo.upsertDevice(token: 'tok-1', platform: 'android', now: DateTime(2026, 6, 26, 8));
    expect(repo.deviceUpserts.single.token, 'tok-1');
    expect(repo.deviceUpserts.single.platform, 'android');
  });
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/data/firestore_repository_test.dart test/data/in_memory_repository_test.dart`
Expected: FAIL — `upsertDevice` / `deviceUpserts` not defined.

- [ ] **Step 3: Add the abstract method**

In `lib/data/repository.dart`, add after the `newTaskId()` declaration:

```dart
  /// Upsert this device's FCM token into `users/{uid}/devices/{token}` (D4).
  /// Doc id is the token itself; dead tokens are pruned server-side.
  Future<void> upsertDevice({
    required String token,
    required String platform,
    required DateTime now,
  });
```

- [ ] **Step 4: Add the mapper**

In `lib/data/firestore_mappers.dart`, add at the end of the file:

```dart
// --- Device -> Firestore doc ---

Map<String, dynamic> deviceToFirestore({
  required String token,
  required String platform,
  required DateTime now,
}) => {
      'token': token,
      'platform': platform,
      'updatedAt': Timestamp.fromDate(now),
    };
```

- [ ] **Step 5: Implement on `FirestoreRepository`**

In `lib/data/firestore_repository.dart`, add after `newTaskId()`:

```dart
  @override
  Future<void> upsertDevice({
    required String token,
    required String platform,
    required DateTime now,
  }) =>
      _db.doc('users/$_uid/devices/$token').set(
            deviceToFirestore(token: token, platform: platform, now: now),
            SetOptions(merge: true),
          );
```

- [ ] **Step 6: Implement on `InMemoryRepository`**

In `lib/data/in_memory_repository.dart`, add a field near the other fields:

```dart
  final List<({String token, String platform, DateTime now})> deviceUpserts = [];
```

and the method after `newTaskId()`:

```dart
  @override
  Future<void> upsertDevice({
    required String token,
    required String platform,
    required DateTime now,
  }) async {
    deviceUpserts.add((token: token, platform: platform, now: now));
  }
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `flutter test test/data/firestore_repository_test.dart test/data/in_memory_repository_test.dart`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/data/ test/data/
git commit -m "feat(data): Repository.upsertDevice seam + device mapper (D4)"
```

---

### Task A2: `MessagingService` seam + `NotifPermission` + fake + provider

**Files:**
- Create: `lib/notifications/messaging_service.dart`
- Create: `test/support/fake_messaging_service.dart`
- Test: `test/notifications/messaging_service_test.dart`

**Interfaces:**
- Produces:
  - `enum NotifPermission { granted, denied, notDetermined }`
  - `abstract MessagingService { Future<NotifPermission> requestPermission(); Future<NotifPermission> permissionStatus(); Future<String?> getToken(); Stream<String> get onTokenRefresh; }`
  - `final messagingServiceProvider = Provider<MessagingService>(...)` (default: `FirebaseMessagingService`)
  - `FakeMessagingService({NotifPermission status, String? token, bool grantOnRequest})` with `int requestCount`, `void emitRefresh(String)`, `void dispose()`

- [ ] **Step 1: Write the seam + real impl + provider**

Create `lib/notifications/messaging_service.dart`:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runtime notification permission state, mapped off the platform's value.
enum NotifPermission { granted, denied, notDetermined }

/// The notification boundary: wraps `firebase_messaging`, which cannot run under
/// `flutter test`. Faked in tests (mirrors the AuthService seam).
abstract class MessagingService {
  /// Show the OS permission prompt; returns the resulting status.
  Future<NotifPermission> requestPermission();

  /// Current permission without prompting.
  Future<NotifPermission> permissionStatus();

  /// Current FCM registration token (null if unavailable).
  Future<String?> getToken();

  /// Fires when the token rotates.
  Stream<String> get onTokenRefresh;
}

class FirebaseMessagingService implements MessagingService {
  FirebaseMessagingService(this._fm);
  final FirebaseMessaging _fm;

  NotifPermission _map(AuthorizationStatus s) => switch (s) {
        AuthorizationStatus.authorized || AuthorizationStatus.provisional => NotifPermission.granted,
        AuthorizationStatus.denied => NotifPermission.denied,
        _ => NotifPermission.notDetermined,
      };

  @override
  Future<NotifPermission> requestPermission() async =>
      _map((await _fm.requestPermission()).authorizationStatus);

  @override
  Future<NotifPermission> permissionStatus() async =>
      _map((await _fm.getNotificationSettings()).authorizationStatus);

  @override
  Future<String?> getToken() => _fm.getToken();

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;
}

final messagingServiceProvider =
    Provider<MessagingService>((ref) => FirebaseMessagingService(FirebaseMessaging.instance));

/// Async permission status for the Settings re-enable card; invalidate after a
/// request to refresh.
final notifPermissionProvider =
    FutureProvider<NotifPermission>((ref) => ref.watch(messagingServiceProvider).permissionStatus());
```

- [ ] **Step 2: Write the fake**

Create `test/support/fake_messaging_service.dart`:

```dart
import 'dart:async';

import 'package:justone/notifications/messaging_service.dart';

class FakeMessagingService implements MessagingService {
  FakeMessagingService({
    this.status = NotifPermission.granted,
    this.token = 'tok-1',
    this.grantOnRequest = true,
  });

  NotifPermission status;
  String? token;
  bool grantOnRequest;
  int requestCount = 0;
  final _refresh = StreamController<String>.broadcast();

  @override
  Future<NotifPermission> requestPermission() async {
    requestCount++;
    status = grantOnRequest ? NotifPermission.granted : NotifPermission.denied;
    return status;
  }

  @override
  Future<NotifPermission> permissionStatus() async => status;

  @override
  Future<String?> getToken() async => token;

  @override
  Stream<String> get onTokenRefresh => _refresh.stream;

  void emitRefresh(String t) => _refresh.add(t);
  void dispose() => _refresh.close();
}
```

- [ ] **Step 3: Write the failing test**

Create `test/notifications/messaging_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/notifications/messaging_service.dart';

import '../support/fake_messaging_service.dart';

void main() {
  test('requestPermission flips a denied fake to granted and counts calls', () async {
    final fake = FakeMessagingService(status: NotifPermission.denied, grantOnRequest: true);
    addTearDown(fake.dispose);
    expect(await fake.permissionStatus(), NotifPermission.denied);
    expect(await fake.requestPermission(), NotifPermission.granted);
    expect(fake.requestCount, 1);
  });

  test('a denying fake stays denied after a request', () async {
    final fake = FakeMessagingService(status: NotifPermission.notDetermined, grantOnRequest: false);
    addTearDown(fake.dispose);
    expect(await fake.requestPermission(), NotifPermission.denied);
  });
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `flutter test test/notifications/messaging_service_test.dart`
Expected: PASS (the fake and seam compile; `firebase_messaging` is not exercised).

- [ ] **Step 5: Commit**

```bash
git add lib/notifications/messaging_service.dart test/support/fake_messaging_service.dart test/notifications/messaging_service_test.dart
git commit -m "feat(notifications): MessagingService seam + NotifPermission + fake"
```

---

### Task A3: `RegistrationController` + provider

**Files:**
- Create: `lib/notifications/registration_controller.dart`
- Test: `test/notifications/registration_controller_test.dart`

**Interfaces:**
- Consumes: `Repository.upsertDevice` (A1), `MessagingService`/`NotifPermission` (A2), `Clock` (`lib/app/providers.dart`).
- Produces:
  - `RegistrationController({required Repository repo, required MessagingService messaging, required Clock now, required String platform})`
  - `Future<NotifPermission> requestAndRegister()` — prompt; on grant save token; return status.
  - `Future<void> registerIfGranted()` — if already granted, save the current token.
  - `Future<void> saveToken(String token)` — upsert that token (used by refresh).
  - `final registrationControllerProvider = Provider<RegistrationController>(...)`

- [ ] **Step 1: Write the failing tests**

Create `test/notifications/registration_controller_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/notifications/messaging_service.dart';
import 'package:justone/notifications/registration_controller.dart';

import '../support/fake_messaging_service.dart';

InMemoryRepository _repo() => InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: DateTime(2026, 6, 26)),
      tasks: const [],
    );

RegistrationController _ctrl(InMemoryRepository repo, FakeMessagingService fake) =>
    RegistrationController(
      repo: repo,
      messaging: fake,
      now: () => DateTime(2026, 6, 26, 8),
      platform: 'android',
    );

void main() {
  test('registerIfGranted upserts the token when already granted', () async {
    final repo = _repo();
    final fake = FakeMessagingService(status: NotifPermission.granted, token: 'tok-1');
    addTearDown(fake.dispose);
    await _ctrl(repo, fake).registerIfGranted();
    expect(repo.deviceUpserts.single.token, 'tok-1');
  });

  test('registerIfGranted does nothing when not granted', () async {
    final repo = _repo();
    final fake = FakeMessagingService(status: NotifPermission.denied);
    addTearDown(fake.dispose);
    await _ctrl(repo, fake).registerIfGranted();
    expect(repo.deviceUpserts, isEmpty);
  });

  test('requestAndRegister grant path prompts, saves token, returns granted', () async {
    final repo = _repo();
    final fake = FakeMessagingService(status: NotifPermission.denied, grantOnRequest: true, token: 'tok-9');
    addTearDown(fake.dispose);
    final result = await _ctrl(repo, fake).requestAndRegister();
    expect(result, NotifPermission.granted);
    expect(fake.requestCount, 1);
    expect(repo.deviceUpserts.single.token, 'tok-9');
  });

  test('requestAndRegister deny path writes nothing', () async {
    final repo = _repo();
    final fake = FakeMessagingService(status: NotifPermission.notDetermined, grantOnRequest: false);
    addTearDown(fake.dispose);
    expect(await _ctrl(repo, fake).requestAndRegister(), NotifPermission.denied);
    expect(repo.deviceUpserts, isEmpty);
  });

  test('saveToken upserts directly (used by token refresh)', () async {
    final repo = _repo();
    final fake = FakeMessagingService();
    addTearDown(fake.dispose);
    await _ctrl(repo, fake).saveToken('tok-refreshed');
    expect(repo.deviceUpserts.single.token, 'tok-refreshed');
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/notifications/registration_controller_test.dart`
Expected: FAIL — `RegistrationController` not defined.

- [ ] **Step 3: Implement the controller**

Create `lib/notifications/registration_controller.dart`:

```dart
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../data/repository.dart';
import 'messaging_service.dart';

/// Owns the FCM token lifecycle: register on grant / app-open, and on rotation.
class RegistrationController {
  RegistrationController({
    required Repository repo,
    required MessagingService messaging,
    required Clock now,
    required String platform,
  })  : _repo = repo,
        _messaging = messaging,
        _now = now,
        _platform = platform;

  final Repository _repo;
  final MessagingService _messaging;
  final Clock _now;
  final String _platform;

  /// Prompt for permission; on grant, save the current token. Returns the status.
  Future<NotifPermission> requestAndRegister() async {
    final status = await _messaging.requestPermission();
    if (status == NotifPermission.granted) await _saveCurrentToken();
    return status;
  }

  /// App-open path: refresh the device doc only if permission is already granted.
  Future<void> registerIfGranted() async {
    if (await _messaging.permissionStatus() == NotifPermission.granted) {
      await _saveCurrentToken();
    }
  }

  /// Upsert a specific token (used by the onTokenRefresh subscription).
  Future<void> saveToken(String token) =>
      _repo.upsertDevice(token: token, platform: _platform, now: _now());

  Future<void> _saveCurrentToken() async {
    final token = await _messaging.getToken();
    if (token != null) await saveToken(token);
  }
}

final registrationControllerProvider = Provider<RegistrationController>(
  (ref) => RegistrationController(
    repo: ref.watch(repositoryProvider),
    messaging: ref.watch(messagingServiceProvider),
    now: ref.watch(nowProvider),
    platform: defaultTargetPlatform.name,
  ),
);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/notifications/registration_controller_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/notifications/registration_controller.dart test/notifications/registration_controller_test.dart
git commit -m "feat(notifications): RegistrationController (token lifecycle)"
```

---

### Task A4: `NotificationScope` + mount in AuthGate

**Files:**
- Create: `lib/notifications/notification_scope.dart`
- Modify: `lib/auth/auth_gate.dart:28` (wrap `HomeRouter`)
- Test: `test/notifications/notification_scope_test.dart`

**Interfaces:**
- Consumes: `registrationControllerProvider` (A3), `messagingServiceProvider` (A2).
- Produces: `class NotificationScope extends ConsumerStatefulWidget { const NotificationScope({super.key, required Widget child}); }`

- [ ] **Step 1: Write the failing tests**

Create `test/notifications/notification_scope_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/notifications/messaging_service.dart';
import 'package:justone/notifications/notification_scope.dart';

import '../support/fake_messaging_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 26, 8);

  Future<InMemoryRepository> pump(WidgetTester tester, FakeMessagingService fake) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now, onboardingComplete: true),
      tasks: const [],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
        messagingServiceProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: NotificationScope(child: SizedBox())),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('registers the token on mount when granted', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.granted, token: 'tok-1');
    addTearDown(fake.dispose);
    final repo = await pump(tester, fake);
    expect(repo.deviceUpserts.single.token, 'tok-1');
  });

  testWidgets('does not register on mount when not granted', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.denied);
    addTearDown(fake.dispose);
    final repo = await pump(tester, fake);
    expect(repo.deviceUpserts, isEmpty);
  });

  testWidgets('upserts on a token refresh', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.granted, token: 'tok-1');
    addTearDown(fake.dispose);
    final repo = await pump(tester, fake);
    fake.emitRefresh('tok-2');
    await tester.pumpAndSettle();
    expect(repo.deviceUpserts.map((d) => d.token), contains('tok-2'));
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/notifications/notification_scope_test.dart`
Expected: FAIL — `NotificationScope` not defined.

- [ ] **Step 3: Implement the scope**

Create `lib/notifications/notification_scope.dart`:

```dart
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'messaging_service.dart';
import 'registration_controller.dart';

/// Registers the FCM token for the signed-in session: once on mount (if already
/// granted) and on every token rotation. Sibling of [DailyResetScope]. It never
/// requests permission — that is user-initiated (onboarding / Settings).
class NotificationScope extends ConsumerStatefulWidget {
  const NotificationScope({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<NotificationScope> createState() => _NotificationScopeState();
}

class _NotificationScopeState extends ConsumerState<NotificationScope> {
  StreamSubscription<String>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(registrationControllerProvider).registerIfGranted();
    });
    _sub = ref.read(messagingServiceProvider).onTokenRefresh.listen(
          (token) => ref.read(registrationControllerProvider).saveToken(token),
        );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
```

- [ ] **Step 4: Mount it in the AuthGate**

In `lib/auth/auth_gate.dart`, add the import near the other `ui`/`app` imports:

```dart
import '../notifications/notification_scope.dart';
```

and change the signed-in `data:` line (currently `data: (_) => const DailyResetScope(child: HomeRouter()),`) to:

```dart
                  data: (_) => const DailyResetScope(
                    child: NotificationScope(child: HomeRouter()),
                  ),
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/notifications/notification_scope_test.dart test/auth/auth_gate_test.dart`
Expected: PASS. (If `auth_gate_test` pumps the signed-in branch, it now renders `NotificationScope`; the real `messagingServiceProvider` is never reached in those tests because they stop before the data branch or override the repo — confirm it still passes; if it newly needs a `messagingServiceProvider` override, add `messagingServiceProvider.overrideWithValue(FakeMessagingService())` to that test's overrides.)

- [ ] **Step 6: Commit**

```bash
git add lib/notifications/notification_scope.dart lib/auth/auth_gate.dart test/notifications/notification_scope_test.dart test/auth/auth_gate_test.dart
git commit -m "feat(notifications): NotificationScope mounts token registration"
```

---

### Task A5: Onboarding rationale + permission step (D14)

**Files:**
- Modify: `lib/ui/onboarding_flow.dart` (add `_step == 2` rationale screen; re-route "Start Just One")
- Test: `test/ui/onboarding_flow_test.dart` (update existing flow; add permission-path tests)

**Interfaces:**
- Consumes: `registrationControllerProvider.requestAndRegister()` (A3); existing `OnboardingController.finish` via `_finish()`.

- [ ] **Step 1: Update + add the failing tests**

Replace the body of `test/ui/onboarding_flow_test.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/notifications/messaging_service.dart';
import 'package:justone/ui/daily_screen.dart';
import 'package:justone/ui/home_router.dart';

import '../support/fake_messaging_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  Future<(InMemoryRepository, FakeMessagingService)> pumpToRationale(
    WidgetTester tester, {
    required bool grantOnRequest,
  }) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now), // onboardingComplete:false
      tasks: const [],
    );
    final fake = FakeMessagingService(status: NotifPermission.notDetermined, grantOnRequest: grantOnRequest, token: 'tok-1');
    addTearDown(fake.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
        messagingServiceProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: HomeRouter()),
    ));
    await tester.pump();
    await tester.tap(find.text('Continue')); // step 0 -> 1
    await tester.pump();
    await tester.tap(find.text('Dishes')); // pick a chore
    await tester.pump();
    await tester.tap(find.text('Start Just One')); // step 1 -> 2 (rationale)
    await tester.pump();
    return (repo, fake);
  }

  // DailyScreen animates (halo), so pumpAndSettle would hang — pump a bounded
  // number of finite frames to flush the async permission + commit + re-route.
  Future<void> settleBounded(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('"Turn on reminders" prompts, registers, lands on daily', (tester) async {
    final (repo, fake) = await pumpToRationale(tester, grantOnRequest: true);
    expect(find.text('Turn on reminders'), findsOneWidget);
    await tester.tap(find.text('Turn on reminders'));
    await settleBounded(tester);
    expect(fake.requestCount, 1);
    expect(repo.deviceUpserts.single.token, 'tok-1');
    expect(find.byType(DailyScreen), findsOneWidget);
  });

  testWidgets('"Not now" skips the prompt and still lands on daily', (tester) async {
    final (repo, fake) = await pumpToRationale(tester, grantOnRequest: true);
    await tester.tap(find.text('Not now'));
    await settleBounded(tester);
    expect(fake.requestCount, 0);
    expect(repo.deviceUpserts, isEmpty);
    expect(find.byType(DailyScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/ui/onboarding_flow_test.dart`
Expected: FAIL — no "Turn on reminders"/"Not now" text; "Start Just One" currently finishes instead of advancing.

- [ ] **Step 3: Re-route "Start Just One" to the rationale step**

In `lib/ui/onboarding_flow.dart`, in `_buildAdd()`, change the final primary button line
(currently `_primary('Start Just One', _titles.isEmpty || _submitting ? null : _finish),`) to:

```dart
        _primary('Start Just One', _titles.isEmpty || _submitting ? null : () => setState(() => _step = 2)),
```

- [ ] **Step 4: Render the rationale step**

In `lib/ui/onboarding_flow.dart`, change `build()`'s child selector
(currently `child: _step == 0 ? _buildTarget() : _buildAdd(),`) to:

```dart
          child: switch (_step) {
            0 => _buildTarget(),
            1 => _buildAdd(),
            _ => _buildRationale(),
          },
```

Add the `_buildRationale()` method (after `_buildAdd()`), plus the import at the top:

```dart
import '../notifications/registration_controller.dart';
```

```dart
  Future<void> _enableThenFinish() async {
    if (_submitting) return;
    await ref.read(registrationControllerProvider).requestAndRegister();
    await _finish();
  }

  Widget _buildRationale() {
    return Column(
      children: [
        Row(children: [
          GestureDetector(
            onTap: () => setState(() => _step = 1),
            child: const Icon(Icons.chevron_left, color: Color(0xFF6F6A60)),
          ),
          const Spacer(),
          _eyebrow('Last step'),
          const Spacer(),
          const SizedBox(width: 24),
        ]),
        const Spacer(),
        Text('STAY ON TRACK',
            style: TypeScale.sans(11.1, weight: FontWeight.w700, letterSpacing: 2.4, color: Palette.accent)),
        const SizedBox(height: 14),
        Text('A gentle nudge, never a nag.',
            textAlign: TextAlign.center,
            style: TypeScale.serif(28.4, weight: FontWeight.w500, color: Palette.ink)),
        const SizedBox(height: 12),
        SizedBox(
          width: 250,
          child: Text(
            "Reminders are the whole point — a quiet beat so today doesn't slip. Change or silence them anytime in settings.",
            textAlign: TextAlign.center,
            style: TypeScale.sans(14, height: 1.55, color: Palette.muted),
          ),
        ),
        const Spacer(),
        _primary('Turn on reminders', _submitting ? null : _enableThenFinish),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: _submitting ? null : _finish,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('Not now',
                style: TypeScale.sans(13, weight: FontWeight.w700, color: const Color(0xFF8A847A))),
          ),
        ),
      ],
    );
  }
```

Note: `_finish()` already guards `_submitting` and flips `onboardingComplete`, which re-routes to daily; no other change needed.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/ui/onboarding_flow_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/ui/onboarding_flow.dart test/ui/onboarding_flow_test.dart
git commit -m "feat(onboarding): rationale + permission step (D14)"
```

---

### Task A6: Settings re-enable card (D14)

**Files:**
- Modify: `lib/ui/settings_screen.dart` (top-of-list card when not granted)
- Test: `test/ui/settings_screen_test.dart`

**Interfaces:**
- Consumes: `notifPermissionProvider` (A2), `registrationControllerProvider.requestAndRegister()` (A3).

**Note (deviation from spec A5, intentional):** the card always calls `requestAndRegister()`. When the OS won't re-prompt (permanent denial), the card carries a one-line "enable in system settings" instruction rather than programmatically opening OS settings — that keeps us off any new dependency (`firebase_messaging` has no open-settings API). Record this in the roadmap wrap-up.

- [ ] **Step 1: Write the failing tests**

Add to `test/ui/settings_screen_test.dart` — extend the imports and `pump` helper to inject the messaging fake, then add two tests. Replace the file's `pump` with this overload and add the tests:

```dart
import 'package:justone/notifications/messaging_service.dart';
import '../support/fake_messaging_service.dart';

  Future<InMemoryRepository> pumpWith(WidgetTester tester, FakeMessagingService fake) async {
    final repo = InMemoryRepository(
      user: UserState(
        timezone: 'UTC', target: 3, lastActiveDate: now, onboardingComplete: true,
        remindersWeekday: const ['08:00', '18:30'], remindersWeekend: const ['10:00'],
      ),
      tasks: const [],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
        messagingServiceProvider.overrideWithValue(fake),
      ],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('shows the re-enable card when notifications are not granted', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.denied, grantOnRequest: true);
    addTearDown(fake.dispose);
    final repo = await pumpWith(tester, fake);
    expect(find.byKey(const ValueKey('reenable-reminders')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reenable-reminders')));
    await tester.pumpAndSettle();
    expect(fake.requestCount, 1);
    expect(repo.deviceUpserts, isNotEmpty);
    expect(find.byKey(const ValueKey('reenable-reminders')), findsNothing); // refreshed -> granted -> gone
  });

  testWidgets('hides the re-enable card when granted', (tester) async {
    final fake = FakeMessagingService(status: NotifPermission.granted);
    addTearDown(fake.dispose);
    await pumpWith(tester, fake);
    expect(find.byKey(const ValueKey('reenable-reminders')), findsNothing);
  });
```

The two pre-existing tests still use the old `pump` helper (no messaging override). Add `messagingServiceProvider.overrideWithValue(FakeMessagingService(status: NotifPermission.granted))` to the existing `pump` helper's overrides so the granted-by-default state hides the card and those tests are unaffected. Remember to `import` and dispose are handled per-test.

- [ ] **Step 2: Run them to verify they fail**

Run: `flutter test test/ui/settings_screen_test.dart`
Expected: FAIL — no `reenable-reminders` widget.

- [ ] **Step 3: Render the card**

In `lib/ui/settings_screen.dart`, add imports:

```dart
import '../notifications/messaging_service.dart';
import '../notifications/registration_controller.dart';
```

In `build()`, after `final list = _activeList(user);`, read the permission async value:

```dart
    final perm = ref.watch(notifPermissionProvider).value;
```

Then, as the **first** child of the `ListView` (before the daily-target `_card(...)`), insert:

```dart
                  if (perm != null && perm != NotifPermission.granted) ...[
                    _reEnableCard(),
                    const SizedBox(height: 12),
                  ],
```

Add the method to `_SettingsScreenState`:

```dart
  Widget _reEnableCard() => GestureDetector(
        key: const ValueKey('reenable-reminders'),
        onTap: () async {
          await ref.read(registrationControllerProvider).requestAndRegister();
          ref.invalidate(notifPermissionProvider);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
          decoration: BoxDecoration(
            color: Palette.accent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Icon(Icons.notifications_off_outlined, size: 20, color: Color(0xFFFBF9F4)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Reminders are off',
                    style: TypeScale.sans(14, weight: FontWeight.w700, color: const Color(0xFFFBF9F4))),
                const SizedBox(height: 3),
                Text('Tap to turn them on. If nothing happens, enable notifications for Just One in system settings.',
                    style: TypeScale.sans(11.1, height: 1.4, color: const Color(0xFFEDEFE8))),
              ]),
            ),
          ]),
        ),
      );
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ui/settings_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/ui/settings_screen.dart test/ui/settings_screen_test.dart
git commit -m "feat(settings): prominent reminders re-enable card (D14)"
```

---

### Task A7: Full client suite green

- [ ] **Step 1: Run the whole Flutter suite**

Run: `flutter test`
Expected: PASS, all green (≈154 prior + the new notification/onboarding/settings tests).

- [ ] **Step 2: Analyze**

Run: `flutter analyze`
Expected: No issues. Fix any lints introduced.

- [ ] **Step 3: Commit (only if Step 2 required edits)**

```bash
git add -A && git commit -m "chore(notifications): client suite green + analyze clean"
```

---

## Part B — Server (TypeScript Cloud Function)

> All `npm` commands run from the `functions/` directory.

### Task B1: Functions tooling + `fields.ts` + `localParts`

**Files:**
- Modify: `functions/tsconfig.json` (→ CommonJS, simplest jest/build path)
- Modify: `functions/package.json` (add `test` script + dev deps)
- Create: `functions/jest.config.js`
- Create: `functions/.eslintrc.js`
- Create: `functions/src/fields.ts`
- Create: `functions/src/time.ts`
- Test: `functions/src/time.test.ts`

**Interfaces:**
- Produces:
  - `interface ReminderMap { weekday: string[]; weekend: string[]; }`
  - `interface UserDoc { timezone: string; reminders?: ReminderMap; streak?: number; bankedToday?: boolean; lastActiveDate?: string; lastNotified?: { date: string; count: number }; }`
  - `interface LocalParts { date: string; minutes: number; isWeekend: boolean; }`
  - `function localParts(timezone: string, now: Date): LocalParts`
  - `function parseHM(s: string): number`

**Why CommonJS:** the scaffold's NodeNext/ESM setting forces `.js` import suffixes and an ESM jest config — both avoidable friction. Functions v2 runs CommonJS fine; switching removes a whole class of config pain (YAGNI).

- [ ] **Step 1: Switch tsconfig to CommonJS**

In `functions/tsconfig.json`, change the two module lines to:

```json
    "module": "commonjs",
    "moduleResolution": "node",
```

(Leave `target`, `strict`, `outDir`, `rootDir`, etc. as-is.)

- [ ] **Step 2: Install dev dependencies**

Run: `npm --prefix functions install -D jest ts-jest @types/jest`
Expected: installs without error; `functions/package.json` devDependencies now include them.

- [ ] **Step 3: Add the test script**

In `functions/package.json`, add to `scripts`:

```json
    "test": "jest",
```

- [ ] **Step 4: Add jest config**

Create `functions/jest.config.js`:

```js
module.exports = {
  preset: "ts-jest",
  testEnvironment: "node",
  testMatch: ["**/*.test.ts"],
};
```

- [ ] **Step 5: Add a working eslint config**

Create `functions/.eslintrc.js` (so `npm run lint` / predeploy works; relaxed where google's defaults fight TS):

```js
module.exports = {
  root: true,
  env: { es6: true, node: true },
  parser: "@typescript-eslint/parser",
  parserOptions: { ecmaVersion: 2020, sourceType: "module" },
  extends: ["eslint:recommended", "plugin:@typescript-eslint/recommended"],
  plugins: ["@typescript-eslint", "import"],
  ignorePatterns: ["lib/**", "node_modules/**", "*.test.ts", "jest.config.js", ".eslintrc.js"],
  rules: {
    "quotes": ["error", "double"],
    "max-len": ["error", { code: 110 }],
    "@typescript-eslint/no-explicit-any": "off",
  },
};
```

- [ ] **Step 6: Write the failing test**

Create `functions/src/time.test.ts`:

```ts
import { localParts, parseHM } from "./fields";

describe("parseHM", () => {
  it("converts HH:mm to minutes", () => {
    expect(parseHM("08:00")).toBe(480);
    expect(parseHM("21:30")).toBe(1290);
  });
});

describe("localParts", () => {
  it("derives London wall-clock + date from UTC instant", () => {
    // 2026-06-26 07:30 UTC -> 08:30 BST (London is UTC+1 in summer).
    const lp = localParts("Europe/London", new Date("2026-06-26T07:30:00Z"));
    expect(lp.date).toBe("2026-06-26");
    expect(lp.minutes).toBe(8 * 60 + 30);
    expect(lp.isWeekend).toBe(false); // 26 Jun 2026 is a Friday
  });

  it("flags weekend by local day-of-week", () => {
    const lp = localParts("Europe/London", new Date("2026-06-27T10:00:00Z"));
    expect(lp.isWeekend).toBe(true); // Saturday
  });

  it("rolls the local date across a timezone boundary", () => {
    // 23:30 UTC is already next-day 08:30 in Tokyo (UTC+9).
    const lp = localParts("Asia/Tokyo", new Date("2026-06-26T23:30:00Z"));
    expect(lp.date).toBe("2026-06-27");
    expect(lp.minutes).toBe(8 * 60 + 30);
  });
});
```

- [ ] **Step 7: Run it to verify it fails**

Run: `npm --prefix functions test`
Expected: FAIL — `./fields` has no `localParts`/`parseHM`.

- [ ] **Step 8: Implement `fields.ts`**

Create `functions/src/fields.ts`:

```ts
export interface ReminderMap {
  weekday: string[];
  weekend: string[];
}

/** The subset of the user doc the notification function reads (mirrors the
 * canonical model in docs/design/backend-decisions.md). */
export interface UserDoc {
  timezone: string;
  reminders?: ReminderMap;
  streak?: number;
  bankedToday?: boolean;
  lastActiveDate?: string; // "YYYY-MM-DD"
  lastNotified?: { date: string; count: number };
}

export interface LocalParts {
  date: string; // "YYYY-MM-DD" in the user's tz
  minutes: number; // minutes since local midnight (0..1439)
  isWeekend: boolean; // local Sat/Sun
}

/** Wall-clock minutes for an "HH:mm" reminder string. */
export function parseHM(s: string): number {
  const [h, m] = s.split(":").map((x) => parseInt(x, 10));
  return h * 60 + m;
}

/** DST-correct local date/time-of-day/weekday from an IANA tz, using the
 * built-in Intl API (no luxon/moment-timezone dependency). */
export function localParts(timezone: string, now: Date): LocalParts {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    weekday: "short",
  });
  const parts: Record<string, string> = {};
  for (const p of fmt.formatToParts(now)) parts[p.type] = p.value;
  let hour = parseInt(parts.hour, 10);
  if (hour === 24) hour = 0; // some engines render local midnight as "24"
  const minutes = hour * 60 + parseInt(parts.minute, 10);
  const date = `${parts.year}-${parts.month}-${parts.day}`;
  const isWeekend = parts.weekday === "Sat" || parts.weekday === "Sun";
  return { date, minutes, isWeekend };
}
```

- [ ] **Step 9: Run test + build to verify**

Run: `npm --prefix functions test && npm --prefix functions run build`
Expected: PASS; build emits to `functions/lib` with no errors.

- [ ] **Step 10: Commit**

```bash
git add functions/tsconfig.json functions/package.json functions/package-lock.json functions/jest.config.js functions/.eslintrc.js functions/src/fields.ts functions/src/time.test.ts
git commit -m "chore(functions): jest+eslint+CommonJS tooling; fields.ts + localParts"
```

---

### Task B2: `copyFor` — server-owned escalation copy

**Files:**
- Create: `functions/src/copy.ts`
- Test: `functions/src/copy.test.ts`

**Interfaces:**
- Produces:
  - `interface Copy { title: string; body: string; }`
  - `function copyFor(args: { isFinal: boolean; streak: number }): Copy`

- [ ] **Step 1: Write the failing test**

Create `functions/src/copy.test.ts`:

```ts
import { copyFor } from "./copy";

describe("copyFor", () => {
  it("gentle beat names the streak", () => {
    const c = copyFor({ isFinal: false, streak: 5 });
    expect(c.title).toBe("Clearing");
    expect(c.body).toContain("5-day streak");
    expect(c.body).not.toMatch(/ends/i);
  });

  it("final beat states the real stakes", () => {
    const c = copyFor({ isFinal: true, streak: 5 });
    expect(c.body).toContain("5-day streak");
    expect(c.body).toMatch(/ends/i);
  });

  it("streak-0 uses start-framing, never 'N-day streak'", () => {
    const gentle = copyFor({ isFinal: false, streak: 0 });
    const fin = copyFor({ isFinal: true, streak: 0 });
    expect(gentle.body).not.toMatch(/streak/i);
    expect(fin.body).not.toMatch(/-day streak/i);
    expect(fin.body).toMatch(/one task/i);
  });
});
```

- [ ] **Step 2: Run it to verify it fails**

Run: `npm --prefix functions test -- copy`
Expected: FAIL — `./copy` not found.

- [ ] **Step 3: Implement `copy.ts`**

Create `functions/src/copy.ts`:

```ts
export interface Copy {
  title: string;
  body: string;
}

/** Opaque, escalating nudge copy (D5/D15) — never names the task. `isFinal` is
 * the last configured reminder of the day (real stakes); earlier beats are
 * gentle and near-identical. `streak === 0` has nothing to lose, so it uses
 * start-framing instead of "your N-day streak ends". */
export function copyFor(args: { isFinal: boolean; streak: number }): Copy {
  const { isFinal, streak } = args;
  const title = "Clearing";
  if (streak <= 0) {
    return {
      title,
      body: isFinal
        ? "Today's still open. One task is all it takes."
        : "A small first task and today's done.",
    };
  }
  if (isFinal) {
    return {
      title,
      body: `Your ${streak}-day streak ends if today stays empty. One task is all it takes.`,
    };
  }
  return { title, body: `One small thing keeps your ${streak}-day streak going.` };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm --prefix functions test -- copy`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/copy.ts functions/src/copy.test.ts
git commit -m "feat(functions): server-owned escalation copy (D5/D15)"
```

---

### Task B3: `decideNotification` — the pure core

**Files:**
- Create: `functions/src/decide.ts`
- Test: `functions/src/decide.test.ts`

**Interfaces:**
- Consumes: `UserDoc`, `localParts`, `parseHM` (B1); `copyFor` (B2).
- Produces:
  - `type Decision = { send: false } | { send: true; index: number; count: number; title: string; body: string }`
  - `function decideNotification(user: UserDoc, now: Date): Decision`

- [ ] **Step 1: Write the failing tests**

Create `functions/src/decide.test.ts`:

```ts
import { decideNotification } from "./decide";
import { UserDoc } from "./fields";

// All instants are UTC; tz is UTC so wall-clock == UTC here.
function user(overrides: Partial<UserDoc> = {}): UserDoc {
  return {
    timezone: "UTC",
    reminders: { weekday: ["08:00", "18:30", "21:00"], weekend: ["10:00"] },
    streak: 5,
    bankedToday: false,
    lastActiveDate: "2026-06-26", // Friday
    ...overrides,
  };
}
const at = (hm: string) => new Date(`2026-06-26T${hm}:00Z`);

describe("decideNotification", () => {
  it("sends the first beat once its time has passed", () => {
    const d = decideNotification(user(), at("08:01"));
    expect(d).toMatchObject({ send: true, index: 0, count: 1 });
  });

  it("does not send before any reminder time", () => {
    expect(decideNotification(user(), at("07:59"))).toEqual({ send: false });
  });

  it("is idempotent — a second run after sending stays silent", () => {
    const u = user({ lastNotified: { date: "2026-06-26", count: 1 } });
    expect(decideNotification(u, at("08:10"))).toEqual({ send: false });
  });

  it("jumps to the latest passed beat (no backfill burst)", () => {
    // 21:05, nothing sent today -> send the final beat (index 2), cover all three.
    const d = decideNotification(user({ lastNotified: { date: "2026-06-25", count: 3 } }), at("21:05"));
    expect(d).toMatchObject({ send: true, index: 2, count: 3 });
    if (d.send) expect(d.body).toMatch(/ends/i); // final-beat copy
  });

  it("suppresses when the streak is already secured today", () => {
    expect(decideNotification(user({ bankedToday: true }), at("21:05"))).toEqual({ send: false });
  });

  it("treats a stale doc as cleared-for-today (D1)", () => {
    // bankedToday true but from yesterday -> still nudge; count resets to 0.
    const u = user({ bankedToday: true, lastActiveDate: "2026-06-25" });
    expect(decideNotification(u, at("08:30"))).toMatchObject({ send: true, index: 0 });
  });

  it("uses the weekend array on weekends", () => {
    // 2026-06-27 is Saturday; weekend = ["10:00"].
    const u = user();
    const sat = (hm: string) => new Date(`2026-06-27T${hm}:00Z`);
    expect(decideNotification(u, sat("09:59"))).toEqual({ send: false });
    expect(decideNotification(u, sat("10:01"))).toMatchObject({ send: true, index: 0, count: 1 });
  });

  it("never sends when the active array is empty", () => {
    const u = user({ reminders: { weekday: [], weekend: [] } });
    expect(decideNotification(u, at("23:59"))).toEqual({ send: false });
  });
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `npm --prefix functions test -- decide`
Expected: FAIL — `./decide` not found.

- [ ] **Step 3: Implement `decide.ts`**

Create `functions/src/decide.ts`:

```ts
import { copyFor } from "./copy";
import { localParts, parseHM, UserDoc } from "./fields";

export type Decision =
  | { send: false }
  | { send: true; index: number; count: number; title: string; body: string };

/** Pure decision core (D1/D3/D5/D17): given a user doc and the current instant,
 * decide whether to send a nudge and which escalation beat. No I/O. */
export function decideNotification(user: UserDoc, now: Date): Decision {
  const lp = localParts(user.timezone, now);

  // D1: a doc whose lastActiveDate isn't local-today rolled over server-side
  // without an app open — treat today's flags/count as cleared.
  const fresh = user.lastActiveDate === lp.date;
  const banked = fresh && user.bankedToday === true;
  if (banked) return { send: false }; // streak secured -> suppress the rest

  const reminders = (lp.isWeekend ? user.reminders?.weekend : user.reminders?.weekday) ?? [];
  if (reminders.length === 0) return { send: false };

  const times = reminders.map(parseHM).sort((a, b) => a - b);
  let passedCount = 0;
  for (const t of times) if (t <= lp.minutes) passedCount++;
  if (passedCount === 0) return { send: false };

  const sentCount =
    user.lastNotified && user.lastNotified.date === lp.date ? user.lastNotified.count : 0;
  if (passedCount <= sentCount) return { send: false };

  // Jump to the latest passed beat; cover the skipped earlier ones so they
  // don't backfill on subsequent runs.
  const index = passedCount - 1;
  const isFinal = index === times.length - 1;
  const { title, body } = copyFor({ isFinal, streak: user.streak ?? 0 });
  return { send: true, index, count: passedCount, title, body };
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm --prefix functions test -- decide`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/decide.ts functions/src/decide.test.ts
git commit -m "feat(functions): pure decideNotification core (D1/D3/D5/D17)"
```

---

### Task B4: `runScan` — the I/O orchestrator (dependency-injected)

**Files:**
- Create: `functions/src/scan.ts`
- Test: `functions/src/scan.test.ts`

**Interfaces:**
- Consumes: `decideNotification` (B3), `localParts` (B1), `UserDoc` (B1).
- Produces:
  - `type SendResult = "ok" | "invalid-token" | "error"`
  - `interface ScanDeps { listUsers(): Promise<Array<{ uid: string; user: UserDoc }>>; listDeviceTokens(uid: string): Promise<string[]>; send(token: string, copy: { title: string; body: string }): Promise<SendResult>; deleteDevice(uid: string, token: string): Promise<void>; setLastNotified(uid: string, value: { date: string; count: number }): Promise<void>; }`
  - `function runScan(deps: ScanDeps, now: Date): Promise<void>`

- [ ] **Step 1: Write the failing tests**

Create `functions/src/scan.test.ts`:

```ts
import { runScan, ScanDeps, SendResult } from "./scan";
import { UserDoc } from "./fields";

function deps(over: Partial<ScanDeps> & { users: Array<{ uid: string; user: UserDoc }> }) {
  const calls = {
    sent: [] as Array<{ token: string; title: string }>,
    deleted: [] as Array<{ uid: string; token: string }>,
    lastNotified: [] as Array<{ uid: string; count: number; date: string }>,
  };
  const base: ScanDeps = {
    listUsers: async () => over.users,
    listDeviceTokens: over.listDeviceTokens ?? (async () => ["tok-1"]),
    send: over.send ?? (async (t, c): Promise<SendResult> => {
      calls.sent.push({ token: t, title: c.title });
      return "ok";
    }),
    deleteDevice: async (uid, token) => {
      calls.deleted.push({ uid, token });
    },
    setLastNotified: async (uid, v) => {
      calls.lastNotified.push({ uid, count: v.count, date: v.date });
    },
  };
  return { d: base, calls };
}

const u: UserDoc = {
  timezone: "UTC",
  reminders: { weekday: ["08:00"], weekend: [] },
  streak: 3,
  bankedToday: false,
  lastActiveDate: "2026-06-26",
};
const now = new Date("2026-06-26T08:30:00Z");

describe("runScan", () => {
  it("sends to each device and advances lastNotified on delivery", async () => {
    const { d, calls } = deps({ users: [{ uid: "a", user: u }] });
    await runScan(d, now);
    expect(calls.sent).toHaveLength(1);
    expect(calls.lastNotified).toEqual([{ uid: "a", count: 1, date: "2026-06-26" }]);
  });

  it("skips users the core says not to send to", async () => {
    const { d, calls } = deps({ users: [{ uid: "a", user: { ...u, bankedToday: true } }] });
    await runScan(d, now);
    expect(calls.sent).toHaveLength(0);
    expect(calls.lastNotified).toHaveLength(0);
  });

  it("deletes a dead token and does not advance lastNotified when all tokens are dead", async () => {
    const { d, calls } = deps({
      users: [{ uid: "a", user: u }],
      send: async (): Promise<SendResult> => "invalid-token",
    });
    await runScan(d, now);
    expect(calls.deleted).toEqual([{ uid: "a", token: "tok-1" }]);
    expect(calls.lastNotified).toHaveLength(0);
  });
});
```

- [ ] **Step 2: Run them to verify they fail**

Run: `npm --prefix functions test -- scan`
Expected: FAIL — `./scan` not found.

- [ ] **Step 3: Implement `scan.ts`**

Create `functions/src/scan.ts`:

```ts
import { decideNotification } from "./decide";
import { localParts, UserDoc } from "./fields";

export type SendResult = "ok" | "invalid-token" | "error";

/** I/O the orchestrator needs, injected so the loop is unit-testable without
 * the Admin SDK / emulator. `index.ts` supplies the Firestore/FCM-backed impl. */
export interface ScanDeps {
  listUsers(): Promise<Array<{ uid: string; user: UserDoc }>>;
  listDeviceTokens(uid: string): Promise<string[]>;
  send(token: string, copy: { title: string; body: string }): Promise<SendResult>;
  deleteDevice(uid: string, token: string): Promise<void>;
  setLastNotified(uid: string, value: { date: string; count: number }): Promise<void>;
}

/** One scheduled pass: decide per user, fan out to devices, prune dead tokens,
 * and advance lastNotified only when at least one device was delivered to. */
export async function runScan(deps: ScanDeps, now: Date): Promise<void> {
  const users = await deps.listUsers();
  for (const { uid, user } of users) {
    const decision = decideNotification(user, now);
    if (!decision.send) continue;

    const tokens = await deps.listDeviceTokens(uid);
    let delivered = false;
    for (const token of tokens) {
      const result = await deps.send(token, { title: decision.title, body: decision.body });
      if (result === "ok") delivered = true;
      else if (result === "invalid-token") await deps.deleteDevice(uid, token);
    }

    if (delivered) {
      await deps.setLastNotified(uid, {
        date: localParts(user.timezone, now).date,
        count: decision.count,
      });
    }
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `npm --prefix functions test -- scan`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add functions/src/scan.ts functions/src/scan.test.ts
git commit -m "feat(functions): runScan orchestrator (fan-out + token pruning, D4)"
```

---

### Task B5: `index.ts` — `onSchedule` wiring (Admin SDK)

**Files:**
- Modify: `functions/src/index.ts` (replace scaffold)
- (no unit test — admin/FCM wiring is verified by build + the manual device check)

**Interfaces:**
- Consumes: `runScan`/`ScanDeps`/`SendResult` (B4), `UserDoc` (B1).
- Produces: `export const sendReminders` (scheduled function).

- [ ] **Step 1: Replace the scaffold**

Overwrite `functions/src/index.ts`:

```ts
import { setGlobalOptions } from "firebase-functions";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

import { UserDoc } from "./fields";
import { runScan, ScanDeps, SendResult } from "./scan";

initializeApp();
setGlobalOptions({ maxInstances: 10 });

// Every 15 minutes: nudge users whose streak isn't secured (D3/D16).
export const sendReminders = onSchedule("every 15 minutes", async () => {
  const db = getFirestore();
  const messaging = getMessaging();

  const deps: ScanDeps = {
    async listUsers() {
      const snap = await db.collection("users").get();
      return snap.docs.map((d) => ({ uid: d.id, user: d.data() as UserDoc }));
    },
    async listDeviceTokens(uid) {
      const snap = await db.collection(`users/${uid}/devices`).get();
      return snap.docs.map((d) => d.data().token as string).filter(Boolean);
    },
    async send(token, copy): Promise<SendResult> {
      try {
        await messaging.send({ token, notification: copy });
        return "ok";
      } catch (e: any) {
        const code = e?.errorInfo?.code ?? e?.code;
        if (code === "messaging/registration-token-not-registered") return "invalid-token";
        logger.error("FCM send failed", { code });
        return "error";
      }
    },
    async deleteDevice(uid, token) {
      await db.doc(`users/${uid}/devices/${token}`).delete();
    },
    async setLastNotified(uid, value) {
      await db.doc(`users/${uid}`).set({ lastNotified: value }, { merge: true });
    },
  };

  await runScan(deps, new Date());
});
```

- [ ] **Step 2: Build, lint, and run the full functions suite**

Run: `npm --prefix functions run build && npm --prefix functions run lint && npm --prefix functions test`
Expected: build emits cleanly; lint reports no errors; all jest suites PASS.

- [ ] **Step 3: Commit**

```bash
git add functions/src/index.ts
git commit -m "feat(functions): onSchedule sendReminders wiring (D3/D16)"
```

---

### Task B6: Manual device-push check doc

**Files:**
- Create: `docs/superpowers/phase-6-manual-push-check.md`

- [ ] **Step 1: Write the manual check**

Create `docs/superpowers/phase-6-manual-push-check.md`:

```markdown
# Phase 6 — manual push check (not automatable, D18)

Real FCM delivery + Cloud Scheduler cannot be emulated. Run this once against the
real project (`just-one-db69c`) on a physical Android device before relying on nudges.

## Setup
1. `flutter run --dart-define=USE_EMULATOR=false` on a physical device, sign in,
   finish onboarding, and tap **"Turn on reminders"** (grant the OS prompt).
2. Confirm a doc appeared at `users/{uid}/devices/{token}` in the Firestore console.
3. Deploy the function: `firebase deploy --only functions` (provisions the
   "every 15 minutes" Cloud Scheduler job automatically).

## Delivery
4. In Settings, set a reminder time ~2 minutes out (weekday/weekend to match today).
   Make sure today is **not** banked (don't complete a task).
5. Background or kill the app. Within the next 15-minute scan boundary, confirm a
   notification arrives titled **"Clearing"** with opaque body text (no task name).

## Conditional suppression
6. Reopen the app and complete one task (banks the streak). Confirm that subsequent
   reminder times today produce **no** further notification.

## Dead-token cleanup
7. Sign out / uninstall to invalidate the token, leave a reminder pending, and after
   a scan confirm the stale `devices/{token}` doc is deleted.

## Escalation
8. With three reminder times configured and an unsecured day, confirm the final beat
   uses the warmer real-stakes copy ("...streak ends if today stays empty...").
```

- [ ] **Step 2: Commit**

```bash
git add docs/superpowers/phase-6-manual-push-check.md
git commit -m "docs(functions): Phase 6 manual device-push check (D18)"
```

---

### Task B7: Roadmap wrap-up

**Files:**
- Modify: `docs/IMPLEMENTATION-ROADMAP.md` (Phase 6 status → complete + decisions)

- [ ] **Step 1: Mark Phase 6 complete**

In the phases table, change Phase 6's **Status** cell from `Not started` to
`**✅ Complete**` (append the final passing test counts once `flutter test` and
`npm --prefix functions test` are both green).

- [ ] **Step 2: Record the decisions captured during Phase 6**

Append a section after the Phase-5 decisions block:

```markdown
## Decisions captured during Phase-6 (2026-06-26)

- **One spec, both halves** — client FCM plumbing + the Cloud Function shipped together.
- **Tap just opens the app** — no deep-link/`data` routing; `routeHome` already lands on
  daily/cleared. (Closes the "still open" deep-link item: v1 = none.)
- **Catch-up jumps to the latest passed beat** — `decideNotification` sends only the most-
  escalated passed reminder and covers the skipped ones (no backfill burst); a refinement of
  D5's literal "next un-sent".
- **Device doc id = the FCM token** — no local-id dependency; token rotation + the server's
  dead-token cleanup self-heal transient duplicates.
- **Streak-0 copy variant** — the final beat uses start-framing when there's no streak to lose.
- **`MessagingService` seam** (mirrors `AuthService`) + one new `Repository.upsertDevice` —
  the only seam additions; `firebase_messaging` never runs in `flutter test`.
- **Functions switched to CommonJS** — dropped the scaffold's NodeNext/ESM for friction-free
  jest + build; Functions v2 runs CJS fine.
- **Server logic is pure** (`decideNotification` + `runScan` with injected `ScanDeps`) and
  fully unit-tested; only the Admin-SDK wiring in `index.ts` is verified by build + the
  documented manual device check (D18).
- **Settings re-enable card does not open OS settings programmatically** — `firebase_messaging`
  has no such API and we avoided a new dependency; the card re-prompts and, on permanent denial,
  instructs the user to enable in system settings.
```

- [ ] **Step 3: Commit**

```bash
git add docs/IMPLEMENTATION-ROADMAP.md
git commit -m "docs: mark Phase 6 complete; record decisions"
```

---

## Final verification

- [ ] `flutter test` — all green.
- [ ] `flutter analyze` — clean.
- [ ] `npm --prefix functions test` — all jest suites green.
- [ ] `npm --prefix functions run build` — emits cleanly.
- [ ] `npm --prefix functions run lint` — no errors.
- [ ] The manual device-push check (`docs/superpowers/phase-6-manual-push-check.md`) is run before relying on nudges in production.
