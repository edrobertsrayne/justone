# Just One — Implementation Roadmap

The product spec (`docs/design/HANDOFF.md`) and backend decisions
(`docs/design/backend-decisions.md`, D1–D23) are **locked and already grilled**. This file
records the *sequencing* of the build — it is too large for one spec, so it's decomposed into
phases. **Each phase gets its own spec → plan → implementation cycle** (via the brainstorming /
writing-plans flow). Specs land in `docs/superpowers/specs/`.

Starting point (2026-06-22): default Flutter counter app with the correct dependencies already in
`pubspec.yaml` (firebase_core/auth, cloud_firestore, messaging, google_sign_in, riverpod,
flutter_timezone), a configured `firebase_options.dart`, and untouched `firestore.rules` /
`functions/` templates.

## Phases

| # | Phase | Scope | Status |
|---|---|---|---|
| 1 | **Domain core + design system** | Pure-Dart immutable models (`Task`, `UserState`), the urgency curve + `meta` derivation, the selection engine (highest-urg active task), the screen-routing pure function, and the state-transition functions (complete / skip / remove / daily-reset) returning intended writes. Plus the design system: colour tokens, halo colour interpolation, the major-second type scale, `Newsreader`/`Nunito Sans` text styles, `ThemeData`. **No Firebase, no UI. Fully TDD.** | **In design (current)** |
| 2 | **Daily-loop UI** | The daily card (swipe-right Done, swipe-left Skip, long-press Remove, finger-following physics, hint labels, halo), plus `cleared` / `emptyPool` / `targetHit` screens and toasts. Driven by the Phase-1 engine against an **in-memory fake repository** (no Firebase yet). | Not started |
| 3 | **Firebase wiring** | Google Sign-In, `users/{uid}` bootstrap on first sign-in (D13), Firestore `StreamProvider`s over user doc + tasks (D10), the real repository, complete-task `WriteBatch` (D11), client-authoritative daily reset on cold-start + resume (D7/D22), owner-isolation security rules (D12). Swap the fake repo for the real one. | Not started |
| 4 | **Onboarding + add / manage / settings** | First-run wizard (`onboardTarget` + `onboardAdd` batch seed in one `WriteBatch`, D23), the `add`/edit screen (title, deadline, recurrence), the `manage` pool screen, and `settings` (target, reminder schedule per D17). First-run routing via `onboardingComplete` (D13). | Not started |
| 5 | **Stats screen** | The streak hero — the one deliberately loud surface in the app. | Not started |
| 6 | **Notifications** | Cloud Function (TypeScript, Functions v2, `onSchedule("every 15 minutes")`, D16) scanning user docs and sending FCM per timezone/reminder window with idempotency + escalation (D3/D5/D17); FCM token registration in a `devices` subcollection (D4); runtime permission flow at end of onboarding with a settings re-enable path (D14); notification-type payloads (D15). | Not started |

## Decisions captured during Phase-1 brainstorm (2026-06-22/23)

- **First slice = Phase 1** (domain core + design system) — foundation everything sits on; resolves
  the urgency curve.
- **Urgency curve (proposed):** a single sigmoid in *normalised lateness*. `d = (now − dueAt)` in
  days; normaliser `N = intervalDays` for recurring, `N = 7` for a one-off with a deadline;
  `r = d / N`; `urg = 0.04 + 0.94 · sigmoid(2r)`. Due-now ≈ 0.51, one cycle overdue ≈ 0.87, badly
  overdue → ~0.96, far-from-due falls below the 0.04 "cleared" threshold naturally. All constants
  tunable + TDD'd.
- **Undated one-off tasks:** surface as gently-due-now with a constant low-band urgency (~0.35) —
  always rank below anything with a real deadline, but keep appearing, so `cleared` is reached only
  when the actionable pool is genuinely empty.
- **Day-one seed:** seeded recurring chores get `dueAt = today` so onboarding lands on a populated
  daily card.

## Still genuinely open (from research §11 / backend "still open")

- Final tuning of the urgency curve constants, reroll count (≈3), default reminder times, streak
  grace (none for v1).
- Notification-tap deep-link routing specifics (Phase 6).
