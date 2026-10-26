-- Follow-up migration: remove any default grants that may expose public tables.
-- Policies and table grants are both required for Supabase Data API access.
revoke all on public.profiles from public, anon, authenticated;
revoke all on public.decks from public, anon, authenticated;

grant select, update (username, display_name) on public.profiles to authenticated;
grant select, insert, update, delete on public.decks to authenticated;
