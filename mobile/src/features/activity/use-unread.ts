import { useMemo } from "react";

import { unreadActivityCount } from "@/domain";
import { activityOptions } from "@/data/selectors";
import { useAppState, useSignedIn } from "@/data/session";

export function useUnreadActivityCount(): number {
  const { user } = useSignedIn();
  const state = useAppState();
  return useMemo(() => unreadActivityCount([...state.tables.activity_log.values()], activityOptions(state, user.id)), [state, user.id]);
}
