#!/usr/bin/env bun
/**
 * Derives the bundled county-boundary asset for offline county attribution.
 *
 * Source: Plotly datasets mirror of the U.S. Census Bureau cartographic
 * boundary file (cb_2010, 1:20m) — public domain, FIPS-keyed.
 *   https://raw.githubusercontent.com/plotly/datasets/master/geojson-counties-fips.json
 *
 * Simplifications applied (attribution is bbox+PIP; res-7 cells are ~5 km
 * across, so ~670 m fidelity is ample):
 *   - Douglas-Peucker with 0.006° (~670 m) tolerance
 *   - coordinates rounded to 3 decimals
 *   - consecutive duplicate points removed after rounding
 *   - rings with fewer than 4 points dropped
 *   - only exterior rings kept (county holes are negligible for PIP)
 *   - state full name baked into properties from the state FIPS
 *
 * Output: ios/USAExplorer/Data/USCountyBoundaries.json.deflate
 * (raw deflate stream; the app inflates it with the Compression framework —
 * same pipeline as tools/make-city-boundaries.js)
 *
 * Usage: bun tools/make-county-boundaries.js [input.json]
 */

import { readFileSync, writeFileSync } from "node:fs";
import zlib from "node:zlib";

const input = process.argv[2] ?? `${process.env.TMPDIR ?? "/tmp"}/us_county_20m.json`;
const output = new URL("../ios/USAExplorer/Data/USCountyBoundaries.json.deflate", import.meta.url).pathname;

const FIPS_TO_STATE = {
  "01": "Alabama", "02": "Alaska", "04": "Arizona", "05": "Arkansas", "06": "California",
  "08": "Colorado", "09": "Connecticut", "10": "Delaware", "11": "District of Columbia",
  "12": "Florida", "13": "Georgia", "15": "Hawaii", "16": "Idaho", "17": "Illinois",
  "18": "Indiana", "19": "Iowa", "20": "Kansas", "21": "Kentucky", "22": "Louisiana",
  "23": "Maine", "24": "Maryland", "25": "Massachusetts", "26": "Michigan",
  "27": "Minnesota", "28": "Mississippi", "29": "Missouri", "30": "Montana",
  "31": "Nebraska", "32": "Nevada", "33": "New Hampshire", "34": "New Jersey",
  "35": "New Mexico", "36": "New York", "37": "North Carolina", "38": "North Dakota",
  "39": "Ohio", "40": "Oklahoma", "41": "Oregon", "42": "Pennsylvania",
  "44": "Rhode Island", "45": "South Carolina", "46": "South Dakota", "47": "Tennessee",
  "48": "Texas", "49": "Utah", "50": "Vermont", "51": "Virginia", "53": "Washington",
  "54": "West Virginia", "55": "Wisconsin", "56": "Wyoming", "72": "Puerto Rico",
};

const round = (v) => Math.round(v * 1000) / 1000;

/** Douglas-Peucker, tolerance in degrees (~0.004° ≈ 440 m). */
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
  // Drop closing duplicate and degenerate rings.
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

const source = JSON.parse(readFileSync(input, "utf8"));
const features = [];

for (const feature of source.features) {
  const { STATE, COUNTY, NAME } = feature.properties;
  const state = FIPS_TO_STATE[STATE];
  if (!state) continue; // skip territories we don't track
  const rings = exteriorRings(feature.geometry);
  if (rings.length === 0) continue;

  features.push({
    type: "Feature",
    properties: { fips: `${STATE}${COUNTY}`, state, name: NAME },
    geometry: rings.length === 1
      ? { type: "Polygon", coordinates: [rings[0]] }
      : { type: "MultiPolygon", coordinates: rings.map((r) => [r]) },
  });
}

const doc = { type: "FeatureCollection", features };
const json = JSON.stringify(doc);
writeFileSync(output, zlib.deflateRawSync(Buffer.from(json), { level: 9 }));

console.log(`counties: ${features.length}`);
console.log(`raw bytes: ${json.length}`);
