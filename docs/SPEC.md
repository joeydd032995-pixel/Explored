# USA Explorer — Geographic Discovery & Community Overlay Platform

**Version 1.0 · Phase 1 implemented · Phases 2–4 contracted below**

This document is the durable product + engineering specification. Phase 1 (this repo,
`ios/`) is implemented and builds clean; later phases extend it without breaking the
contracts defined here.

---

## 1. Product Intent

A discovery-centric mapping product that quantifies real-world exploration against
**authoritative administrative boundaries** and lets any user author, share, and
monetize **data overlays** registered to real-world coordinates. Visual language is
its own: dark-navy cartography, gold discovery accents, hexagonal fog-of-war. No
design, schema, or interaction language is derived from any proprietary map app.

## 2. Implemented in Phase 1 (iOS, SwiftUI)

### 2.1 Core discovery engine

- **Grid:** Uber H3 at resolution 7 (≈5.161 km² mean cell area) via SwiftyH3.
  Every GPS breadcrumb claims its cell exactly once (`discovered_hexes`).
- **Hierarchical entities:** states and counties. State attribution is
  **boundary-exact and offline**: every fix is matched against authoritative
  Census TIGER/Line-derived cartographic polygons (`Data/USStateBoundaries.json`,
  public domain) via bbox-prefiltered ray-casting point-in-polygon
  (`BoundaryService`) — no network required. Reverse geocoding still supplies
  county/city names and first-visit celebrations. The triggering H3 cell is
  attributed per level (`state_hexes`, `county_hexes`).
- **Dwell weighting:** every fix records a throttled visit (1 write per cell per
  5 min, `hex_visits`) so density thresholds can later distinguish transit from
  exploration without changing the unique-cell invariant.
- **Exact percentages:** `DiscoveryProgressEngine.StateProgress.percent` =
  unique claimed cells ÷ **exact H3 res-7 polyfill count of the state's boundary
  polygon** (computed once per state in the background, cached in
  `boundary_cell_counts` keyed by boundary version). Until a polyfill lands the
  engine falls back to the Census ALand estimate (ALand ÷ 5.161 km²) and the UI
  flags it with `≈`. 0.0000 %–100.00 %, four decimals below 0.01 %. National
  progress uses U.S. land area (9,147,593 km²) as an estimate. Residual
  unexplored surface = polygon area (Chamberlain–Duquette spherical area) −
  claimed × cell area. Per-state visit stats (`state_stats`) track last visit
  and cumulative geodesic distance traveled inside the polygon.
- **Progressive disclosure:** hex fog recedes on the real basemap; per-state rings
  and bars with cell/counties/cities/km²-remaining analytics in the Layers tab.
- **Offline-first:** all claims accumulate in the local encrypted-at-device SQLite
  store and sync stats to the backend opportunistically (Supabase, already
  configured) — nothing requires connectivity to keep working.
- **Background operation:** continuous tracking with
  `allowsBackgroundLocationUpdates`, auto-pause disabled, significant-change
  monitoring as a wake-up fallback, Always-authorization escalation. (Previous turn.)

### 2.2 Overlay plugin architecture (`Overlays/OverlayKit.swift`)

```swift
@MainActor protocol OverlayProvider: Identifiable {
    var id: String; var name: String; var summary: String
    var systemImage: String; var version: String; var isSensitive: Bool
    var featureCount: Int { get }
    func features(in region: MKCoordinateRegion) async -> [OverlayFeature]
    func submit(kind:coordinate:note:) async -> OverlayFeature?
    func confirm(_ feature: OverlayFeature) async -> OverlayFeature?
}
```

- `OverlayFeature` carries id, kind, WGS 84 coordinate, **confidence (0–1)**,
  **last-verified epoch**, **expiry epoch** (ephemeral), confirmations,
  **provenance string**. Viewport-filtered, expiry-pruned by the registry.
- New layers (air quality, historical markers, traffic, events) register with the
  `OverlayRegistry` — zero core changes.

**Reference implementation 1 — Camera Awareness** (`CameraOverlayProvider`):
versioned seed dataset (`Data/CameraSeedData.json`, provenance per record:
toll-authority gantries, municipal registries, public-records ALPR datasets) merged
with crowd-contributed points. Contribution starts at 0.40 confidence; each
"still accurate" verification adds +0.10 toward 0.99 and stamps `last_verified`.
Sensitive category — flagged `isSensitive`, elevated moderation server-side.

