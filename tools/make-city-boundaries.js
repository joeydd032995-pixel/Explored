#!/usr/bin/env bun
/**
 * Derives the bundled city/place-boundary asset for offline city attribution.
 *
 * Source: U.S. Census Bureau CitySDK GeoJSON mirror of the cartographic
 * boundary places file (1:500,000, 2022 vintage) — public domain. Covers
 * incorporated places (cities, towns, villages, boroughs) and CDPs for all
 * states + DC + PR.
 *   https://github.com/uscensusbureau/citysdk/tree/master/v2/GeoJSON/500k
 *
 * Simplifications applied (attribution is bbox+PIP; res-7 cells are ~5 km
 * across, so ~600 m boundary fidelity is ample):
 *   - Douglas-Peucker with 0.006° (~670 m) tolerance
 *   - coordinates rounded to 3 decimals
 *   - consecutive duplicates / degenerate rings removed
 *   - only exterior rings kept
 *   - properties reduced to { state, name, kind } with kind from NAMELSAD
 *     ("Houston city" → "city"); entity key = "StateName-Name", matching
 *     the geocoder's city-id convention
 *
 * Output: ios/USAExplorer/Data/USCityBoundaries.json
 * Cache:   $TMPDIR/citysdk-2022/<fips>.json (re-run reuses the cache)
 *
 * Usage: bun tools/make-city-boundaries.js
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";

const cacheDir = `${process.env.TMPDIR ?? "/tmp"}/citysdk-2022`;
const output = new URL("../ios/USAExplorer/Data/USCityBoundaries.json", import.meta.url).pathname;

const STATE_FIPS = [
  "01", "02", "04", "05", "06", "08", "09", "10", "11", "12", "13", "15",
  "16", "17", "18", "19", "20", "21", "22", "23", "24", "25", "26", "27",
  "28", "29", "30", "31", "32", "33", "34", "35", "36", "37", "38", "39",
  "40", "41", "42", "44", "45", "46", "47", "48", "49", "50", "51", "53",
  "54", "55", "56", "72",
];

const round = (v) => Math.round(v * 1000) / 1000;

function simplify(ring, tolerance = 0.006) {
  const keep = new Array(ring.length).fill(false);
  keep[0] = keep[ring.length - 1] = true;
  const stack = [[0, ring.length - 1]];
  while (stack.length > 0) {
    const [start, end] = stack.pop();
    let maxDist = 0, index = -1;
    const [ax, ay] = ring[start], [bx, by] = ring[end];
    const dx = bx - ax, dy = by - ay;
    const lenSq = dx * dx + dy * dy;
    for (let i = start + 1; i < end; i++) {
      const [px, py] = ring[i];
      let dist;
      if (lenSq === 0) {
        dist = Math.hypot(px - ax, py - ay);
      } else {
        const t = Math.max(0, Math.min(1, ((px - ax) * dx + (py - ay) * dy) / lenSq));
        dist = Math.hypot(px - (ax + t * dx), py - (ay + t * dy));
      }
      if (dist > maxDist) { maxDist = dist; index = i; }
    }
    if (index >= 0 && maxDist > tolerance) {
      keep[index] = true;
      stack.push([start, index], [index, end]);
    }
  }
  return ring.filter((_, i) => keep[i]);
}

function simplifyRing(ring) {
  const simplified = simplify(ring.map(([lng, lat]) => [round(lng), round(lat)]));
  const out = [];
  for (const [lng, lat] of simplified) {
    const prev = out[out.length - 1];
    if (!prev || prev[0] !== lng || prev[1] !== lat) out.push([lng, lat]);
  }
  if (out.length > 1 && out[0][0] === out[out.length - 1][0] && out[0][1] === out[out.length - 1][1]) {
    out.pop();
  }
  return out.length >= 4 ? out : null;
}

function exteriorRings(geometry) {
  if (geometry.type === "Polygon") {
    return [simplifyRing(geometry.coordinates[0])].filter(Boolean);
  }
  if (geometry.type === "MultiPolygon") {
    return geometry.coordinates
      .map((polygon) => simplifyRing(polygon[0]))
      .filter(Boolean);
  }
  return [];
}

async function fetchState(fips) {
  const cachePath = `${cacheDir}/${fips}.json`;
  if (existsSync(cachePath)) {
    return JSON.parse(readFileSync(cachePath, "utf8"));
  }
  const url = `https://raw.githubusercontent.com/uscensusbureau/citysdk/master/v2/GeoJSON/500k/2022/${fips}/place.json`;
  const response = await fetch(url);
  if (!response.ok) throw new Error(`fetch ${fips}: HTTP ${response.status}`);
  const text = await response.text();
  mkdirSync(cacheDir, { recursive: true });
  writeFileSync(cachePath, text);
  return JSON.parse(text);
}

mkdirSync(cacheDir, { recursive: true });
const features = [];

for (const fips of STATE_FIPS) {
  const doc = await fetchState(fips);
  for (const feature of doc.features) {
    const p = feature.properties;
    const nameLsad = p.NAMELSAD ?? p.NAME;
    const kind = nameLsad.startsWith(p.NAME) ? nameLsad.slice(p.NAME.length).trim() : "";
    const rings = exteriorRings(feature.geometry);
    if (rings.length === 0) continue;

    features.push({
      type: "Feature",
      properties: { state: p.STATE_NAME, name: p.NAME, kind },
      geometry: rings.length === 1
        ? { type: "Polygon", coordinates: [rings[0]] }
        : { type: "MultiPolygon", coordinates: rings.map((r) => [r]) },
    });
  }
  console.log(`${fips}: ${features.length} total`);
}

const doc = { type: "FeatureCollection", features };
writeFileSync(output, JSON.stringify(doc));

console.log(`places: ${features.length}`);
console.log(`bytes: ${JSON.stringify(doc).length}`);
