# Phase 5 — Stats Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the stats screen — the app's one deliberately loud surface — a static streak hero plus four lifetime stat cards, reached from the daily screen's bar-chart button.

**Architecture:** A new `StatsScreen` `ConsumerWidget` reads `userProvider` (progress fields) and `tasksProvider` (pool count), rendered as a pushed `MaterialPageRoute` from the daily screen — replacing the temporary `PlaceholderScreen`. It is not part of `routeHome`; it's a tap-to-view surface like `manage`/`settings`. Matches the prototype exactly (static, no motion).

**Tech Stack:** Flutter, flutter_riverpod (manual providers, no codegen), `InMemoryRepository` fakes in `flutter test`. Fonts: `Newsreader` (serif/numerals) + `Nunito Sans` (UI/labels).

## Global Constraints

- **Source of truth:** the `<!-- STATS -->` block in `docs/design/Chore App Designs.dc.html` (lines 350–385). Read sizes/colours off the markup; don't invent values.
- **Type scale:** major-second, ratio 1.125, base 14px. Sizes used here: 72.8, 35.9, 17.7, 15.8, 11.1, 9.8 (all already on the ladder).
- **Colours:** paper `#F3F1EC`, ink `#2B2824`. Stats-only: hero `#2F4233`, gold `#E8C98F`, accent green `#3A5240`, overline `#93A58F`, hero subtext `#EEF2E8`.
- **`poolCount` definition:** tasks with `status != archived && status != removed` (i.e. `active` + `benched`). Matches the prototype and `routeHome`'s pool-empty check.
- **Restraint everywhere but here:** this is the only loud surface — but still no motion in this build (entrance animation is deferred).
- **TDD:** failing test first, minimal implementation, frequent commits. UI is covered with widget tests (project convention).
- Keep files under ~1,000 lines.

---

### Task 1: Add stats-surface colour tokens to `Palette`

The hero card and gold numeral need three reusable tokens. The two near-white hero text shades stay local to the screen (Task 2) — they're hero-internal, not reusable.

**Files:**
- Modify: `lib/theme/palette.dart`
- Test: `test/theme/palette_test.dart`

**Interfaces:**
- Produces: `Palette.statsHero` = `Color(0xFF2F4233)`, `Palette.statsGold` = `Color(0xFFE8C98F)`, `Palette.statsAccent` = `Color(0xFF3A5240)`.

- [ ] **Step 1: Write the failing test**

Add this test to `test/theme/palette_test.dart` inside `main()`:

```dart
  test('stats-surface tokens use the exact spec hex values', () {
    expect(Palette.statsHero, const Color(0xFF2F4233));
    expect(Palette.statsGold, const Color(0xFFE8C98F));
    expect(Palette.statsAccent, const Color(0xFF3A5240));
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/theme/palette_test.dart`
Expected: FAIL — `The getter 'statsHero' isn't defined for the type 'Palette'`.

- [ ] **Step 3: Add the tokens**

In `lib/theme/palette.dart`, add to the `Palette` class after `iconCream`:

```dart
  // Stats screen — the one deliberately loud surface (HANDOFF §7).
  static const Color statsHero = Color(0xFF2F4233);
  static const Color statsGold = Color(0xFFE8C98F);
  static const Color statsAccent = Color(0xFF3A5240);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/theme/palette_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/theme/palette.dart test/theme/palette_test.dart
git commit -m "feat(theme): stats-surface colour tokens"
```

---

### Task 2: Build the `StatsScreen` widget

The loud streak hero plus the 2×2 stat grid. Reads providers, derives `poolCount`, guards on loading.

**Files:**
- Create: `lib/ui/stats_screen.dart`
- Test: `test/ui/stats_screen_test.dart`

**Interfaces:**
- Consumes: `Palette.statsHero/statsGold/statsAccent` (Task 1); `userProvider` (`StreamProvider<UserState>`) and `tasksProvider` (`StreamProvider<List<Task>>`) from `lib/app/providers.dart`; `UserState` fields `streak`, `bestStreak`, `targetMetDays`, `lifetimeDone`; `Task.status` / `TaskStatus.{active,benched,archived,removed}`.
- Produces: `class StatsScreen extends ConsumerWidget` (const constructor `StatsScreen({super.key})`).

- [ ] **Step 1: Write the failing tests**

