import { useEffect } from "react";
import { AppState } from "react-native";

import { supabase } from "@/lib/supabase";

import { useSignedIn } from "./session";

// Live updates for the trip on screen: any change another member makes to its
// expenses, payments, people or name pulls that trip again.

const TABLES = [
  { table: "expenses", filter: (id: string) => `trip_id=eq.${id}` },
  { table: "settlements", filter: (id: string) => `trip_id=eq.${id}` },
  { table: "trip_people", filter: (id: string) => `trip_id=eq.${id}` },
  { table: "trips", filter: (id: string) => `id=eq.${id}` },
] as const;

export function useTripRealtime(tripId: string | undefined) {
  const { sync, store } = useSignedIn();
  useEffect(() => {
    if (!tripId) return;
    // A trip that hasn't reached the server has nothing to listen to yet.
    if (store.getState().tables.trips.get(tripId)?._pushed === null) return;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const refresh = () => {
      if (timer) clearTimeout(timer);
      timer = setTimeout(() => void sync.request({ tripId }), 400);
    };
    let channel = subscribe();
    function subscribe() {
      const ch = supabase.channel(`trip-${tripId}-${Date.now()}`);
      for (const t of TABLES) {
        ch.on("postgres_changes", { event: "*", schema: "public", table: t.table, filter: t.filter(tripId!) }, refresh);
      }
      ch.subscribe();
      return ch;
    }
    // Sockets drop in the background; reconnect and catch up on return.
    const sub = AppState.addEventListener("change", (s) => {
      if (s === "active") {
        void supabase.removeChannel(channel);
        channel = subscribe();
        refresh();
      }
    });
    return () => {
      sub.remove();
      if (timer) clearTimeout(timer);
      void supabase.removeChannel(channel);
    };
  }, [tripId, sync, store]);
}
