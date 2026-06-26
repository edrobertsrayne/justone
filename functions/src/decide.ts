import { copyFor } from "./copy";
import { localParts, parseHM, UserDoc } from "./fields";

export type Decision =
  | { send: false }
  | { send: true; index: number; count: number; title: string; body: string };

/** Pure decision core (D1/D3/D5/D17): given a user doc and the current instant,
 * decide whether to send a nudge and which escalation beat. No I/O. */
export function decideNotification(user: UserDoc, now: Date): Decision {
  const lp = localParts(user.timezone, now);

  // D1: a doc whose lastActiveDate isn't local-today rolled over server-side
  // without an app open — treat today's flags/count as cleared.
  const fresh = user.lastActiveDate === lp.date;
  const banked = fresh && user.bankedToday === true;
  if (banked) return { send: false }; // streak secured -> suppress the rest

  const reminders = (lp.isWeekend ? user.reminders?.weekend : user.reminders?.weekday) ?? [];
  if (reminders.length === 0) return { send: false };

  const times = reminders.map(parseHM).sort((a, b) => a - b);
  let passedCount = 0;
  for (const t of times) if (t <= lp.minutes) passedCount++;
  if (passedCount === 0) return { send: false };

  const sentCount =
    user.lastNotified && user.lastNotified.date === lp.date ? user.lastNotified.count : 0;
  if (passedCount <= sentCount) return { send: false };

  // Jump to the latest passed beat; cover the skipped earlier ones so they
  // don't backfill on subsequent runs.
  const index = passedCount - 1;
  const isFinal = index === times.length - 1;
  const { title, body } = copyFor({ isFinal, streak: user.streak ?? 0 });
  return { send: true, index, count: passedCount, title, body };
}
