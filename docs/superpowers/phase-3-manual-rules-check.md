# Phase 3 — Manual owner-isolation rules check (D12)

The Dart test fakes have no rules engine, so verify `firestore.rules` by hand
against the emulator whenever the rules change. Expected: a user can read/write
only their own `users/{uid}` tree.

## Steps
1. `firebase emulators:start` (serves Auth :9099, Firestore :8080, UI).
2. Open the Emulator UI → Firestore. Create `users/alice/tasks/t1` and `users/bob/tasks/t1`.
3. In the Auth emulator, add two users; note alice's uid.
4. Using the Rules Playground (Firestore tab → "Rules playground"):
   - **Allowed:** authenticated as alice, `get`/`update` on `users/alice` and
     `users/alice/tasks/t1` → all green.
   - **Denied:** authenticated as alice, `get`/`update` on `users/bob` and
     `users/bob/tasks/t1` → all red (permission denied).
   - **Denied:** unauthenticated, any path → red.
5. If any expectation fails, the rules are wrong — fix and re-run.
