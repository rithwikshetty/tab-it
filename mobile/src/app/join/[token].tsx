import { Redirect, useLocalSearchParams } from "expo-router";
import { useEffect, useState } from "react";

import { savePendingInvite } from "@/data/invites";

// https://tab-it.app/join/<token> lands here. The token is kept until a
// signed-in session redeems it (see the signed-in layout).
export default function JoinInvite() {
  const { token } = useLocalSearchParams<{ token: string }>();
  const [saved, setSaved] = useState(false);
  useEffect(() => {
    savePendingInvite(String(token ?? "").toLowerCase()).finally(() => setSaved(true));
  }, [token]);
  return saved ? <Redirect href="/" /> : null;
}