Create `test/ui/stats_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/task.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/stats_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 25, 9);

  UserState user() => UserState(
        timezone: 'UTC',
        lastActiveDate: now,
        onboardingComplete: true,
        streak: 5,
        bestStreak: 12,
        targetMetDays: 9,
        lifetimeDone: 128,
      );

  // 3 active/benched (counted) + 1 archived + 1 removed (excluded) => poolCount 3.
  List<Task> tasks() => [
        Task(id: 'a', title: 'A', kind: TaskKind.recurring, intervalDays: 7, dueAt: now, createdAt: now),
        Task(id: 'b', title: 'B', kind: TaskKind.recurring, intervalDays: 7, dueAt: now, createdAt: now, status: TaskStatus.benched),
        Task(id: 'c', title: 'C', kind: TaskKind.oneOff, dueAt: now, createdAt: now),
        Task(id: 'd', title: 'D', kind: TaskKind.oneOff, dueAt: now, createdAt: now, status: TaskStatus.archived),
        Task(id: 'e', title: 'E', kind: TaskKind.oneOff, dueAt: now, createdAt: now, status: TaskStatus.removed),
      ];

  Future<void> pump(WidgetTester tester, {required InMemoryRepository repo}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
      ],
      child: const MaterialApp(home: StatsScreen()),
    ));
    await tester.pump();
  }

  testWidgets('renders the streak hero and the four stat values', (tester) async {
    await pump(tester, repo: InMemoryRepository(user: user(), tasks: tasks()));
    expect(find.text('Current streak'.toUpperCase()), findsOneWidget); // overline
    expect(find.text('5'), findsOneWidget); // streak numeral
    expect(find.text('days showing up'), findsOneWidget);
    expect(find.text('Days at target'), findsOneWidget);
    expect(find.text('9'), findsOneWidget);
    expect(find.text('Longest streak'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Chores completed'), findsOneWidget);
    expect(find.text('128'), findsOneWidget);
    expect(find.text('In your pool'), findsOneWidget);
    expect(find.text('3'), findsOneWidget); // poolCount excludes archived + removed
  });

  testWidgets('back button pops the route', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryRepository(user: user(), tasks: tasks())),
        nowProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const StatsScreen())),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Your stats'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stats-back')));
    await tester.pumpAndSettle();
    expect(find.text('Your stats'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('renders a paper fill while providers are loading', (tester) async {
    // Repository whose streams never emit -> providers stay loading.
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: StatsScreen()),
    ));
    await tester.pump();
    expect(find.text('Your stats'), findsNothing); // header not built yet
    expect(tester.takeException(), isNull);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/ui/stats_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:justone/ui/stats_screen.dart'`.

> Note on the loading test: with no `ProviderScope` overrides, `repositoryProvider` builds a real `FirestoreRepository` with `uid!` on a null uid and would throw. To keep the loading guard test honest without Firebase, the guard must short-circuit on `userAsync.value == null || tasksAsync.value == null` BEFORE touching anything else — exactly mirroring `HomeRouter`. The default `ProviderScope` here has no auth, so `authProvider` is unset and `userProvider` stays in loading; the widget must therefore render its paper fill from the null-guard. If the real provider graph throws in this environment, replace this test body with an explicit always-loading repository override (a repo whose `watchUser`/`watchTasks` return `Stream.fromFuture(Completer<...>().future)`); keep the assertion that the header is absent and no exception is thrown.

- [ ] **Step 3: Implement `StatsScreen`**

