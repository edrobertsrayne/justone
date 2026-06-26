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
