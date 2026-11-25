-- Overlay platform schema — phase 1 (reference overlays) + phase 3 scaffolding
-- Run in Supabase SQL editor. PostGIS is required for authoritative boundary
-- storage; enable it first: CREATE EXTENSION IF NOT EXISTS postgis;

-- ============================================================
-- Real-time hazard & enforcement overlay (Waze-style, ephemeral)
-- ============================================================
create table if not exists hazard_reports (
    id text primary key,
    kind text not null check (kind in ('police','speed_trap','accident','road_hazard','construction')),
    lat double precision not null check (lat between -90 and 90),
    lng double precision not null check (lng between -180 and 180),
    created_at bigint not null,          -- epoch seconds (client clock, offline-first)
    expires_at bigint not null,          -- epoch seconds; rows older than this are dead
    confirmations integer not null default 0,
    reporter_user_id uuid null,
    -- Georeferencing in WGS 84 (EPSG:4326); PostGIS column for spatial queries.
    geom geography(point, 4326) generated always as
        (case when lat is not null and lng is not null
              then st_setsrid(st_makepoint(lng, lat), 4326)::geography end) stored
);

create index if not exists hazard_reports_expires_idx on hazard_reports (expires_at);
create index if not exists hazard_reports_geom_idx on hazard_reports using gist (geom);

-- Atomic confirm: bumps confirmations and extends expiry.
create or replace function confirm_hazard_report(p_report_id text, p_new_expiry bigint)
returns void language plpgsql as $$
begin
    update hazard_reports
       set confirmations = confirmations + 1,
           expires_at = greatest(expires_at, p_new_expiry)
     where id = p_report_id and expires_at > (extract(epoch from now()))::bigint;
end;
$$;

-- ============================================================
-- Camera-awareness overlay (DeFlock-style, moderated, permanent)
-- ============================================================
create table if not exists camera_points (
    id text primary key,
    kind text not null check (kind in ('alpr_fixed','alpr_mobile','toll_gantry','red_light')),
    lat double precision not null check (lat between -90 and 90),
    lng double precision not null check (lng between -180 and 180),
    note text not null default '',
    confidence real not null default 0.4,
    confirmations integer not null default 0,
    last_verified bigint not null default 0,
    status text not null default 'pending' check (status in ('pending','approved','rejected')),
    source text not null default 'community',
    reporter_user_id uuid null,
    geom geography(point, 4326) generated always as
        (case when lat is not null and lng is not null
              then st_setsrid(st_makepoint(lng, lat), 4326)::geography end) stored,
    created_at timestamptz not null default now()
);

create index if not exists camera_points_geom_idx on camera_points using gist (geom);
create index if not exists camera_points_status_idx on camera_points (status) where status = 'approved';

-- ============================================================
-- Phase 3 scaffolding: creator overlay marketplace
-- ============================================================
create table if not exists overlay_definitions (
    id uuid primary key default gen_random_uuid(),
    creator_user_id uuid not null,
    name text not null,
    version integer not null default 1,
    -- Plugin contract: geometry types, style JSON, clustering rules, metadata schema.
    spec jsonb not null,
    coordinate_system text not null default 'EPSG:4326',
    visibility text not null default 'private' check (visibility in ('private','shared','public')),
    pricing text not null default 'free' check (pricing in ('free','paid')),
    price_usd numeric(10,2),
    store_product_id text,               -- StoreKit 2 / Play Billing product id
    category text not null default 'general',  -- 'cameras'/'enforcement' get elevated moderation
    rating_avg real not null default 0,
    rating_count integer not null default 0,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists overlay_reviews (
    id uuid primary key default gen_random_uuid(),
    overlay_id uuid not null references overlay_definitions(id) on delete cascade,
    user_id uuid not null,
    rating smallint not null check (rating between 1 and 5),
    body text not null default '',
    created_at timestamptz not null default now(),
    unique (overlay_id, user_id)
);

-- ============================================================
-- Row Level Security
-- ============================================================
alter table hazard_reports enable row level security;
alter table camera_points enable row level security;
alter table overlay_definitions enable row level security;
alter table overlay_reviews enable row level security;

-- Hazards: world-readable while active; only the reporter can mutate.
create policy "hazard read" on hazard_reports for select using (true);
create policy "hazard insert" on hazard_reports for insert with check (true);
create policy "hazard update" on hazard_reports for update using (reporter_user_id = auth.uid());

-- Cameras: approved points world-readable; pending only to the reporter.
create policy "camera read" on camera_points for select
    using (status = 'approved' or reporter_user_id = auth.uid());
create policy "camera insert" on camera_points for insert with check (true);

-- Marketplace: public overlays world-readable; creators own their definitions.
create policy "overlay read" on overlay_definitions for select
    using (visibility = 'public' or creator_user_id = auth.uid());
create policy "overlay insert" on overlay_definitions for insert with check (creator_user_id = auth.uid());
create policy "overlay update" on overlay_definitions for update using (creator_user_id = auth.uid());
create policy "overlay delete" on overlay_definitions for delete using (creator_user_id = auth.uid());
create policy "review read" on overlay_reviews for select using (true);
create policy "review write" on overlay_reviews for insert with check (user_id = auth.uid());

-- ============================================================
-- Phase 2+ (boundary ingestion jobs — run via CI, not RLS tables):
--   boundaries_admin (osm_id bigint, level smallint, name text,
--                     version integer, geom geography(multipolygon, 4326),
--                     source text check (source in ('osm','tiger','gadm','natural_earth')),
--                     fetched_at timestamptz)
--   cell_claims (user_id uuid, cell text, entity_level smallint, entity_id text,
--                first_seen bigint, last_seen bigint, visits integer,
--                primary key (user_id, cell, entity_id))
-- Ingestion: download TIGER/Line & OSM admin dumps on schedule, diff against
-- current rows, upsert changed relations, and bump `version` so clients can
-- notify users when boundary updates change their percentages.
-- ============================================================
