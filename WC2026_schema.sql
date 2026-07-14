-- WC2026 Office Pool schema
-- Run this in Supabase SQL Editor

-- Players (one row per person who registers)
create table if not exists pool_players (
  id uuid default gen_random_uuid() primary key,
  name text not null unique,
  email text,
  created_at timestamptz default now()
);

-- Picks (one row per market per player)
create table if not exists pool_picks (
  id uuid default gen_random_uuid() primary key,
  player_name text not null,
  market_id text not null,
  pick text not null,
  submitted_at timestamptz default now(),
  unique(player_name, market_id)
);

-- Results (one row per market — organizer fills in)
create table if not exists pool_results (
  market_id text primary key,
  result text,
  updated_at timestamptz default now()
);

-- RLS
alter table pool_players enable row level security;
alter table pool_picks   enable row level security;
alter table pool_results enable row level security;

-- Anyone can register and submit picks
create policy "anyone_insert_players" on pool_players for insert to anon with check (true);
create policy "anyone_read_players"   on pool_players for select to anon using (true);
create policy "anyone_insert_picks"   on pool_picks   for insert to anon with check (true);
create policy "anyone_read_picks"     on pool_picks   for select to anon using (true);
create policy "anyone_read_results"   on pool_results for select to anon using (true);

-- Only service role can insert results (admin)
create policy "service_insert_results" on pool_results for all to service_role using (true) with check (true);
create policy "service_update_picks"   on pool_picks   for update to service_role using (true);