Create `lib/ui/stats_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../domain/task.dart';
import '../theme/palette.dart';

// Hero-internal shades — not reusable tokens, so they live here.
const Color _heroOverline = Color(0xFF93A58F);
const Color _heroSubtext = Color(0xFFEEF2E8);
const Color _backChevron = Color(0xFF6F6A60);
const Color _statLabel = Color(0xFFA8A193);

/// The stats screen — the app's one deliberately loud surface (HANDOFF §1, §7).
/// Static by design; an entrance animation is a deferred follow-up.
class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider).value;
    final tasks = ref.watch(tasksProvider).value;
    if (user == null || tasks == null) {
      return const ColoredBox(color: Palette.paper, child: SizedBox.expand());
    }

    final poolCount = tasks
        .where((t) => t.status != TaskStatus.archived && t.status != TaskStatus.removed)
        .length;

    return Scaffold(
      backgroundColor: Palette.paper,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    key: const ValueKey('stats-back'),
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: const [
                          BoxShadow(color: Color(0x1A2B2824), blurRadius: 3, offset: Offset(0, 1)),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text('‹',
                          style: TextStyle(
                              fontFamily: 'Nunito Sans',
                              fontWeight: FontWeight.w600,
                              fontSize: 17.7,
                              color: _backChevron)),
                    ),
                  ),
                  const Text('Your stats',
                      style: TextStyle(
                          fontFamily: 'Newsreader',
                          fontWeight: FontWeight.w600,
                          fontSize: 15.8,
                          color: Palette.ink)),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 30),
                child: Column(
                  children: [
                    _HeroCard(streak: user.streak),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                            child: _StatCard(
                                value: '${user.targetMetDays}',
                                label: 'Days at target',
                                valueColor: Palette.statsAccent)),
                        const SizedBox(width: 11),
                        Expanded(
                            child: _StatCard(
                                value: '${user.bestStreak}', label: 'Longest streak')),
                      ],
                    ),
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        Expanded(
                            child: _StatCard(
                                value: '${user.lifetimeDone}', label: 'Chores completed')),
                        const SizedBox(width: 11),
                        Expanded(
                            child: _StatCard(value: '$poolCount', label: 'In your pool')),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Palette.statsHero,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 22),
      child: Column(
        children: [
          const Text('CURRENT STREAK',
              style: TextStyle(
                  fontFamily: 'Nunito Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 9.8,
                  letterSpacing: 2.16,
                  color: _heroOverline)),
          const SizedBox(height: 10),
          Text('$streak',
              style: const TextStyle(
                  fontFamily: 'Newsreader',
                  fontWeight: FontWeight.w500,
                  fontSize: 72.8,
                  height: 1,
                  color: Palette.statsGold)),
          const SizedBox(height: 2),
          const Text('days showing up',
              style: TextStyle(
                  fontFamily: 'Newsreader',
                  fontWeight: FontWeight.w500,
                  fontSize: 15.8,
                  color: _heroSubtext)),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label, this.valueColor = Palette.ink});

  final String value;
  final String label;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(color: Color(0x0D2B2824), blurRadius: 2, offset: Offset(0, 1)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontFamily: 'Newsreader',
                  fontWeight: FontWeight.w500,
                  fontSize: 35.9,
                  height: 1,
                  color: valueColor)),
          const SizedBox(height: 8),
          Text(label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontFamily: 'Nunito Sans',
                  fontWeight: FontWeight.w600,
                  fontSize: 11.1,
                  height: 1.3,
                  color: _statLabel)),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/ui/stats_screen_test.dart`
Expected: PASS (all three tests). If the loading test throws, apply the fallback in the Step 2 note (always-loading repository override).

- [ ] **Step 5: Commit**

```bash
git add lib/ui/stats_screen.dart test/ui/stats_screen_test.dart
git commit -m "feat(ui): stats screen — streak hero + lifetime stat grid"
```

---

### Task 3: Wire the daily stats button to `StatsScreen` and remove `PlaceholderScreen`

The daily screen's bar-chart button currently opens a `PlaceholderScreen`. Point it at `StatsScreen`. `PlaceholderScreen`'s only caller was this button, so it becomes dead code — remove it and its test.

**Files:**
- Modify: `lib/ui/daily_screen.dart` (imports + the `_open(context, 'Stats')` call at `:51`, and the now-unused `_open` helper at `:21-23`)
- Test: `test/ui/daily_screen_test.dart` (add a navigation test)
- Delete: `lib/ui/placeholder_screen.dart`, `test/ui/placeholder_screen_test.dart`

**Interfaces:**
- Consumes: `StatsScreen` (Task 2).

- [ ] **Step 1: Write the failing test**

Add to `test/ui/daily_screen_test.dart` inside `main()`:

```dart
  testWidgets('stats button opens the stats screen', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();
    expect(find.text('Your stats'), findsOneWidget);
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/ui/daily_screen_test.dart`
Expected: FAIL — taps the bar-chart, lands on `PlaceholderScreen` ("Stats — coming soon"), so `'Your stats'` is not found.

- [ ] **Step 3: Rewire the button and drop the placeholder helper**

In `lib/ui/daily_screen.dart`:

1. Replace the import line `import 'placeholder_screen.dart';` with `import 'stats_screen.dart';`.
2. Delete the `_open` helper (lines 21–23):

