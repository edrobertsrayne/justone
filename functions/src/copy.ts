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
