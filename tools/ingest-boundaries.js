#!/usr/bin/env bun
/**
 * Phase 4 boundary ingestion job — scheduled, runs with the service role.
 *
 * Fetches the current U.S. state cartographic boundaries (Census-derived
 * GeoJSON), diffs them against `boundaries_admin` using the deterministic
 * res-7 cell count (`total_cells`) as the change signal, upserts changed
 * geometries with a per-entity version bump, and — when anything changed —
 * writes a `boundary_releases` row. Clients (iOS app) compare the release
 * version on launch and post a local notification when percentages move.
 *
 * Env (run through `rork env run -- bun tools/ingest-boundaries.js`):
 *   EXPO_PUBLIC_SUPABASE_URL      project URL
 *   SUPABASE_SERVICE_ROLE_KEY     service role key (server only)
 *
 * Optional exact polyfill: if the `h3` package is importable, total_cells is
 * an exact res-7 polyfill; otherwise a spherical-area estimate (~5.16 km² per
 * res-7 cell) is used. Both are deterministic for a given geometry, which is
 * all the diff needs.
 */

const SUPABASE_URL = process.env.EXPO_PUBLIC_SUPABASE_URL ?? process.env.SUPABASE_URL ?? "";
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY ?? "";
const LEVEL = 2; // states; counties/places follow the same pattern at scale
const SOURCE_URL =
  "https://raw.githubusercontent.com/PublicaMundi/MappingAPI/master/data/geojson/us-states.json";

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error("Missing EXPO_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY");
  process.exit(1);
}

const headers = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  "Content-Type": "application/json",
  Prefer: "resolution=merge-duplicates,return=minimal",
};

async function h3PolyfillCount(geometry) {
  try {
    const h3 = await import("h3-js");
    const cells = h3.polygonToCells(geometry.coordinates, 7, true);
    return cells.length;
  } catch {
    return null; // fall back to the area estimate
  }
}

/** Spherical polygon area in km² (shoelace over equal-angle-ish projection). */
function areaKm2(geometry) {
  const R = 6371;
  const rings = geometry.type === "Polygon" ? [geometry.coordinates[0]] : geometry.coordinates.map((p) => p[0]);
  let total = 0;
  for (const ring of rings) {
    let sum = 0;
    for (let i = 0; i < ring.length - 1; i++) {
      const [lng1, lat1] = ring[i];
      const [lng2, lat2] = ring[i + 1];
      sum += ((lng2 - lng1) * Math.PI) / 180 * (2 + Math.sin((lat1 * Math.PI) / 180) + Math.sin((lat2 * Math.PI) / 180));
    }
    total += Math.abs((sum * R * R) / 2);
  }
  return Math.abs(total);
}

async function rest(path, method = "GET", body) {
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!response.ok) {
    throw new Error(`${method} ${path}: ${response.status} ${await response.text()}`);
  }
  return response.status === 204 ? null : response.json();
}

async function main() {
  // 1. Fetch current Census-derived state boundaries.
  const source = await fetch(SOURCE_URL).then((r) => r.json());

  // 2. Existing rows (id, version, total_cells) for the diff.
  const existing = await rest(
    `boundaries_admin?select=id,version,total_cells&level=eq.${LEVEL}`
  );
  const byId = new Map(existing.map((row) => [row.id, row]));

  // 3. Diff + upsert changed entities.
  const changed = [];
  for (const feature of source.features) {
    const fips = String(feature.id ?? feature.properties?.STATE ?? "").padStart(2, "0");
    const name = feature.properties?.name ?? feature.properties?.NAME;
    if (!fips || !name) continue;

    const id = `tiger:state:${fips}`;
    const prev = byId.get(id);
    const exact = await h3PolyfillCount(feature.geometry);
    const totalCells = exact ?? Math.max(1, Math.round(areaKm2(feature.geometry) / 5.16));

    if (!prev || prev.total_cells !== totalCells) {
      await rest("boundaries_admin", "POST", {
        id,
        level: LEVEL,
        name,
        source: "tiger",
        version: (prev?.version ?? 0) + 1,
        total_cells: totalCells,
        geom: feature.geometry,
      });
      changed.push({ level: LEVEL, id, name });
      console.log(`changed: ${name} (${id}) -> ${totalCells} cells`);
    }
  }

  // 4. Release row when anything changed (drives client notifications).
  if (changed.length > 0) {
    const releases = await rest("boundary_releases?select=version&order=released_at.desc&limit=50");
    const maxN = releases.reduce((max, r) => {
      const match = /census-cb\.(\d+)/.exec(r.version);
      return match ? Math.max(max, Number(match[1])) : max;
    }, 2);
    const version = `census-cb.${maxN + 1}`;
    await rest("boundary_releases", "POST", {
      version,
      changed_entities: changed,
    });
    console.log(`release ${version}: ${changed.length} entities changed`);
  } else {
    console.log("no boundary changes");
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
