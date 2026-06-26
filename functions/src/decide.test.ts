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
