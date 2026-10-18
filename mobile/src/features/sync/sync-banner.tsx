import { router } from "expo-router";

import { useSyncStatus } from "@/data/session";
import { Banner } from "@/ui/primitives";

/** Says when changes are waiting for a connection or were refused. */
export function SyncBanner() {
  const status = useSyncStatus();
  if (status.failed > 0) {
    return (
      <Banner
        tone="warning"
        text={status.failed === 1 ? "1 change couldn't be saved." : `${status.failed} changes couldn't be saved.`}
        action={{ label: "Review", onPress: () => router.push("/sync-issues") }}
      />
    );
  }
  if (status.phase === "offline") {
    const text =
      status.pending > 0
        ? `Offline. ${status.pending === 1 ? "1 change" : `${status.pending} changes`} will sync when you reconnect.`
        : "Offline. Showing what's saved on this phone.";
    return <Banner text={text} />;
  }
  return null;
}
