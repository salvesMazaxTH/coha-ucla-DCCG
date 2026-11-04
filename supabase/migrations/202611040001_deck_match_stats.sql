-- Only the authoritative match server may insert results. Clients may read their own.
create table if not exists public.deck_match_results (
  match_id text not null,
  seat smallint not null check (seat in (0, 1)),
  user_id uuid not null references auth.users (id) on delete cascade,
  deck_key text not null check (char_length(deck_key) between 1 and 100),
  result text not null check (result in ('win', 'loss', 'draw')),
  created_at timestamptz not null default now(),
  primary key (match_id, seat)
);

create index if not exists deck_match_results_user_deck_idx
  on public.deck_match_results (user_id, deck_key);

alter table public.deck_match_results enable row level security;
revoke all on public.deck_match_results from public, anon, authenticated;
grant select on public.deck_match_results to authenticated;

drop policy if exists "Users can read their own match results" on public.deck_match_results;
create policy "Users can read their own match results"
  on public.deck_match_results for select to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.record_deck_match_results(p_results jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.deck_match_results (match_id, seat, user_id, deck_key, result)
  select r.match_id, r.seat, r.user_id, r.deck_key, r.result
  from jsonb_to_recordset(p_results)
    as r(match_id text, seat smallint, user_id uuid, deck_key text, result text)
  on conflict (match_id, seat) do nothing;
$$;

revoke all on function public.record_deck_match_results(jsonb) from public, anon, authenticated;
grant execute on function public.record_deck_match_results(jsonb) to service_role;

-- security_invoker keeps the underlying per-user RLS in force.
create or replace view public.deck_match_stats
with (security_invoker = true)
as
select user_id, deck_key, count(*)::integer as games,
  count(*) filter (where result = 'win')::integer as wins,
  count(*) filter (where result = 'loss')::integer as losses,
  count(*) filter (where result = 'draw')::integer as draws
from public.deck_match_results
group by user_id, deck_key;

revoke all on public.deck_match_stats from public, anon, authenticated;
grant select on public.deck_match_stats to authenticated;
