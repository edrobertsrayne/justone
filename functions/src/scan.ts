import { decideNotification } from "./decide";
import { localParts, UserDoc } from "./fields";

export type SendResult = "ok" | "invalid-token" | "error";

/** I/O the orchestrator needs, injected so the loop is unit-testable without
 * the Admin SDK / emulator. `index.ts` supplies the Firestore/FCM-backed impl. */
export interface ScanDeps {
  listUsers(): Promise<Array<{ uid: string; user: UserDoc }>>;
  listDeviceTokens(uid: string): Promise<string[]>;
  send(token: string, copy: { title: string; body: string }): Promise<SendResult>;
  deleteDevice(uid: string, token: string): Promise<void>;
  setLastNotified(uid: string, value: { date: string; count: number }): Promise<void>;
}

/** One scheduled pass: decide per user, fan out to devices, prune dead tokens,
 * and advance lastNotified only when at least one device was delivered to. */
export async function runScan(deps: ScanDeps, now: Date): Promise<void> {
  const users = await deps.listUsers();
  for (const { uid, user } of users) {
    try {
      const decision = decideNotification(user, now);
      if (!decision.send) continue;

      const tokens = await deps.listDeviceTokens(uid);
      let delivered = false;
      for (const token of tokens) {
        const result = await deps.send(token, { title: decision.title, body: decision.body });
        if (result === "ok") delivered = true;
        else if (result === "invalid-token") await deps.deleteDevice(uid, token);
      }

      if (delivered) {
        await deps.setLastNotified(uid, {
          date: localParts(user.timezone, now).date,
          count: decision.count,
        });
      }
    } catch (e) {
      console.error(`scan: user ${uid} failed`, e);
    }
  }
}
