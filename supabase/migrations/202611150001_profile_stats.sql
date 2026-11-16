-- Profile statistics. Older rows keep these columns null: the client then falls back to the deck's
-- current contents, and the "times played" numbers simply start counting from this migration on.
alter table public.deck_match_results
  add column if not exists leader_id text check (leader_id is null or char_length(leader_id) between 1 and 100),
  add column if not exists deck_cards jsonb check (deck_cards is null or jsonb_typeof(deck_cards) = 'object'),
  add column if not exists deck_domains text[],
  add column if not exists card_plays jsonb check (card_plays is null or jsonb_typeof(card_plays) = 'object');

create index if not exists deck_match_results_user_created_idx
  on public.deck_match_results (user_id, created_at desc);

-- Same signature as before: the server keeps calling it; the new fields are optional.
create or replace function public.record_deck_match_results(p_results jsonb)
returns void
language sql
security definer
set search_path = ''
as $$
  insert into public.deck_match_results
    (match_id, seat, user_id, deck_key, result, leader_id, deck_cards, deck_domains, card_plays)
  select r.match_id, r.seat, r.user_id, r.deck_key, r.result,
    r.leader_id, r.deck_cards, r.deck_domains, r.card_plays
  from jsonb_to_recordset(p_results)
    as r(match_id text, seat smallint, user_id uuid, deck_key text, result text,
      leader_id text, deck_cards jsonb, deck_domains text[], card_plays jsonb)
  on conflict (match_id, seat) do nothing;
$$;

revoke all on function public.record_deck_match_results(jsonb) from public, anon, authenticated;
grant execute on function public.record_deck_match_results(jsonb) to service_role;

-- The table's select grant and RLS policy already cover the new columns (owner reads own rows only).
