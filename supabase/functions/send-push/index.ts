// send-push: Database webhook (pg_net) -> resolve recipients -> APNs.
// Authenticated by a shared secret header (verify_jwt = false), so the call must
// come from the DB trigger, which reads the secret from private.app_config.
import { createClient } from "jsr:@supabase/supabase-js@2";
import { apnsConfigured, sendPush } from "./apns.ts";

const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

interface ActivityEvent {
  activity_id: string;
  trip_id: string;
  actor_id: string;
  action: string;
  entity_type: string;
  entity_id: string;
  snapshot: Record<string, string> | null;
}

interface PushTarget {
  user_id: string;
  apns_token: string;
  push_device_id: string;
  badge: number;
}

/// Compose the banner: trip name as title, action-specific body. Mirrors the
/// in-app ActivityPresenter so push and feed read consistently.
function composeAlert(event: ActivityEvent): { title: string; body: string } {
  const s = event.snapshot ?? {};
  const actor = s.actor_name ?? "Someone";
  const title = s.trip_name ?? "tab-it";
  const money = s.amount && s.currency ? ` ${s.currency} ${s.amount}` : "";
  const desc = s.description ?? "an expense";

  let body: string;
  switch (event.action) {
    case "expense_created": body = `${actor} added ${desc}${money}`; break;
    case "expense_updated": body = `${actor} edited ${desc}${money}`; break;
    case "expense_deleted": body = `${actor} deleted ${desc}`; break;
    case "settlement_created": body = `${actor} recorded a payment${money}`; break;
    case "settlement_updated": body = `${actor} edited a payment${money}`; break;
    case "settlement_deleted": body = `${actor} removed a payment`; break;
    case "member_joined": body = `${actor} added ${s.member_name ?? "someone"}`; break;
    case "member_left": body = `${actor} removed ${s.member_name ?? "someone"}`; break;
    case "trip_updated": body = `${actor} renamed the trip`; break;
    default: body = `${actor} updated the trip`;
  }
  return { title, body };
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET || WEBHOOK_SECRET === "") {
    return new Response("unauthorized", { status: 401 });
  }

  let body_: { activity_id?: string };
  try {
    body_ = (await req.json()) as { activity_id?: string };
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }
  if (!body_.activity_id) {
    return new Response(JSON.stringify({ error: "missing_activity_id" }), {
      status: 400,
      headers: { "content-type": "application/json" },
    });
  }

  if (!apnsConfigured()) {
    // Push not configured (no .p8 / keys). Acknowledge so the webhook doesn't error.
    return new Response(JSON.stringify({ skipped: "apns_not_configured" }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Only the activity ID is trusted from the request; title/body/deep-link all
  // come from the canonical row, so a replayed or tampered webhook body can't
  // put words in a banner.
  const { data: row, error: rowError } = await supabase
    .from("activity_log")
    .select("id, trip_id, actor_id, action, entity_type, entity_id, snapshot_json")
    .eq("id", body_.activity_id)
    .maybeSingle();
  if (rowError) {
    return new Response(JSON.stringify({ error: rowError.message }), { status: 500 });
  }
  if (!row) {
    return new Response(JSON.stringify({ error: "unknown_activity" }), { status: 404 });
  }
  const event: ActivityEvent = {
    activity_id: row.id,
    trip_id: row.trip_id,
    actor_id: row.actor_id,
    action: row.action,
    entity_type: row.entity_type,
    entity_id: row.entity_id,
    snapshot: row.snapshot_json as Record<string, string> | null,
  };

  const { data: targets, error } = await supabase.rpc("push_targets_for_activity", {
    p_activity_id: event.activity_id,
  });
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }

  const { title, body } = composeAlert(event);
  let sent = 0;
  const deadDeviceIds: string[] = [];

  for (const target of (targets ?? []) as PushTarget[]) {
    const payload = {
      aps: {
        alert: { title, body },
        badge: target.badge,
        sound: "default",
        "thread-id": event.trip_id,
      },
      trip_id: event.trip_id,
      entity_type: event.entity_type,
      entity_id: event.entity_id,
    };
    // One bad token or network hiccup must not abort the rest of the fan-out.
    let result;
    try {
      result = await sendPush(target.apns_token, payload, { collapseId: event.entity_id });
    } catch (e) {
      console.error(`apns send threw device=${target.push_device_id}: ${e instanceof Error ? e.message : String(e)}`);
      continue;
    }
    if (result.ok) {
      sent++;
    } else if (result.tokenDead) {
      deadDeviceIds.push(target.push_device_id);
    } else {
      console.error(`apns send failed status=${result.status} reason=${result.reason} device=${target.push_device_id}`);
    }
  }

  if (deadDeviceIds.length > 0) {
    await supabase.from("push_devices").delete().in("id", deadDeviceIds);
  }

  return new Response(JSON.stringify({ sent, pruned: deadDeviceIds.length }), {
    status: 200,
    headers: { "content-type": "application/json" },
  });
});
