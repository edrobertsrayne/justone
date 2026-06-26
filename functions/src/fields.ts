export interface ReminderMap {
  weekday: string[];
  weekend: string[];
}

/** The subset of the user doc the notification function reads (mirrors the
 * canonical model in docs/design/backend-decisions.md). */
export interface UserDoc {
  timezone: string;
  reminders?: ReminderMap;
  streak?: number;
  bankedToday?: boolean;
  lastActiveDate?: string; // "YYYY-MM-DD"
  lastNotified?: { date: string; count: number };
}

export interface LocalParts {
  date: string; // "YYYY-MM-DD" in the user's tz
  minutes: number; // minutes since local midnight (0..1439)
  isWeekend: boolean; // local Sat/Sun
}

/** Wall-clock minutes for an "HH:mm" reminder string. */
export function parseHM(s: string): number {
  const [h, m] = s.split(":").map((x) => parseInt(x, 10));
  return h * 60 + m;
}

/** DST-correct local date/time-of-day/weekday from an IANA tz, using the
 * built-in Intl API (no luxon/moment-timezone dependency). */
export function localParts(timezone: string, now: Date): LocalParts {
  const fmt = new Intl.DateTimeFormat("en-US", {
    timeZone: timezone,
    hour12: false,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    weekday: "short",
  });
  const parts: Record<string, string> = {};
  for (const p of fmt.formatToParts(now)) parts[p.type] = p.value;
  let hour = parseInt(parts.hour, 10);
  if (hour === 24) hour = 0; // some engines render local midnight as "24"
  const minutes = hour * 60 + parseInt(parts.minute, 10);
  const date = `${parts.year}-${parts.month}-${parts.day}`;
  const isWeekend = parts.weekday === "Sat" || parts.weekday === "Sun";
  return { date, minutes, isWeekend };
}
