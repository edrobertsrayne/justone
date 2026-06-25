# CLAUDE.md

Guidance for working on **Just One** (one-task-a-day chore app, Flutter + Firebase).

## How to use this file
- **Only record learnings that help future work on this project.** This file is for hard-won
  knowledge, not narration or status. If it won't change a future decision or save future effort,
  it doesn't belong here.
- **If something took several attempts to get right, record it.** When the correct approach
  wasn't the first one you tried, capture the approach that worked (and briefly why the obvious
  ones didn't) so it isn't rediscovered the hard way.

## Working principles
- **Follow YAGNI.** Build the simplest thing that functions as desired. No speculative
  generality, no building for hypothetical futures. The simplest option that works wins.
- **Keep files under ~1,000 lines.** Don't let any file grow past 1k lines without a very good,
  explicit reason. Split or refactor before it gets there.

## Learnings
<!-- Append project-specific learnings below as they're discovered. -->

- **Testing `StreamProvider`s backed by `async*` repository streams:** `InMemoryRepository`'s
  `watchUser()`/`watchTasks()` are single-subscription `async*` generators. In a unit test, calling
  `container.read(someStreamProvider.future)` with no active listener lets Riverpod 3.x auto-dispose
  the provider mid-load, so the future never completes and the test times out. Establish a listener
  first — `container.listen(provider, (_, __) {})` (close it in `addTearDown`) — before awaiting
  `.future`. Widget tests don't hit this: the widget tree keeps the providers alive.

- **UI reading a `StreamProvider` (`userProvider`) inside a callback / bottom sheet:** the widget
  must establish an active listener before `ref.read(provider).value` — otherwise `.value` is null
  and the action silently no-ops. For a modal bottom sheet, make it a `ConsumerStatefulWidget` so it
  owns its own `ref` and does `ref.watch(userProvider)` in `build`. Don't thread a borrowed
  `WidgetRef` from the caller into a plain `StatefulWidget` and call `listenManual` on it — that
  subscription is tied to the *caller's* element, not the sheet's, so it leaks on every open.