```dart
  void _open(BuildContext context, String title) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceholderScreen(title: title)));
  }
```

3. Change the stats `_ChromeButton`'s `onTap` from:

```dart
                      _ChromeButton(icon: Icons.bar_chart, onTap: () => _open(context, 'Stats')),
```

to:

```dart
                      _ChromeButton(
                          icon: Icons.bar_chart,
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const StatsScreen()))),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/ui/daily_screen_test.dart`
Expected: PASS (all four tests, including the new one).

- [ ] **Step 5: Delete the dead placeholder and its test**

```bash
git rm lib/ui/placeholder_screen.dart test/ui/placeholder_screen_test.dart
```

- [ ] **Step 6: Verify nothing else references the placeholder**

Run: `grep -rn "placeholder_screen\|PlaceholderScreen" lib test`
Expected: no output.

- [ ] **Step 7: Run the full suite**

Run: `flutter test`
Expected: PASS (previous count minus the 1 deleted placeholder test, plus the 4 new tests across Tasks 1–3 — net green, no failures).

- [ ] **Step 8: Commit**

```bash
git add lib/ui/daily_screen.dart test/ui/daily_screen_test.dart
git commit -m "feat(ui): wire daily stats button to StatsScreen; drop placeholder"
```

---

### Task 4: Record Phase-5 decisions and the deferred follow-up

Mark the phase complete and capture the one deliberate deferral (gentle entrance animation) so it isn't lost.

**Files:**
- Modify: `docs/IMPLEMENTATION-ROADMAP.md`

- [ ] **Step 1: Flip the Phase 5 status**

In the phases table, change the Phase 5 `Status` cell from `Not started` to `✅ Complete` (use the final test count from Task 3's `flutter test` run, e.g. `**✅ Complete** (NNN tests green)`).

- [ ] **Step 2: Add a decisions section**

After the "Decisions captured during Phase-4" section, add:

```markdown
## Decisions captured during Phase-5 (2026-06-25)

- **Stats is a pushed route, not a `routeHome` screen:** reached via the daily bar-chart button as a
  `MaterialPageRoute` (same pattern as manage/settings). `AppScreen.stats` stays unreferenced by the
  router, consistent with manage/settings.
- **`poolCount` excludes archived + removed** (active + benched), matching the prototype and
  `routeHome`'s pool-empty definition — derived from `tasksProvider`, not stored.
- **Built static, matching the prototype.** **Deferred follow-up:** revisit a gentle entrance
  animation for the stats hero (streak count-up or hero fade/scale-in), evaluated on-device — the
  handoff calls this "the one loud moment" but the prototype markup carries the weight through
  composition, not motion.
- **`PlaceholderScreen` removed** — the stats button was its last caller.
```

- [ ] **Step 3: Commit**

```bash
git add docs/IMPLEMENTATION-ROADMAP.md
git commit -m "docs: mark Phase 5 complete; record decisions + deferred animation"
```

---

## Self-Review

**Spec coverage:**
- Architecture/nav (pushed route, not in `routeHome`) → Task 3 wiring + Task 4 note. ✓
- Data (userProvider fields + poolCount from tasksProvider, loading guard) → Task 2. ✓
- Layout (header, hero card, 2×2 grid, exact sizes/colours) → Task 2. ✓
- Colour tokens (statsHero/statsGold/statsAccent in Palette; hero shades local) → Task 1 + Task 2. ✓
- Cleanup (remove PlaceholderScreen + import + test) → Task 3. ✓
- Tests (render values, poolCount exclusion, back pops, loading guard, daily wire-up) → Tasks 2 & 3. ✓
- Follow-up note (deferred animation) → Task 4. ✓

**Placeholder scan:** No "TBD"/"handle edge cases"/"similar to" — all code shown in full. The loading-test fallback is fully specified (always-loading repository override), not a hand-wave. ✓

**Type consistency:** `StatsScreen({super.key})` const constructor used identically in Tasks 2 & 3. `poolCount` filter (`!= archived && != removed`) identical in spec, test, and implementation. Provider names (`userProvider`, `tasksProvider`, `repositoryProvider`, `nowProvider`) match `lib/app/providers.dart`. `TaskStatus` members match `lib/domain/task.dart`. `ValueKey('stats-back')` defined in Task 2, asserted in Task 2's test. ✓
