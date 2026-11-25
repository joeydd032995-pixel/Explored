-- Phase 4 — social expansion, territory games, analytics, privacy erasure.
-- Runs after 20261121_phase3_marketplace.sql. Identity model unchanged:
-- anonymous per-install user id, client-identified RLS.

-- ============================================================
-- Cell-claim sync (CRDT-style merge target from phase 2)
-- ============================================================
-- cell_claims already exists (20261121_phase2_boundaries.sql) keyed
-- (user_id, cell, entity_level, entity_id). Add device attribution and the
-- merge function used by the sync service.
alter table cell_claims add column if not exists device text not null default '';

create or replace function upsert_cell_claim(
    p_user_id uuid, p_cell text, p_level smallint, p_entity_id text,
    p_first_seen bigint, p_last_seen bigint, p_visits integer
) returns void language sql as $$
    insert into cell_claims (user_id, cell, entity_level, entity_id, first_seen, last_seen, visits, device)
    values (p_user_id, p_cell, p_level, p_entity_id, p_first_seen, p_last_seen, p_visits, '')
    on conflict (user_id, cell, entity_level, entity_id) do update
        set first_seen = least(cell_claims.first_seen, excluded.first_seen),
            last_seen  = greatest(cell_claims.last_seen, excluded.last_seen),
            visits     = greatest(cell_claims.visits, excluded.visits);
$$;

-- Erasure: the client identity can delete its own claims (privacy pillar).
create function delete_my_cell_claims(p_user_id uuid) returns void
language sql security definer set search_path = public as $$
    delete from cell_claims where user_id = p_user_id;
$$;

-- ============================================================
-- Social events (activity feed)
-- ============================================================
create table if not exists social_events (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    username text not null default 'explorer',
    kind text not null,                        -- 'state'|'county'|'city'|'layer'|'game'|'milestone'
    title text not null,                       -- human-readable, e.g. "first visited Texas"
    created_at timestamptz not null default now()
);
create index if not exists social_events_user_idx on social_events (user_id, created_at desc);
alter table social_events enable row level security;
create policy "social events read" on social_events for select using (true);
create policy "social events insert" on social_events for insert with check (true);
create policy "social events delete own" on social_events for delete
    using (user_id::text = coalesce(auth.uid()::text, user_id::text));

-- ============================================================
-- Territory Games
-- ============================================================
create table if not exists game_sessions (
    id uuid primary key default gen_random_uuid(),
    mode text not null check (mode in ('king_of_the_hill','claim_and_defend','contested_nodes')),
    host_user_id uuid not null,
    host_name text not null default 'explorer',
    status text not null default 'lobby' check (status in ('lobby','live','ended')),
    params jsonb not null default '{}',        -- mode setup: hills/nodes, radius, duration
    invite_code text not null unique,
    duration_s integer not null default 600,
    created_at timestamptz not null default now(),
    started_at timestamptz,
    ended_at timestamptz
);
create index if not exists game_sessions_status_idx on game_sessions (status) where status in ('lobby','live');
alter table game_sessions enable row level security;
create policy "game sessions read" on game_sessions for select using (true);
create policy "game sessions insert" on game_sessions for insert with check (true);
create policy "game sessions update" on game_sessions for update using (true);
create policy "game sessions delete host" on game_sessions for delete using (true);

create table if not exists game_players (
    session_id uuid not null references game_sessions(id) on delete cascade,
    user_id uuid not null,
    display_name text not null default 'explorer',
    color text not null default '#f5c518',
    lat double precision,
    lng double precision,
    score double precision not null default 0,
    last_ping bigint not null default 0,
    primary key (session_id, user_id)
);
alter table game_players enable row level security;
create policy "game players read" on game_players for select using (true);
create policy "game players write" on game_players for insert with check (true);
create policy "game players update" on game_players for update using (true);
create policy "game players delete own" on game_players for delete using (true);

-- Append-only scoring log (captures, flips, holds).
create table if not exists game_events (
    id uuid primary key default gen_random_uuid(),
    session_id uuid not null references game_sessions(id) on delete cascade,
    user_id uuid not null,
    kind text not null,                        -- 'capture'|'flip'|'hold'|'end'
    payload jsonb not null default '{}',
    created_at timestamptz not null default now()
);
create index if not exists game_events_session_idx on game_events (session_id, created_at desc);
alter table game_events enable row level security;
create policy "game events read" on game_events for select using (true);
create policy "game events insert" on game_events for insert with check (true);

-- ============================================================
-- Analytics (aggregates only — never coordinates)
-- ============================================================
create table if not exists app_metrics (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null,
    day date not null default current_date,
    metric text not null,                      -- 'map_frame_ms_p90'|'overlay_load_ms'|'overlays_active'|'game_sessions'
    value double precision not null default 0,
    created_at timestamptz not null default now()
);
create index if not exists app_metrics_day_idx on app_metrics (day, metric);
alter table app_metrics enable row level security;
create policy "app metrics insert" on app_metrics for insert with check (true);
create policy "app metrics read own" on app_metrics for select
    using (user_id::text = coalesce(auth.uid()::text, user_id::text));
create policy "app metrics delete own" on app_metrics for delete
    using (user_id::text = coalesce(auth.uid()::text, user_id::text));

-- Per-install log of marketplace installs by day (powers creator sparklines).
create table if not exists overlay_install_events (
    overlay_id uuid not null,
    user_id uuid not null,
    day date not null default current_date,
    unique (overlay_id, user_id, day)
);
alter table overlay_install_events enable row level security;
create policy "install events insert" on overlay_install_events for insert with check (true);
create policy "install events read" on overlay_install_events for select using (true);

-- Daily install counts for one overlay (creator analytics RPC).
create or replace function overlay_daily_installs(p_overlay_id text, p_days integer default 30)
returns table (day date, installs bigint) language sql security definer as $$
    select day, count(distinct user_id)
      from overlay_install_events
     where overlay_id::text = p_overlay_id
       and day >= current_date - (p_days - 1)
     group by day
     order by day;
$$;

-- Distinct installers, all time.
create or replace function overlay_active_users(p_overlay_id text)
returns bigint language sql security definer as $$
    select count(distinct user_id) from overlay_install_events where overlay_id::text = p_overlay_id;
$$;

-- ============================================================
-- Boundary releases (ingestion job writes; app reads)
-- ============================================================
create table if not exists boundary_releases (
    version text primary key,
    changed_entities jsonb not null default '[]',  -- [{level, id, name}]
    released_at timestamptz not null default now()
);
alter table boundary_releases enable row level security;
create policy "boundary releases read" on boundary_releases for select using (true);
create policy "boundary releases write" on boundary_releases for insert
    with check (true);
