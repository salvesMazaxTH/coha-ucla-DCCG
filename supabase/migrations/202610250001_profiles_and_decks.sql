-- Supabase foundation for browser accounts and saved user decks.
-- Safe to re-run in an existing project.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text not null unique,
  display_name text not null default '',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint profiles_username_format check (username ~ '^[a-z0-9_]{3,24}$')
);

create table if not exists public.decks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 60),
  content jsonb not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint decks_content_format check (
    jsonb_typeof(content) = 'object'
    and jsonb_typeof(content -> 'leader') = 'string'
    and jsonb_typeof(content -> 'cards') = 'object'
  )
);

create index if not exists decks_user_updated_idx
  on public.decks (user_id, updated_at desc);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists decks_set_updated_at on public.decks;
create trigger decks_set_updated_at
before update on public.decks
for each row execute function public.set_updated_at();

-- Create a usable initial username from Google metadata/email. A suffix makes
-- collisions safe; users can later change it through the profile form.
create or replace function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_name text;
  candidate text;
  suffix text;
  full_name text;
begin
  full_name := coalesce(
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'name', ''),
    ''
  );
  base_name := lower(regexp_replace(
    coalesce(nullif(new.raw_user_meta_data ->> 'preferred_username', ''), split_part(coalesce(new.email, 'jogador'), '@', 1)),
    '[^a-zA-Z0-9_]', '', 'g'
  ));
  base_name := left(base_name, 17);
  if char_length(base_name) < 3 then
    base_name := 'jogador';
  end if;
  candidate := base_name;

  while exists (select 1 from public.profiles p where p.username = candidate) loop
    suffix := lpad(floor(random() * 100000)::text, 5, '0');
    candidate := left(base_name, 18) || suffix;
  end loop;

  insert into public.profiles (id, username, display_name)
  values (new.id, candidate, full_name);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
after insert on auth.users
for each row execute function public.create_profile_for_new_user();

alter table public.profiles enable row level security;
alter table public.decks enable row level security;

drop policy if exists "Users can read their own profile" on public.profiles;
create policy "Users can read their own profile"
  on public.profiles for select to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

drop policy if exists "Users can manage their own decks" on public.decks;
create policy "Users can manage their own decks"
  on public.decks for all to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

grant select, update (username, display_name) on public.profiles to authenticated;
grant select, insert, update, delete on public.decks to authenticated;

