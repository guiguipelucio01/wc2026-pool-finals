-- WC2026 Office Pool schema (v2 — real email+password login via Supabase Auth)
-- Run this in Supabase SQL Editor. It drops and recreates the pool tables,
-- which is safe as long as no real picks need to be preserved (test data only).

drop table if exists pool_picks;
drop table if exists pool_players;
drop table if exists pool_results;

-- Players — one row per registered user. id = their auth.users id.
create table pool_players (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null unique,
  email text,
  is_admin boolean not null default false,
  created_at timestamptz default now()
);

-- Picks — one row per market per player
create table pool_picks (
  id uuid default gen_random_uuid() primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  player_name text not null,
  market_id text not null,
  pick text not null,
  submitted_at timestamptz default now(),
  unique(user_id, market_id)
);

-- Results — one row per market — organizer fills in
create table pool_results (
  market_id text primary key,
  result text,
  updated_at timestamptz default now()
);

-- RLS
alter table pool_players enable row level security;
alter table pool_picks   enable row level security;
alter table pool_results enable row level security;

-- Players: any logged-in user can read the list (leaderboard), but can only
-- create/update their own row.
create policy "read_players" on pool_players for select to authenticated using (true);
create policy "insert_own_player" on pool_players for insert to authenticated with check (auth.uid() = id);
create policy "update_own_player" on pool_players for update to authenticated using (auth.uid() = id);

-- Picks: any logged-in user can read all picks (leaderboard/scoring), but can
-- only write their own.
create policy "read_picks" on pool_picks for select to authenticated using (true);
create policy "insert_own_picks" on pool_picks for insert to authenticated with check (auth.uid() = user_id);
create policy "update_own_picks" on pool_picks for update to authenticated using (auth.uid() = user_id);

-- Results: any logged-in user can read; only players flagged is_admin=true can write.
create policy "read_results" on pool_results for select to authenticated using (true);
create policy "admin_insert_results" on pool_results for insert to authenticated
  with check (exists (select 1 from pool_players where id = auth.uid() and is_admin = true));
create policy "admin_update_results" on pool_results for update to authenticated
  using (exists (select 1 from pool_players where id = auth.uid() and is_admin = true));

-- After deploying, sign up through the live site with your own account, then
-- run this once (with your email) to make yourself the admin:
-- update pool_players set is_admin = true where email = 'you@example.com';

-- ── v3 — admin-controlled open/close switch for picks ──────────────────────
-- Purely additive: safe to run once against an existing database, does not
-- touch pool_players/pool_picks/pool_results. Single-row settings table.
create table if not exists pool_settings (
  id boolean primary key default true,
  picks_open boolean not null default true,
  updated_at timestamptz default now(),
  constraint pool_settings_singleton check (id)
);
insert into pool_settings (id, picks_open) values (true, true) on conflict (id) do nothing;

alter table pool_settings enable row level security;
create policy "read_settings" on pool_settings for select to authenticated using (true);
create policy "admin_update_settings" on pool_settings for update to authenticated
  using (exists (select 1 from pool_players where id = auth.uid() and is_admin = true));

-- ── v4 — per-match open/close control (replaces the single picks_open switch) ──
-- Lets the admin close picks for one match (e.g. 3rd Place, once it kicks off)
-- while leaving another (e.g. the Final) open. Keys are the market_id prefix:
-- 't3' = 3rd Place Match, 'fin' = World Cup Final, 't' = Tournament Awards.
alter table pool_settings drop column if exists picks_open;
alter table pool_settings add column if not exists group_open jsonb not null
  default '{"t3":true,"fin":true,"t":true}'::jsonb;
