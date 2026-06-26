import { setGlobalOptions } from "firebase-functions";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";

import { UserDoc } from "./fields";
import { runScan, ScanDeps, SendResult } from "./scan";

initializeApp();
setGlobalOptions({ maxInstances: 10 });

// Every 15 minutes: nudge users whose streak isn't secured (D3/D16).
export const sendReminders = onSchedule("every 15 minutes", async () => {
  const db = getFirestore();
  const messaging = getMessaging();

  const deps: ScanDeps = {
    async listUsers() {
      const snap = await db.collection("users").get();
      return snap.docs.map((d) => ({ uid: d.id, user: d.data() as UserDoc }));
    },
    async listDeviceTokens(uid) {
      const snap = await db.collection(`users/${uid}/devices`).get();
      return snap.docs.map((d) => d.data().token as string).filter(Boolean);
    },
    async send(token, copy): Promise<SendResult> {
      try {
        await messaging.send({ token, notification: copy });
        return "ok";
      } catch (e: any) {
        const code = e?.errorInfo?.code ?? e?.code;
        if (code === "messaging/registration-token-not-registered") return "invalid-token";
        logger.error("FCM send failed", { code });
        return "error";
      }
    },
    async deleteDevice(uid, token) {
      await db.doc(`users/${uid}/devices/${token}`).delete();
    },
    async setLastNotified(uid, value) {
      await db.doc(`users/${uid}`).set({ lastNotified: value }, { merge: true });
    },
  };

  await runScan(deps, new Date());
});
