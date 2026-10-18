import { inviteJoinErrorMessage, normalizedEmail } from "@/domain";
import type { TripPerson } from "@/domain/records";
import { INVITE_URL_PREFIX } from "@/lib/config";
import { uuid } from "@/lib/ids";
import { supabase } from "@/lib/supabase";

import type { Ctx } from "./actions";
import { call, RemoteError, toRemoteError } from "./remote";
import type { LocalPerson, Op } from "./schema";
import type { SyncEngine } from "./sync";

// Operations the server must perform itself (membership, invites, the hidden
// containers behind non-group expenses). They need a connection; the result
// is merged into the store straight away so the UI reflects it.

export interface OnlineCtx extends Ctx {
  sync: SyncEngine;
}

export function onlineMessage(error: unknown): string {
  const e = toRemoteError(error);
  if (e.transient) return "You're offline. Connect to the internet and try again.";
  return e.message;
}

export function inviteErrorMessage(error: unknown): string {
  const e = toRemoteError(error);
  if (e.transient) return "You're offline. Connect to the internet and open the invite link again.";
  return inviteJoinErrorMessage(e.code ?? null) ?? e.message;
}

async function mergePeople({ store }: Ctx, rows: TripPerson[]) {
  await store.commit(rows.map((row) => ({ table: "trip_people", row: { ...row, _pushed: row.write_id, _error: null } }) as Op));
}

/** A trip created offline must reach the server before people can join it. */
async function ensureTripOnServer(ctx: OnlineCtx, tripId: string) {
  const trip = ctx.store.getState().tables.trips.get(tripId);
  if (!trip) throw new RemoteError("Trip not found on this phone.", false);
  if (trip.deleted_at) throw new RemoteError("This trip has been deleted.", false);
  if (trip._pushed !== null) return;
  await ctx.sync.request();
  const after = ctx.store.getState().tables.trips.get(tripId);
  if (after?._pushed === null) {
    throw new RemoteError(after._error ?? "You're offline. Connect to the internet and try again.", !after._error);
  }
}

export async function addTripPerson(ctx: OnlineCtx, tripId: string, email: string, displayName: string | null): Promise<LocalPerson> {
  await ensureTripOnServer(ctx, tripId);
  const row = await call(
    supabase.rpc("add_trip_person_by_email", {
      p_trip_id: tripId,
      p_email: normalizedEmail(email),
      p_display_name: displayName?.trim() || undefined,
      p_person_id: uuid(),
    }),
  );
  const person = row as unknown as TripPerson;
  await mergePeople(ctx, [person]);
  return { ...person, _pushed: person.write_id };
}

export async function updateTripPersonEmail(ctx: OnlineCtx, personId: string, email: string) {
  const row = await call(supabase.rpc("update_trip_person_email", { p_person_id: personId, p_email: normalizedEmail(email) }));
  await mergePeople(ctx, [row as unknown as TripPerson]);
}

export async function removeTripPerson(ctx: OnlineCtx, personId: string) {
  const t = ctx.store.getState().tables;
  const local = t.trip_people.get(personId);
  const referenced =
    [...t.expense_payments.values(), ...t.expense_splits.values()].some((r) => r.trip_person_id === personId) ||
    [...t.settlements.values()].some((s) => s.from_person_id === personId || s.to_person_id === personId);
  if (local?._pushed === null && !referenced) {
    // Never reached the server and nothing points at it: just drop it.
    await ctx.store.commit([{ table: "trip_people", key: personId, remove: true }]);
    return;
  }
  const row = await call(supabase.rpc("remove_trip_person", { p_person_id: personId }));
  await mergePeople(ctx, [row as unknown as TripPerson]);
}

export async function tripInviteUrl(ctx: OnlineCtx, tripId: string): Promise<string> {
  await ensureTripOnServer(ctx, tripId);
  const invite = (await call(supabase.rpc("get_or_create_trip_invite", { p_trip_id: tripId }))) as unknown as { token: string };
  return `${INVITE_URL_PREFIX}${invite.token}`;
}

export async function revokeTripInvite(_ctx: OnlineCtx, tripId: string) {
  await call(supabase.rpc("revoke_trip_invite", { p_trip_id: tripId }));
}

export async function joinTripWithInvite(ctx: OnlineCtx, token: string): Promise<{ tripId: string; tripName: string }> {
  const rows = await call(supabase.rpc("join_trip_with_invite", { p_token: token, p_person_id: uuid() }));
  const row = (Array.isArray(rows) ? rows[0] : rows) as { trip_id: string; trip_name: string } | undefined;
  if (!row) throw new RemoteError("This invite link is invalid or was turned off.", false);
  await ctx.sync.request({ tripId: row.trip_id });
  return { tripId: row.trip_id, tripName: row.trip_name };
}

/**
 * Finds or creates the hidden container shared by you and these people, the
 * home of non-group expenses between exactly this set of people.
 */
export async function resolveNonGroupContainer(ctx: OnlineCtx, people: { email: string; displayName: string }[]): Promise<string> {
  const self = ctx.user.email ? normalizedEmail(ctx.user.email) : `${ctx.user.id}@users.tab`;
  const seen = new Set<string>();
  const participants = people
    .map((p) => ({ email: normalizedEmail(p.email), display_name: p.displayName.trim().slice(0, 60) }))
    .filter((p) => p.email !== self && !seen.has(p.email) && seen.add(p.email));
  if (participants.length === 0) throw new RemoteError("Pick at least one other person.", false);

  const rows = (await call(
    supabase.rpc("resolve_or_create_non_group_container", { p_participants: participants }),
  )) as unknown as TripPerson[];
  const containerId = rows[0]?.trip_id;
  if (!containerId) throw new RemoteError("Couldn't set up this expense. Check your connection and try again.", true);
  const ops: Op[] = [];
  if (!ctx.store.getState().tables.trips.has(containerId)) {
    // A placeholder until the next pull brings the real row; never pushed.
    const now = new Date().toISOString();
    const write = uuid();
    ops.push({
      table: "trips",
      row: {
        id: containerId,
        name: "",
        kind: "non_group",
        member_signature: [...seen, self].sort().join("|"),
        created_by: ctx.user.id,
        last_activity_at: now,
        created_at: now,
        updated_at: now,
        deleted_at: null,
        write_id: write,
        _pushed: write,
      },
    });
  }
  for (const row of rows) ops.push({ table: "trip_people", row: { ...row, _pushed: row.write_id, _error: null } });
  await ctx.store.commit(ops);
  return containerId;
}
