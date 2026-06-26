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
