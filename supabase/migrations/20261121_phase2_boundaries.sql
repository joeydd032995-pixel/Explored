-- Phase 2 — boundary ingestion pipeline + cross-device cell-claim merge.
-- Run in Supabase SQL editor (PostGIS required, see phase-1 migration).
--
-- Ingestion (CI job, service role — not exposed to clients):
--   1. Download Census TIGER/Line cartographic boundaries (states, counties,
--      places) and OSM admin relations on schedule.
--   2. Diff against boundaries_admin rows; upsert changed geometries and
--      bump `version` per entity.
--   3. Compute `total_cells` per entity: exact H3 res-7 polyfill count
--      (matches the client's BoundaryService algorithm; PostGIS can verify
--      a sample with ST_Contains against generated cell centers).
-- Clients compare `version`/`boundary_version` and recompute affected
-- percentages when boundaries change.

-- ============================================================
-- boundaries_admin — versioned, source-tagged entity polygons
-- ============================================================
create table if not exists boundaries_admin (
    id text primary key,                       -- e.g. 'tiger:state:48', 'tiger:place:4825548'
    level smallint not null,                   -- 2 = state, 3 = county, 4 = city/place
    name text not null,
    source text not null check (source in ('osm','tiger','gadm','natural_earth')),
    version integer not null default 1,
    total_cells integer,                       -- exact res-7 polyfill count (ingestion-computed)
    geom geography(multipolygon, 4326) not null,
    fetched_at timestamptz not null default now()
);

create index if not exists boundaries_admin_geom_idx on boundaries_admin using gist (geom);
create index if not exists boundaries_admin_level_idx on boundaries_admin (level, id);

-- World-readable reference data; writes happen only via the service role.
alter table boundaries_admin enable row level security;
create policy "boundaries read" on boundaries_admin for select using (true);

-- Server-side point-in-boundary lookup (verification of offline attribution).
create or replace function boundary_entity_at(p_lat double precision, p_lng double precision, p_level smallint)
returns table (id text, name text, source text, version integer)
language sql stable as $$
    select id, name, source, version
      from boundaries_admin
     where level = p_level
       and st_contains(geom::geometry, st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geometry)
     limit 1;
$$;

-- ============================================================
-- cell_claims — per-user H3 claim ledger for entity progress
-- ============================================================
-- Mirrors the on-device state_hexes/county_hexes/city_hexes tables so
-- percentages survive device loss and can be computed server-side.
create table if not exists cell_claims (
    user_id uuid not null,
    cell text not null,                        -- H3 cell index (res 7)
    entity_level smallint not null check (entity_level between 2 and 4),
    entity_id text not null,                   -- boundaries_admin.id
    first_seen bigint not null,
    last_seen bigint not null,
    visits integer not null default 1,
    primary key (user_id, cell, entity_level, entity_id)
);

create index if not exists cell_claims_entity_idx on cell_claims (entity_level, entity_id);

alter table cell_claims enable row level security;
create policy "claims read own" on cell_claims for select using (user_id = auth.uid());
create policy "claims insert own" on cell_claims for insert with check (user_id = auth.uid());

-- Authoritative entity progress: exact denominator from boundaries_admin,
-- numerator from the caller's claims.
create or replace function entity_progress(p_level smallint, p_entity_id text, p_user uuid)
returns table (claimed bigint, total integer, percent double precision)
language sql stable as $$
    select count(b.cell) as claimed,
           coalesce(ba.total_cells, 0) as total,
           case when coalesce(ba.total_cells, 0) > 0
                then least(100.0, count(b.cell)::double precision / ba.total_cells * 100.0)
                else 0 end as percent
      from boundaries_admin ba
      left join cell_claims b
             on b.entity_level = ba.level and b.entity_id = ba.id and b.user_id = p_user
     where ba.level = p_level and ba.id = p_entity_id
     group by ba.total_cells;
$$;