**Reference implementation 2 — Live Hazards** (`HazardOverlayProvider`):
ephemeral reports (police, speed trap, accident, road hazard, construction) with
per-kind TTLs (45 min – 24 h), automatic pruning, confirm-extends-expiry
(+50 % of TTL), offline-first local store, and id-keyed merge of remote reports.

### 2.3 Persistence & sync

- **Local (source of truth):** SQLite (`explorer.db`) — coordinates, discovered
  hexes, hex visits, state/county hex attribution, overlay points, hazard reports.
- **Backend:** Supabase (Rork-managed project) for profiles, friend graph, city
  nodes, and now `hazard_reports` / `camera_points` (client upserts + id-keyed
  merge; degraded to local-only when unconfigured).
- **Schema:** `supabase/migrations/20261120_overlay_platform.sql` — PostGIS
  geography columns (EPSG:4326) with GIST indexes, `confirm_hazard_report` RPC,
  marketplace tables, full RLS, and the phase-2 boundary-ingestion table outline
  (`boundaries_admin`, `cell_claims`).

### 2.4 Screens

- **Map** — basemap + fog + travel path + overlay annotations (color-coded by
  kind), HUD: share, live-hazard report, layer filters; tap a feature for its
  provenance/confidence card with confirm workflow; long-press check-in retained.
- **Layers** — national %, per-state progress bars with exact polygon
  denominators (≈ = interim area estimate), last-visit/distance analytics,
  county- and city-level progress sections, overlay registry status,
  marketplace preview.
- Stats / Friends unchanged.

## 3. Contracts for Later Phases

**Phase 2 — boundary ingestion pipeline (device side implemented; server tables live).**
Exact, offline, boundary-based discovery now reaches the **city level**:
Census place polygons (24,516 incorporated places + CDPs, 1:500k, public
domain) are DP-simplified (~670 m) and bundled raw-deflate
(`Data/USCityBoundaries.json.deflate`, built by `tools/make-city-boundaries.js`),
alongside county (`USCountyBoundaries.json.deflate`) and state polygons.
`BoundaryService` does bbox-prefiltered ray-casting PIP at all three levels,
computes exact Chamberlain–Duquette areas and per-entity res-7 polyfill
denominators (cached in `boundary_cell_counts`, versioned), and owns all
hex→entity attribution — reverse geocoding only adds names/celebrations.
County/city keys reuse the geocoder's `StateName-Name` convention; city
denominators floor at 1 cell (small places may contain no res-7 cell center).
New tables: `city_hexes`; new UI: Counties and Cities & Places progress
sections in Layers. Server side: `20261121_phase2_boundaries.sql` adds
`boundaries_admin` (source-tagged, version-bumped, `total_cells`),
`cell_claims`, and the `boundary_entity_at` / `entity_progress` functions;
the scheduled ingestion job is `tools/ingest-boundaries.js` (see phase 4).

**Phase 3 — creator marketplace (built end-to-end; store configured).** `overlay_definitions`
(spec JSONB: `feature_kind` + category + point features; visibility private/shared/public;
pricing free/paid — paid layers unlock through the single monthly All-Access Pass
entitlement `all_access`; `category` drives elevated moderation — cameras/enforcement
publish as `pending_review`), `overlay_reviews` (one per person per layer, upsert),
`overlay_reports`, `increment_overlay_installs` RPC, client-identified RLS
(`20261121_phase3_marketplace.sql`). Client: `MarketplaceService` (install/uninstall
persisted on device, catalog from Supabase), `MarketplaceOverlayProvider` (read-only
points provider), `PassService` (RevenueCat, 24 h offline grace, tied to the local
explorer id via logIn), Marketplace UI in Layers tab: browse/search/detail, reviews,
report flow, Creator Studio (pin-drop authoring, publish), My Layers analytics,
Apple-compliant paywall (price headline, restore, EULA + privacy links).
RevenueCat Test Store is live: app `appe329bba038`, entitlement `all_access`,
product `all_access_monthly` P1M $4.99, current offering `marketplace`;
the public SDK key ships as `RORK_PUBLIC_REVENUECAT_IOS_API_KEY`.

