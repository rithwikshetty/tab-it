-- 13. Privilege locking
-- ============================================================================
-- Raw profile rows are shared for display lookup, but activity_last_seen_at is
-- a private read cursor. Expose only non-sensitive profile columns to clients.
revoke select on public.profiles from authenticated;
grant select (id, display_name, avatar_url, created_at, updated_at, write_id)
  on public.profiles to authenticated;

-- Trigger functions exist only to be invoked by their triggers — they should
-- never be callable via /rest/v1/rpc. Revoke EXECUTE from public/anon/auth.
revoke execute on function public.handle_new_user()            from public, anon, authenticated;
revoke execute on function public.touch_trip_last_activity()   from public, anon, authenticated;
revoke execute on function public.set_sync_fields()            from public, anon, authenticated;
revoke execute on function public.sync_profile_name_to_trip_people() from public, anon, authenticated;
revoke execute on function public.validate_category_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_split_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_split_total(uuid) from public, anon, authenticated;
revoke execute on function public.validate_expense_split_total_from_expense_trigger() from public, anon, authenticated;
revoke execute on function public.validate_expense_split_total_from_split_trigger() from public, anon, authenticated;
revoke execute on function public.validate_expense_payment_row() from public, anon, authenticated;
revoke execute on function public.validate_expense_payment_total(uuid) from public, anon, authenticated;
revoke execute on function public.validate_expense_payment_total_from_expense_trigger() from public, anon, authenticated;
revoke execute on function public.validate_expense_payment_total_from_payment_trigger() from public, anon, authenticated;
revoke execute on function public.validate_settlement_row() from public, anon, authenticated;
revoke execute on function public.validate_trip_mute_pref_row() from public, anon, authenticated;
revoke execute on function public.purge_soft_deleted_records(timestamptz) from public, anon, authenticated;
revoke execute on function public.log_expense_activity()    from public, anon, authenticated;
revoke execute on function public.log_settlement_activity() from public, anon, authenticated;
revoke execute on function public.log_membership_activity() from public, anon, authenticated;
revoke execute on function public.log_trip_activity()       from public, anon, authenticated;
revoke execute on function public.guard_trip_kind()         from public, anon, authenticated;
revoke execute on function private.profile_display_name(uuid) from public, anon, authenticated;
revoke execute on function private.trip_name(uuid)            from public, anon, authenticated;
revoke execute on function private.person_display_name(uuid)  from public, anon, authenticated;
revoke execute on function private.money_text(numeric)        from public, anon, authenticated;

revoke execute on function public.ensure_current_profile(text, text) from public, anon;
grant  execute on function public.ensure_current_profile(text, text) to authenticated;
revoke execute on function public.create_trip_with_self(uuid, uuid, text) from public, anon;
grant  execute on function public.create_trip_with_self(uuid, uuid, text) to authenticated;
revoke execute on function public.add_trip_person_by_email(uuid, text, text, uuid) from public, anon;
grant  execute on function public.add_trip_person_by_email(uuid, text, text, uuid) to authenticated;
revoke execute on function public.claim_trip_people_for_current_email() from public, anon;
grant  execute on function public.claim_trip_people_for_current_email() to authenticated;
revoke execute on function public.suggest_trip_people(text, int) from public, anon;
grant  execute on function public.suggest_trip_people(text, int) to authenticated;
revoke execute on function public.update_trip_person_email(uuid, text) from public, anon;
grant  execute on function public.update_trip_person_email(uuid, text) to authenticated;
revoke execute on function public.remove_trip_person(uuid) from public, anon;
grant  execute on function public.remove_trip_person(uuid) to authenticated;
revoke execute on function public.create_expense_with_payments_and_splits(jsonb, jsonb, jsonb) from public, anon;
grant  execute on function public.create_expense_with_payments_and_splits(jsonb, jsonb, jsonb) to authenticated;
-- resolve_or_create_non_group_container privileges live in 19_rpc_non_group.sql:
-- the function is defined there, and this file sorts before it in the build.
revoke execute on function public.mark_activity_seen() from public, anon;
grant  execute on function public.mark_activity_seen() to authenticated;

-- private helpers are not PostgREST-exposed, but authenticated sessions need
-- EXECUTE for policy evaluation.
revoke execute on function private.is_trip_member(uuid) from public, anon;
grant  execute on function private.is_trip_member(uuid) to authenticated;
revoke execute on function private.is_profile_trip_member(uuid, uuid) from public, anon;
grant  execute on function private.is_profile_trip_member(uuid, uuid) to authenticated;
revoke execute on function private.is_profile_trip_member_any(uuid, uuid) from public, anon;
grant  execute on function private.is_profile_trip_member_any(uuid, uuid) to authenticated;
revoke execute on function private.is_trip_person(uuid, uuid) from public, anon;
grant  execute on function private.is_trip_person(uuid, uuid) to authenticated;
revoke execute on function private.normalized_email(text) from public, anon;
grant  execute on function private.normalized_email(text) to authenticated;
revoke execute on function private.current_auth_email() from public, anon;
grant  execute on function private.current_auth_email() to authenticated;
revoke execute on function private.receipt_object_trip_id(text) from public, anon;
grant  execute on function private.receipt_object_trip_id(text) to authenticated;
revoke execute on function private.receipt_object_expense_id(text) from public, anon;
grant  execute on function private.receipt_object_expense_id(text) to authenticated;
revoke execute on function private.can_read_receipt_object(text) from public, anon;
grant  execute on function private.can_read_receipt_object(text) to authenticated;
revoke execute on function private.can_write_receipt_object(text) from public, anon;
grant  execute on function private.can_write_receipt_object(text) to authenticated;
