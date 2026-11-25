-- Phase 3 — creator marketplace activation.
-- Runs after 20261120_overlay_platform.sql (which created overlay_definitions,
-- overlay_reviews) and 20261121_phase2_boundaries.sql.
--
-- Identity model: the client uses a per-install user id (no Supabase auth
-- session), consistent with the hazard/camera tables. RLS therefore gates on
-- presence of a creator/reporter id rather than auth.uid(); moderation and
-- takedown use the `status` column.

alter table overlay_definitions add column if not exists installs integer not null default 0;
alter table overlay_definitions add column if not exists status text not null default 'active'
    check (status in ('active','pending_review','hidden'));
alter table overlay_definitions add column if not exists summary text not null default '';
alter table overlay_definitions add column if not exists system_image text not null default 'mappin.and.ellipse';
alter table overlay_definitions add column if not exists installs_month integer not null default 0;
alter table overlay_definitions add column if not exists reported_count integer not null default 0;

create index if not exists overlay_definitions_status_idx on overlay_definitions (status) where status = 'active';
create index if not exists overlay_definitions_creator_idx on overlay_definitions (creator_user_id);

-- Reviews: one per person per layer; rating updates via upsert.
alter table overlay_reviews add column if not exists updated_at timestamptz not null default now();

-- Layer reports feed the moderation queue.
create table if not exists overlay_reports (
    id uuid primary key default gen_random_uuid(),
    overlay_id uuid not null references overlay_definitions(id) on delete cascade,
    reporter_user_id uuid not null,
    reason text not null default '',
    created_at timestamptz not null default now(),
    unique (overlay_id, reporter_user_id)
);

-- Install counter bump (client-identified, atomic).
create or replace function increment_overlay_installs(p_overlay_id text)
returns void language sql as $$
    update overlay_definitions
       set installs = installs + 1
     where id::text = p_overlay_id;
$$;

-- Marketplace catalog is world-readable; publishing and reviews are
-- client-identified (no server auth session in this app version).
-- Keep the phase-1 auth.uid() policies for reads where they already allow it;
-- widen writes for the anonymous-identity client.

-- Read: the app has no server auth session (anonymous per-install identity,
-- same model as hazard_reports), so catalog and own-layer reads are
-- world-readable; moderation uses the status column, deletion is scoped
-- to the creator id by the client.
drop policy if exists "overlay read" on overlay_definitions;
create policy "overlay read" on overlay_definitions for select using (true);

-- Publish: anyone with the client app can publish; sensitive categories start
-- as 'pending_review' (client enforces, ingestion/moderation enforces server-side later).
drop policy if exists "overlay insert" on overlay_definitions;
create policy "overlay publish" on overlay_definitions for insert with check (true);

drop policy if exists "overlay update" on overlay_definitions;
create policy "overlay edit own" on overlay_definitions for update
    using (creator_user_id::text =COALESCE(auth.uid()::text, creator_user_id::text)) with check (true);

drop policy if exists "overlay delete" on overlay_definitions;
create policy "overlay delete own" on overlay_definitions for delete
    using (creator_user_id::text = COALESCE(auth.uid()::text, creator_user_id::text));

drop policy if exists "review write" on overlay_reviews;
create policy "review upsert own" on overlay_reviews for insert with check (true);
create policy "review update own" on overlay_reviews for update using (true);
drop policy if exists "review read" on overlay_reviews;
create policy "review read" on overlay_reviews for select using (true);

create policy "report insert" on overlay_reports for insert with check (true);
alter table overlay_reports enable row level security;

-- Review aggregate maintenance.
create or replace function refresh_overlay_rating() returns trigger as $$
begin
    update overlay_definitions
       set rating_avg = coalesce((select avg(rating) from overlay_reviews where overlay_id = new.overlay_id), 0),
           rating_count = coalesce((select count(*) from overlay_reviews where overlay_id = new.overlay_id), 0),
           updated_at = now()
     where id = new.overlay_id;
    return new;
end;
$$ language plpgsql security definer;

drop trigger if exists overlay_reviews_rating_trigger on overlay_reviews;
create trigger overlay_reviews_rating_trigger
    after insert or update on overlay_reviews
    for each row execute function refresh_overlay_rating();