**Phase 4 — Territory Games, offline merge, analytics, boundary notifications,
privacy (built; multiplayer verified server-side, two-device play pending).**
Migration `20261122_phase4_social_games.sql`: `social_events`, `game_sessions` /
`game_players` / `game_events`, `app_metrics`, `overlay_install_events` +
`overlay_daily_installs` / `overlay_active_users` RPCs, `boundary_releases`,
`upsert_cell_claim` merge RPC (LEAST/GREATEST) and `delete_my_cell_claims`, all
client-identified RLS — all smoke-tested over REST.

- **Offline reconciliation** — `CellClaimSyncService` (5-min loop) pushes unsynced
  `state/county/city_hexes` rows (new `synced` flags + partial indexes) via
  `upsert_cell_claim` and pulls the explorer's other-device claims, union-merging
  locally: cells additive, first_seen min, last_seen/visits max; milestones and
  stats re-derive after a merge.
- **Territory Games** — `GameService`: create/join (6-char invite code + open
  sessions list), lobby → live → results; hills/nodes seeded around the host's
  location. First-wave modes: King of the Hill, Claim & Defend (hills decay ~2%/s
  unattended), Contested Nodes (out-hold to flip, captures logged in `game_events`).
  Polling (~2s PostgREST upsert/select) instead of Realtime in v1; each device
  scores its own progress (friends/honor model). Live position sharing exists
  ONLY inside a live session — player rows are deleted on leave and at end.
  UI: Territory Games card in Stats → `GameViews` lobby/live map/results/rematch.
- **Social** — `social_events` feed (milestones, layer publishes, game starts)
  atop the Friends tab; leaderboard metric tabs (nodes/states/counties/cities
  from `user_stats`); friend profile sheet gains a side-by-side comparison.
- **Analytics** — `app_metrics` daily rollups (map frame ms p90, overlay load ms,
  overlays active, game sessions — aggregates only, never coordinates); creators
  get 30-day install sparklines in My Layers.
- **Boundary updates** — `tools/ingest-boundaries.js` (service-role scheduled job:
  fetch Census boundaries, diff via deterministic `total_cells`, upsert + version
  bump, write `boundary_releases`); the app checks the latest release on launch
  and posts a local notification listing changed areas.
- **Privacy** — `PrivacyService` + Privacy settings (Stats tab, hand icon):
  pause-all-tracking master gate in `LocationService`, delete-by-date-range
  (breadcrumbs/visits/state stats), JSON export via share sheet, full erasure
  (local wipe + `delete_my_cell_claims` / metrics / social events under the
  client identity).

## 4. OpenAPI Sketch (backend, phase 2+)

```
GET  /v1/overlays?bbox=...&kinds=...        → OverlayFeature[] (filtered, paginated)
POST /v1/overlays/{provider}/features       → 201 OverlayFeature  (auth)
POST /v1/overlays/features/{id}/confirm     → 200 OverlayFeature
GET  /v1/discovery/entities/{id}/progress   → { percent, claimed, total, firstVisit }
GET  /v1/marketplace/overlays?q=...         → OverlayDefinition[]
POST /v1/marketplace/overlays               → 201 OverlayDefinition  (creator)
POST /v1/purchases/validate                 → { entitlement }        (StoreKit 2 receipt)
DELETE /v1/me/location-history              → 204  (GDPR/CCPA erasure)
GET    /v1/me/export                        → data export bundle
```

## 5. Privacy & Compliance Notes

- Location breadcrumbs stay **on device** by default; only aggregate stats
  (states/counties/hex counts) sync. Feature coordinates are inherently public
  map data; **reporter identity is not stored client-side** and RLS keeps pending
  contributions private.
- Built (phase 4): pause-all-tracking switch, selective deletion per date range,
  JSON data export, full erasure (local + server cell claims/metrics/feed).
  Approximate-location mode and retention windows remain future work.
- Camera/enforcement overlays always render provenance + confidence + last-verified;
  unverified community points start at 0.40 confidence and cannot display as
  authoritative.

## 6. Success Metrics

Regions progressed per active user · validated H3 cells claimed · overlay
consumption/creation retention · marketplace liquidity (phase 3) · accuracy-report
rate and confirmation ratio per overlay.
