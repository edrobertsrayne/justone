# Phase 5 — Stats screen (design)

**Status:** approved, ready for implementation plan
**Date:** 2026-06-25
**Roadmap:** Phase 5 of `docs/IMPLEMENTATION-ROADMAP.md`

The stats screen is the streak hero — **the app's one deliberately loud surface** (HANDOFF §1,
§7). Everywhere else the product is restraint; here it gives weight. The build matches the
prototype exactly (static): the loudness comes from composition — a dark-green hero card and an
oversized gold streak numeral — not from motion. The source of truth is the `<!-- STATS -->` block
in `docs/design/Chore App Designs.dc.html` (lines 350–385).

## Goal

A `StatsScreen` that displays the current streak hero plus four supporting lifetime stats, reached
by tapping the bar-chart button on the daily screen.

## Architecture / navigation

- New widget `lib/ui/stats_screen.dart` (`StatsScreen`, a `ConsumerWidget`).
- Pushed as a `MaterialPageRoute` from the daily screen's bar-chart `_ChromeButton`, **replacing**
  the current `_open(context, 'Stats')` → `PlaceholderScreen` call. Same navigation pattern as
  `ManageScreen`/`SettingsScreen`.
- **Not** added to `routeHome`. Stats is a tap-to-view surface, not part of the daily loop — the
  same way `manage`/`settings` live outside the router. `AppScreen.stats` already exists in the
  enum and remains unreferenced by the router, consistent with `manage`/`settings`.

## Data

`StatsScreen` reads:

- `userProvider` → `streak`, `targetMetDays`, `bestStreak`, `lifetimeDone`.
- `tasksProvider` → `poolCount` = count of tasks with `status != archived && status != removed`
  (i.e. active + benched). This matches the prototype's `poolCount`
  (`x.status!=='archived' && x.status!=='removed'`) and `routeHome`'s pool-empty definition.

While either provider is still loading (`.value == null`), render a bare `Palette.paper` fill —
the same guard `HomeRouter` uses.

## Layout (exact spec from the prototype)

Outer: `Scaffold` on `Palette.paper`, `SafeArea`, column.

**Header** (padding ~50/22/14, space-between row):
- Back chevron `‹` button — 40×40, white, radius 13, soft shadow; Nunito Sans 600 17.7px
  `#6F6A60`. Pops the route.
- Centered title "Your stats" — Newsreader 600, 15.8px, `Palette.ink`.
- 40px spacer (keeps the title centered).

**Body** (scrollable — prototype uses `overflow:auto`; padding ~8/22/30):

- **Hero card:** background `#2F4233`, radius 22, padding 26/22, centered text:
  - Overline "CURRENT STREAK" — Nunito Sans 700, 9.8px, letter-spacing .22em (≈2.16px), `#93A58F`.
  - Streak numeral `{{ streak }}` — Newsreader 500, **72.8px**, gold `#E8C98F`, margin-top 10.
  - Subtext "days showing up" — Newsreader 500, 15.8px, `#EEF2E8`, margin-top 2.

- **2×2 grid of stat cards** (two rows of two, gap 11, row gap 11). Each card: white, radius 18,
  padding 18, subtle shadow (`rgba(43,40,36,.05)`), centered:
  - Numeral — Newsreader 500, 35.9px.
  - Label — Nunito Sans 600, 11.1px, line-height 1.3, `#A8A193`, margin-top 8.

  | Position | Value | Label | Numeral colour |
  |---|---|---|---|
  | row 1 left | `targetMetDays` | "Days at target" | `#3A5240` (accent green) |
  | row 1 right | `bestStreak` | "Longest streak" | `Palette.ink` |
  | row 2 left | `lifetimeDone` | "Chores completed" | `Palette.ink` |
  | row 2 right | `poolCount` | "In your pool" | `Palette.ink` |

## Colour tokens

Add the loud-surface colours to `Palette` (the codebase centralizes colour tokens there):

- `statsHero` = `#2F4233`
- `statsGold` = `#E8C98F`
- `statsAccent` = `#3A5240`

The two near-white text shades used only inside the hero (`#93A58F` overline, `#EEF2E8` subtext)
stay as local constants in `stats_screen.dart` — they are hero-internal, not reusable tokens.

## Cleanup

`PlaceholderScreen` was only ever the stand-in for this screen (its sole caller is the daily
screen's Stats button). After wiring `StatsScreen` it is dead code. Remove
`lib/ui/placeholder_screen.dart`, its import in `daily_screen.dart`, and
`test/ui/placeholder_screen_test.dart`.

## Testing (TDD — widget tests, matching the project's UI convention)

`test/ui/stats_screen_test.dart`:

- Renders `streak`, `bestStreak`, `targetMetDays`, `lifetimeDone` from a fake user.
- Derives `poolCount` correctly — excludes `archived` and `removed`, includes `active` + `benched`.
- Back button pops the route.
- Loading guard: renders a paper fill (no crash) when providers haven't resolved.

`test/ui/daily_screen_test.dart` (extend): tapping the stats button navigates to `StatsScreen`,
not `PlaceholderScreen`.

## Follow-up (deferred, by decision)

The handoff calls stats "the one loud moment — give it weight." We are matching the static
prototype now. **Revisit a gentle entrance animation** (e.g. streak numeral count-up, or hero
fade/scale-in) later, evaluated on-device. Record this as a Phase-5 note in the roadmap.

## Out of scope

- No entrance/motion animation (deferred, above).
- No changes to the urgency curve, transitions, or daily loop.
- Notifications remain Phase 6.
