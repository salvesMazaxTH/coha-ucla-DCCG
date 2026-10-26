-- Each account can own at most 24 decks. This trigger is the authority: the game client checks the same
-- number (DeckStore.MAX_DECKS) only to give a friendlier message, but a hand-made request is stopped here.
-- Safe to re-run. Accounts that already hold more than 24 keep their decks; they just cannot add new ones
-- until they are back under the limit (updates and deletes are not affected).

create or replace function public.enforce_deck_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  max_decks constant integer := 24;
  current_count integer;
begin
  -- Serialise concurrent inserts of the same user so two parallel requests cannot both slip under the limit.
  perform pg_advisory_xact_lock(hashtextextended(new.user_id::text, 0));
  select count(*) into current_count from public.decks d where d.user_id = new.user_id;
  if current_count >= max_decks then
    raise exception 'deck_limit_reached: at most % decks per account', max_decks
      using errcode = 'check_violation';
  end if;
  return new;
end;
$$;

drop trigger if exists decks_enforce_limit on public.decks;
create trigger decks_enforce_limit
before insert on public.decks
for each row execute function public.enforce_deck_limit();
