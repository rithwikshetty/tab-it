// sweep-receipts: removes receipt photos no expense has pointed at for 30
// days. pg_cron calls it once a day through pg_net. Authenticated by the same
// shared secret header as send-push (verify_jwt = false).
//
// orphaned_receipt_objects() picks the objects; this function removes them
// through the Storage API, which deletes the file as well as its row.
import { createClient } from "jsr:@supabase/supabase-js@2";

const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const BATCH = 100;

function json(body: unknown, status: number): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== WEBHOOK_SECRET || WEBHOOK_SECRET === "") {
    return new Response("unauthorized", { status: 401 });
  }

  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const { data, error } = await admin.rpc("orphaned_receipt_objects");
  if (error) {
    console.error("orphaned_receipt_objects failed", error);
    return json({ error: "list_failed" }, 500);
  }

  const names = ((data ?? []) as { name: string }[]).map((row) => row.name);
  let removed = 0;
  for (let i = 0; i < names.length; i += BATCH) {
    const { data: gone, error: storageError } = await admin.storage
      .from("receipts")
      .remove(names.slice(i, i + BATCH));
    if (storageError) {
      console.error("receipt removal failed", { removed, storageError });
      return json({ error: "remove_failed", found: names.length, removed }, 500);
    }
    removed += gone?.length ?? 0;
  }

  console.log("sweep-receipts", { found: names.length, removed });
  return json({ found: names.length, removed }, 200);
});
