import { Redirect, useLocalSearchParams } from "expo-router";
import { useEffect, useState } from "react";
import { Alert } from "react-native";

import { browserSignInRunning } from "@/data/auth";
import { supabase } from "@/lib/supabase";

// Opened by `<bundle id>://auth-callback` when a sign-in link hands back to
// the app outside the in-app browser sign-in, which exchanges its own code.
// Finishes the PKCE exchange, then returns to the app's start.
export default function AuthCallback() {
  const { code } = useLocalSearchParams<{ code?: string }>();
  const [done, setDone] = useState(!code || browserSignInRunning());
  useEffect(() => {
    if (done || !code) return;
    supabase.auth
      .exchangeCodeForSession(code)
      .then(({ error }) => {
        if (error) Alert.alert("Couldn't sign in", "That sign-in link didn't work. Ask for a new code and try again.");
      })
      .finally(() => setDone(true));
    // Runs once for the code this screen opened with.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [code]);
  return done ? <Redirect href="/" /> : null;
}
