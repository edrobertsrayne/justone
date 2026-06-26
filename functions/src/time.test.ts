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

  it("uses UTC+0 for London in winter (no BST)", () => {
    // 2026-01-15 12:00 UTC -> 12:00 local (London is UTC+0 in winter, no DST offset).
    const lp = localParts("Europe/London", new Date("2026-01-15T12:00:00Z"));
    expect(lp.date).toBe("2026-01-15");
    expect(lp.minutes).toBe(720); // 12 * 60
    expect(lp.isWeekend).toBe(false); // Thursday
  });
});
