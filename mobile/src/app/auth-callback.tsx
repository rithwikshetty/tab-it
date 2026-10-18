import { Redirect, useLocalSearchParams } from "expo-router";
import { useEffect, useState } from "react";

import { supabase } from "@/lib/supabase";

// Opened by `<bundle id>://auth-callback` when a browser sign-in hands back to
// the app outside the in-app auth session. Finishes the PKCE exchange, then
// returns to the app's start.
export default function AuthCallback() {
  const { code } = useLocalSearchParams<{ code?: string }>();
  const [done, setDone] = useState(!code);
  useEffect(() => {
    if (!code) return;
    supabase.auth.exchangeCodeForSession(code).finally(() => setDone(true));
  }, [code]);
  return done ? <Redirect href="/" /> : null;
}
