const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const url = require('url');

const crypto = require('crypto');
const hos = require('./hos');

const PORT = 3003;
const DIR = __dirname;

// --- Schedule storage (JSON file, will migrate to SQL later) ---
const SCHEDULE_FILE = path.join(DIR, 'schedule.json');
let scheduleData = [];
try {
  scheduleData = JSON.parse(fs.readFileSync(SCHEDULE_FILE, 'utf8'));
  console.log(`  [Schedule] Loaded ${scheduleData.length} scheduled routes`);
} catch(e) { scheduleData = []; }

function saveSchedule() {
  fs.writeFileSync(SCHEDULE_FILE, JSON.stringify(scheduleData, null, 2));
}

// --- Mills / Yards / Activity storage ---
const MILLS_FILE    = path.join(DIR, 'mills.json');
const YARDS_FILE    = path.join(DIR, 'yards.json');
const ACTIVITY_FILE = path.join(DIR, 'activity.json');
const MILLS_SEED    = path.join(DIR, 'mills.seed.json');
const YARDS_SEED    = path.join(DIR, 'yards.seed.json');

function loadJsonFile(file, seedFile, label) {
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    console.log(`  [${label}] Loaded ${data.length} entries`);
    return data;
  } catch(e) {
    // Missing or invalid — try to seed from ship-with-repo seed file
    if (seedFile) {
      try {
        const seed = JSON.parse(fs.readFileSync(seedFile, 'utf8'));
        fs.writeFileSync(file, JSON.stringify(seed, null, 2));
        console.log(`  [${label}] Seeded ${seed.length} entries from ${path.basename(seedFile)}`);
        return seed;
      } catch(e2) { /* fall through */ }
    }
    console.log(`  [${label}] Starting empty`);
    return [];
  }
}

let millsData    = loadJsonFile(MILLS_FILE,    MILLS_SEED,    'Mills');
let yardsData    = loadJsonFile(YARDS_FILE,    YARDS_SEED,    'Yards');
let activityData = loadJsonFile(ACTIVITY_FILE, null,          'Activity');

// Ensure every mill/yard has a uuid (backfill for legacy seeds)
let needsMillSave = false, needsYardSave = false;
millsData.forEach(m => { if (!m.uuid) { m.uuid = crypto.randomUUID(); needsMillSave = true; } });
yardsData.forEach(y => { if (!y.uuid) { y.uuid = crypto.randomUUID(); needsYardSave = true; } });

function saveMills()    { fs.writeFileSync(MILLS_FILE,    JSON.stringify(millsData,    null, 2)); }
function saveYards()    { fs.writeFileSync(YARDS_FILE,    JSON.stringify(yardsData,    null, 2)); }
function saveActivity() { fs.writeFileSync(ACTIVITY_FILE, JSON.stringify(activityData, null, 2)); }

if (needsMillSave) saveMills();
if (needsYardSave) saveYards();

// Activity log helper — call from any endpoint that mutates state
function logActivity(req, action, entity, details) {
  const xff = req.headers['x-forwarded-for'];
  const ipRaw = (xff && xff.split(',')[0].trim()) || req.socket.remoteAddress || '';
  const ip = ipRaw.replace(/^::ffff:/, '');
  activityData.unshift({
    id: crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    ip,
    user: null,   // populated once SSO is wired in
    action,       // 'create' | 'update' | 'delete' | 'login' | 'logout'
    entity,       // 'mill' | 'yard' | 'schedule' | 'auth'
    details: details || {},
  });
  if (activityData.length > 1000) activityData.length = 1000;
  try { saveActivity(); } catch(e) { console.error('  [Activity] save failed:', e.message); }
}

// Internal Nominatim geocoder for server-side mill saves
function geocodeAddress(address) {
  return new Promise((resolve) => {
    const u = `https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${encodeURIComponent(address)}`;
    const req = https.get(u, { headers: { 'User-Agent': 'CarterLumberRouteApp/1.0' }, timeout: 8000 }, (r) => {
      const chunks = [];
      r.on('data', c => chunks.push(c));
      r.on('end', () => {
        try {
          const arr = JSON.parse(Buffer.concat(chunks).toString());
          if (arr && arr[0]) resolve({ lat: parseFloat(arr[0].lat), lon: parseFloat(arr[0].lon) });
          else resolve(null);
        } catch(e) { resolve(null); }
      });
    });
    req.on('error', () => resolve(null));
    req.on('timeout', () => { req.destroy(); resolve(null); });
  });
}

// Check if a truck is busy at a given time (considering route duration)
function isTruckBusy(truckId, truckName, startTime, durationSec, excludeScheduleId) {
  const newStart = new Date(startTime).getTime();
  const newEnd = newStart + (durationSec || 8 * 3600) * 1000; // default 8 hours if no duration

  for (const s of scheduleData) {
    if (s.status !== 'scheduled') continue;
    if (excludeScheduleId && s.id === excludeScheduleId) continue;
    if (!s.truck) continue;

    const matchesId = s.truck.id && (String(s.truck.id) === String(truckId));
    const matchesName = s.truck.name && (s.truck.name === truckName);
    if (!matchesId && !matchesName) continue;

    const existStart = new Date(s.scheduledAt).getTime();
    const existDuration = (s.duration || 8 * 3600) * 1000;
    const existEnd = existStart + existDuration;

    // Overlap check: new route overlaps if it starts before existing ends AND ends after existing starts
    if (newStart < existEnd && newEnd > existStart) {
      return {
        busy: true,
        conflict: {
          scheduleId: s.id,
          scheduledAt: s.scheduledAt,
          duration: s.duration,
          mill: s.mill ? s.mill.name : '?',
          yard: s.yard ? (s.yard.posNumber + ' ' + (s.yard.city || '')) : '?',
        }
      };
    }
  }
  return { busy: false };
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', c => chunks.push(c));
    req.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString())); }
      catch(e) { reject(e); }
    });
    req.on('error', reject);
  });
}

// Load secrets from secrets.js (gitignored) — never commit API keys
let secrets = {};
try { secrets = require('./secrets'); } catch(e) {}
const MAPBOX_TOKEN = secrets.MAPBOX_TOKEN || process.env.MAPBOX_TOKEN || '';
const IS_EMAIL    = secrets.INTELLISHIFT_EMAIL    || process.env.IS_EMAIL    || '';
const IS_PASSWORD = secrets.INTELLISHIFT_PASSWORD || process.env.IS_PASSWORD || '';
const ORS_API_KEY = secrets.ORS_API_KEY || process.env.ORS_API_KEY || '';

// Known branch IDs for "570: Traffic" (discovered, hardcoded to skip branch lookup)
// 34911 = 570: Traffic-CMV  |  34914 = 570: Traffic-Trailers  |  30215 = 570: Traffic (parent)
const IS_BRANCH_IDS = [34911, 34914, 30215];

// --- IntelliShift token + asset cache ---
let isToken = null;
let isTokenExpiry = 0;
let cachedAssets = null;     // { id, name, branchId } for all branch 570 assets
let assetsLoadedAt = 0;
const ASSET_CACHE_TTL = 4 * 60 * 60 * 1000; // refresh asset list every 4 hours

function intellishiftRequest(options, postBody) {
  return new Promise((resolve, reject) => {
    const req = https.request(options, (res) => {
      const chunks = [];
      res.on('data', c => chunks.push(c));
      res.on('end', () => {
        try {
          resolve({ status: res.status || res.statusCode, body: JSON.parse(Buffer.concat(chunks).toString()) });
        } catch(e) {
          resolve({ status: res.statusCode, body: Buffer.concat(chunks).toString() });
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(20000, () => { req.destroy(); reject(new Error('Timeout')); });
    if (postBody) req.write(postBody);
    req.end();
  });
}

let isTokenPromise = null; // prevent concurrent auth requests
async function getIntelliShiftToken() {
  if (isToken && Date.now() < isTokenExpiry) return isToken;
  if (isTokenPromise) return isTokenPromise; // reuse in-flight request
  isTokenPromise = (async () => {
    console.log('  [IS] Fetching new auth token...');
    const body = JSON.stringify({ email: IS_EMAIL, password: IS_PASSWORD });
    const result = await intellishiftRequest({
      hostname: 'auth.intellishift.com',
      path: '/oauth/token',
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) }
    }, body);
    if (result.body && result.body.access_token) {
      isToken = result.body.access_token;
      isTokenExpiry = Date.now() + ((result.body.expires_in || 86400) * 1000) - 60000;
      console.log('  [IS] Token acquired, valid for 24h');
      return isToken;
    }
    throw new Error('IntelliShift auth failed: ' + JSON.stringify(result.body));
  })().finally(() => { isTokenPromise = null; });
  return isTokenPromise;
}

async function isGet(token, path) {
  return intellishiftRequest({
    hostname: 'connect.intellishift.com',
    path, method: 'GET',
    headers: { 'Authorization': `Bearer ${token}`, 'Accept': 'application/json' }
  });
}

// Load branch 570 asset metadata — filtered by branchId, cached for 4 hours
async function loadBranch570Assets() {
  if (cachedAssets && Date.now() - assetsLoadedAt < ASSET_CACHE_TTL) return cachedAssets;
  const token = await getIntelliShiftToken();

  // branchId URL filter not supported by API — fetch all pages and filter in memory
  console.log('  [IS] Fetching all assets (branchId filter not supported by API, will filter in memory)...');
  let allBranchAssets = [];
  let page = 1, totalPages = 1;
  do {
    let r;
    try {
      r = await isGet(token, `/api/assets?pageNumber=${page}&pageSize=100`);
    } catch(e) {
      console.log(`  [IS] Request error page ${page}: ${e.message}`);
      break;
    }
    if (r.status !== 200) { console.log(`  [IS] Page ${page}: status ${r.status}`); break; }
    const data = r.body;
    const items = Array.isArray(data) ? data : (data.collection || []);
    allBranchAssets = allBranchAssets.concat(items);
    totalPages = data.totalPages || 1;
    if (page === 1 || page === totalPages) console.log(`  [IS] Page ${page}/${totalPages}: ${items.length} items`);
    page++;
  } while (page <= totalPages);

  // Deduplicate, then filter to only branch 570 assets
  const seen = new Set();
  const branchIdSet = new Set(IS_BRANCH_IDS);
  cachedAssets = allBranchAssets
    .filter(a => { if (seen.has(a.id)) return false; seen.add(a.id); return true; })
    .filter(a => branchIdSet.has(a.branchId))
    .map(a => ({
      id: a.id,
      name: a.name || String(a.id),
      branchId: a.branchId,
      operator: a.assignedOperatorText || null,  // "Operator" in IntelliShift — assigned per vehicle
    }));
  assetsLoadedAt = Date.now();
  console.log(`  [IS] Asset cache loaded: ${cachedAssets.length} branch 570 assets (filtered from ${seen.size} total)`);
  return cachedAssets;
}

// Fetch current locations for branch 570 assets
async function fetchBranch570Locations() {
  const assets = await loadBranch570Assets();
  const token = await getIntelliShiftToken();
  const idSet = new Set(assets.map(a => a.id));

  // Primary: /api/assets/current-locations returns VehicleTelematics[] (no required params)
  // vehicleId in VehicleTelematics matches id in asset records
  try {
    const r = await isGet(token, `/api/assets/current-locations`);
    if (r.status === 200) {
      const items = Array.isArray(r.body) ? r.body : (r.body.collection || []);
      console.log(`  [IS] /api/assets/current-locations: ${items.length} total records`);
      if (items.length > 0) {
        const locMap = {};
        items.forEach(loc => {
          const id = loc.vehicleId || loc.assetId || loc.id;
          if (idSet.has(id)) locMap[id] = loc;
        });
        console.log(`  [IS] Matched ${Object.keys(locMap).length} branch 570 vehicles with location data`);
        if (Object.keys(locMap).length > 0) {
          return { locMap, endpoint: '/api/assets/current-locations' };
        }
        // Got records but none matched our asset IDs — log a sample to debug
        if (items.length > 0) {
          console.log(`  [IS] Sample record (no ID match):`, JSON.stringify(items[0]).substring(0, 400));
        }
      }
    } else {
      console.log(`  [IS] /api/assets/current-locations status: ${r.status}`);
    }
  } catch(e) {
    console.log(`  [IS] /api/assets/current-locations error: ${e.message}`);
  }

  // Fallback bulk endpoints
  const fallbackEndpoints = [
    `/api/assets/locations`,
    `/api/telemetry/latest`,
    `/api/vehicles/locations`,
  ];
  for (const ep of fallbackEndpoints) {
    try {
      const r = await isGet(token, ep + '?pageSize=500');
      if (r.status === 200) {
        const items = Array.isArray(r.body) ? r.body : (r.body.collection || []);
        if (items.length > 0) {
          const locMap = {};
          items.forEach(loc => {
            const id = loc.vehicleId || loc.assetId || loc.id;
            if (idSet.has(id)) locMap[id] = loc;
          });
          console.log(`  [IS] Fallback ${ep}: ${items.length} records, ${Object.keys(locMap).length} matched`);
          if (Object.keys(locMap).length > 0) return { locMap, endpoint: ep };
        }
      }
    } catch(e) { /* try next */ }
  }

  console.log('  [IS] No location data found for branch 570 vehicles');
  return { locMap: {}, endpoint: 'none' };
}

// Build final vehicle list merging asset metadata + locations
async function getVehiclesWithLocations() {
  const assets = await loadBranch570Assets();
  const { locMap, endpoint } = await fetchBranch570Locations();

  const vehicles = assets.map(a => {
    const loc = locMap[a.id] || {};
    // Classify as truck/trailer from IntelliShift sub-branch
    // 34911 = 570: Traffic-CMV (trucks) | 34914 = 570: Traffic-Trailers | 30215 = parent
    const type = a.branchId === 34911 ? 'truck' : a.branchId === 34914 ? 'trailer' : 'unknown';
    return {
      id:         a.id,
      name:       loc.vehicleName || a.name,
      type,
      description: loc.vehicleMakeModel || '',
      lat:        parseFloat(loc.latitude  || loc.lat  || 0),
      lon:        parseFloat(loc.longitude || loc.lon  || 0),
      speed:      loc.speed       || 0,
      heading:    loc.headingDegrees !== undefined ? loc.headingDegrees : (loc.heading || 0),
      engineOn:   loc.engineOn    || false,
      // "Operator" is IntelliShift's per-vehicle assigned driver (assignedOperatorText).
      // Fall back to the driverName sent with the location ping if the asset lacks one.
      // We keep the outgoing field named `operator` and alias `driver` for backward compat.
      operator:   a.operator || loc.driverName || '',
      driver:     a.operator || loc.driverName || '',
      street:     loc.street      || '',
      city:       loc.city        || '',
      state:      loc.state       || '',
      updated:    loc.lastUpdate  || loc.lastUpdated || '',
      isSpeeding: loc.isSpeeding  || false,
      stopDuration: loc.stopDuration || '',
    };
  }).filter(v => v.lat !== 0 && v.lon !== 0);

  console.log(`  [IS] getVehiclesWithLocations: ${assets.length} total assets, ${vehicles.length} with location`);
  return { vehicles, total: assets.length, withLocation: vehicles.length, endpoint };
}

// --- Operators cache (for Drivers modal) ---
let cachedOperators = null;
let operatorsLoadedAt = 0;
const OPERATOR_CACHE_TTL = 60 * 60 * 1000; // 1 hour

async function loadOperators(token) {
  if (cachedOperators && Date.now() - operatorsLoadedAt < OPERATOR_CACHE_TTL) return cachedOperators;
  console.log('  [IS] Fetching all operators...');
  let allOps = [];
  let page = 1, totalPages = 1;
  do {
    const r = await isGet(token, `/api/operators?pageNumber=${page}&pageSize=100`);
    if (r.status !== 200) break;
    const items = Array.isArray(r.body) ? r.body : (r.body.collection || []);
    allOps = allOps.concat(items);
    totalPages = r.body.totalPages || 1;
    page++;
  } while (page <= totalPages);
  cachedOperators = allOps;
  operatorsLoadedAt = Date.now();
  console.log(`  [IS] Operator cache loaded: ${cachedOperators.length} total`);
  return cachedOperators;
}

async function fetchAssignments(token) {
  // Fetch recent assignments (active + closed in past 8 days).
  // The /api/operator-assignments endpoint returns current active ones by default.
  // To get historical, we'd need date params — for now grab what we can.
  let allAssign = [];
  let page = 1, totalPages = 1;
  do {
    const r = await isGet(token, `/api/operator-assignments?pageNumber=${page}&pageSize=100`);
    if (r.status !== 200) break;
    const items = Array.isArray(r.body) ? r.body : (r.body.collection || []);
    allAssign = allAssign.concat(items);
    totalPages = r.body.totalPages || 1;
    page++;
  } while (page <= totalPages);
  console.log(`  [IS] Fetched ${allAssign.length} operator assignments`);
  return allAssign;
}

const MIME_TYPES = {
  '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript',
  '.json': 'application/json', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml', '.ico': 'image/x-icon',
  '.xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
};

// --- Haversine distance fallback when routing APIs are down ---
function haversine(lat1, lon1, lat2, lon2) {
  const R = 6371; // km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat/2)**2 + Math.cos(lat1*Math.PI/180)*Math.cos(lat2*Math.PI/180)*Math.sin(dLon/2)**2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a));
}

function generateFallbackRoute(coordsStr, overview) {
  const parts = coordsStr.split(';');
  if (parts.length < 2) return null;
  const [lon1, lat1] = parts[0].split(',').map(Number);
  const [lon2, lat2] = parts[1].split(',').map(Number);
  const straightKm = haversine(lat1, lon1, lat2, lon2);
  const roadFactor = 1.32; // typical road-to-straight-line ratio
  const distMeters = straightKm * roadFactor * 1000;
  const avgSpeedKmh = 80; // avg highway speed
  const durationSec = (straightKm * roadFactor / avgSpeedKmh) * 3600;

  const route = {
    distance: distMeters,
    duration: durationSec,
    weight_name: "routability",
    weight: durationSec
  };

  // Generate geometry if full overview requested
  if (overview === 'full') {
    const steps = 20;
    const coordinates = [];
    for (let i = 0; i <= steps; i++) {
      const t = i / steps;
      // Simple interpolation with slight curve
      const lat = lat1 + (lat2 - lat1) * t;
      const lon = lon1 + (lon2 - lon1) * t;
      coordinates.push([lon, lat]);
    }
    route.geometry = { type: 'LineString', coordinates };
  }

  return {
    code: 'Ok',
    routes: [route],
    waypoints: [
      { hint: '', distance: 0, name: '', location: [lon1, lat1] },
      { hint: '', distance: 0, name: '', location: [lon2, lat2] }
    ],
    _fallback: true,
    _note: 'Estimated via straight-line distance x1.32 road factor (OSRM unavailable)'
  };
}

// --- Proxy with timeout and multiple fallbacks ---
function proxyRequest(targetUrl, res, fallbackUrls, fallbackFn) {
  const startTime = Date.now();
  const urlShort = targetUrl.substring(0, 100);
  console.log(`  -> ${urlShort}...`);
  let done = false; // guard against double-response

  const req = https.get(targetUrl, {
    headers: { 'User-Agent': 'CarterLumberRouteApp/1.0' },
    timeout: 8000
  }, (proxyRes) => {
    const chunks = [];
    proxyRes.on('data', chunk => chunks.push(chunk));
    proxyRes.on('end', () => {
      if (done) return;
      const body = Buffer.concat(chunks);
      const elapsed = Date.now() - startTime;
      console.log(`  <- ${proxyRes.statusCode} (${elapsed}ms)`);
      // If rate-limited (429) or forbidden (403), try fallback instead of passing error through
      if (proxyRes.statusCode === 429 || proxyRes.statusCode === 403) {
        console.log(`  !! Rate limited or blocked (${proxyRes.statusCode}) — trying fallback`);
        return tryNext();
      }
      done = true;
      res.writeHead(proxyRes.statusCode, {
        'Content-Type': proxyRes.headers['content-type'] || 'application/json',
        'Access-Control-Allow-Origin': '*'
      });
      res.end(body);
    });
  });

  req.on('timeout', () => {
    req.destroy();
    if (done) return;
    console.log(`  !! Timeout: ${urlShort}`);
    tryNext();
  });

  req.on('error', (err) => {
    if (done) return;
    console.error(`  !! Error: ${err.message}`);
    tryNext();
  });

  function tryNext() {
    if (done) return;
    if (fallbackUrls && fallbackUrls.length > 0) {
      const next = fallbackUrls.shift();
      console.log(`  -> Trying fallback...`);
      proxyRequest(next, res, fallbackUrls, fallbackFn);
    } else if (fallbackFn) {
      done = true;
      console.log(`  -> Using local calculation fallback`);
      const result = fallbackFn();
      if (result) {
        res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
        res.end(JSON.stringify(result));
      } else {
        res.writeHead(502, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
        res.end(JSON.stringify({ error: 'All routing attempts failed' }));
      }
    } else {
      done = true;
      res.writeHead(504, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
      res.end(JSON.stringify({ error: 'Gateway timeout' }));
    }
  }
}

// Simple proxy (no fallback chain)
function simpleProxy(targetUrl, res) {
  const startTime = Date.now();
  console.log(`  -> ${targetUrl.substring(0, 100)}...`);
  let done = false;

  const req = https.get(targetUrl, {
    headers: { 'User-Agent': 'CarterLumberRouteApp/1.0' },
    timeout: 10000
  }, (proxyRes) => {
    const chunks = [];
    proxyRes.on('data', chunk => chunks.push(chunk));
    proxyRes.on('end', () => {
      if (done) return;
      done = true;
      const body = Buffer.concat(chunks);
      console.log(`  <- ${proxyRes.statusCode} (${Date.now() - startTime}ms)`);
      res.writeHead(proxyRes.statusCode, {
        'Content-Type': proxyRes.headers['content-type'] || 'application/json',
        'Access-Control-Allow-Origin': '*'
      });
      res.end(body);
    });
  });

  req.on('timeout', () => {
    if (done) return;
    done = true;
    req.destroy();
    console.log(`  !! Timeout: ${targetUrl.substring(0, 80)}`);
    res.writeHead(504, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    res.end(JSON.stringify({ error: 'Timeout' }));
  });
  req.on('error', (err) => {
    if (done) return;
    done = true;
    console.error(`  !! Error: ${err.message}`);
    res.writeHead(502, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    res.end(JSON.stringify({ error: err.message }));
  });
}

// --- HTTP Server ---
const server = http.createServer((req, res) => {
  const parsed = url.parse(req.url, true);
  const pathname = parsed.pathname;

  // OSRM routing — primary -> fallback mirror -> haversine estimate
  if (pathname === '/api/route') {
    const coords = parsed.query.coords || '';
    const overview = parsed.query.overview || 'full';
    // driving-traffic uses real-time traffic for accurate ETAs; falls back to driving profile if needed
    const qs = `?geometries=geojson&overview=${overview}&annotations=duration,distance,congestion&access_token=${MAPBOX_TOKEN}`;
    const mapbox         = `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${coords}${qs}`;
    const mapboxFallback = `https://api.mapbox.com/directions/v5/mapbox/driving/${coords}${qs}`;
    const osrmFallback   = `https://router.project-osrm.org/route/v1/driving/${coords}?overview=${overview}&geometries=geojson`;
    console.log('  Route request — Mapbox driving-traffic -> driving -> OSRM -> haversine');
    return proxyRequest(mapbox, res, [mapboxFallback, osrmFallback], () => generateFallbackRoute(coords, overview));
  }

  // Truck-safe (HGV) routing via OpenRouteService.
  // coords query is "lon1,lat1;lon2,lat2" to match /api/route.
  // Returns Mapbox-compatible shape so existing client code works.
  // Falls back to Mapbox driving if ORS is unconfigured or fails.
  if (pathname === '/api/truck-route') {
    const coordsStr = parsed.query.coords || '';
    const overview  = parsed.query.overview || 'full';
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');

    const fallbackToDrivingMapbox = () => {
      const qs = `?geometries=geojson&overview=${overview}&annotations=duration,distance,congestion&access_token=${MAPBOX_TOKEN}`;
      const mapbox       = `https://api.mapbox.com/directions/v5/mapbox/driving-traffic/${coordsStr}${qs}`;
      const mapboxDrive  = `https://api.mapbox.com/directions/v5/mapbox/driving/${coordsStr}${qs}`;
      const osrmFallback = `https://router.project-osrm.org/route/v1/driving/${coordsStr}?overview=${overview}&geometries=geojson`;
      console.log('  [truck-route] Falling back to Mapbox driving chain');
      proxyRequest(mapbox, res, [mapboxDrive, osrmFallback], () => generateFallbackRoute(coordsStr, overview));
    };

    if (!ORS_API_KEY) {
      console.log('  [truck-route] ORS_API_KEY not set — falling back to Mapbox driving');
      return fallbackToDrivingMapbox();
    }

    // Build ORS coordinates (array of [lon, lat] pairs)
    const pts = coordsStr.split(';').map(p => p.split(',').map(Number));
    if (pts.length < 2 || pts.some(p => p.length !== 2 || isNaN(p[0]) || isNaN(p[1]))) {
      res.writeHead(400);
      return res.end(JSON.stringify({ error: 'Invalid coords param — expected lon1,lat1;lon2,lat2' }));
    }

    const orsBody = JSON.stringify({
      coordinates: pts,
      instructions: false,
      geometry: true,
      preference: 'recommended',
    });
    const orsReq = https.request({
      hostname: 'api.openrouteservice.org',
      path: '/v2/directions/driving-hgv/geojson',
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Authorization': ORS_API_KEY,
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(orsBody),
      },
      timeout: 10000,
    }, (orsRes) => {
      const chunks = [];
      orsRes.on('data', c => chunks.push(c));
      orsRes.on('end', () => {
        const raw = Buffer.concat(chunks).toString();
        if (orsRes.statusCode !== 200) {
          console.log(`  [truck-route] ORS returned ${orsRes.statusCode}: ${raw.substring(0, 200)}`);
          return fallbackToDrivingMapbox();
        }
        try {
          const data = JSON.parse(raw);
          const feat = data.features && data.features[0];
          if (!feat) { console.log('  [truck-route] ORS returned no features'); return fallbackToDrivingMapbox(); }
          const props = feat.properties || {};
          const summary = props.summary || {};
          // Normalize to Mapbox-like response shape so existing client code works unchanged
          const converted = {
            code: 'Ok',
            routes: [{
              geometry: feat.geometry,
              distance: summary.distance,   // meters
              duration: summary.duration,   // seconds
              weight: summary.duration,
              weight_name: 'duration',
              _source: 'openrouteservice-hgv',
            }],
            waypoints: pts.map((p, i) => ({ location: p, name: '', distance: 0, hint: '' })),
            _truckSafe: true,
          };
          console.log(`  [truck-route] ORS HGV: ${Math.round(summary.distance/1000)}km, ${Math.round(summary.duration/60)}min`);
          res.writeHead(200);
          res.end(JSON.stringify(converted));
        } catch(e) {
          console.log('  [truck-route] Parse error:', e.message);
          fallbackToDrivingMapbox();
        }
      });
    });
    orsReq.on('error', (err) => { console.log('  [truck-route] Request error:', err.message); fallbackToDrivingMapbox(); });
    orsReq.on('timeout', () => { orsReq.destroy(); console.log('  [truck-route] Request timeout'); fallbackToDrivingMapbox(); });
    orsReq.write(orsBody);
    orsReq.end();
    return;
  }

  // HOS projection endpoint — compute without persisting (useful for pre-scheduling checks)
  if (pathname === '/api/hos' && req.method === 'POST') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const body = await readBody(req);
      const projection = hos.projectDelivery({
        startTime: body.startTime,
        drivingDurationSec: body.drivingDurationSec,
        cumulativeWeekHoursBeforeStart: body.cumulativeWeekHoursBeforeStart || 0,
        schedule: body.schedule || '70/8',
      });
      res.writeHead(200);
      res.end(JSON.stringify(projection));
    } catch(e) {
      res.writeHead(400); res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // Nominatim geocoding
  if (pathname === '/api/geocode') {
    const q = parsed.query.q || '';
    return simpleProxy(`https://nominatim.openstreetmap.org/search?format=json&limit=1&q=${encodeURIComponent(q)}`, res);
  }

  // EIA diesel prices
  if (pathname === '/api/diesel') {
    const qs = req.url.split('?').slice(1).join('?');
    return simpleProxy(`https://api.eia.gov/v2/petroleum/pri/gnd/data/?${qs}`, res);
  }

  // IntelliShift: preload asset metadata (fast, cached)
  if (pathname === '/api/intellishift/assets') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const assets = await loadBranch570Assets();
      res.writeHead(200);
      res.end(JSON.stringify({ assets, total: assets.length, cachedAt: new Date(assetsLoadedAt).toISOString() }));
    } catch(e) {
      res.writeHead(500); res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // IntelliShift: live locations only (called on toggle + refresh)
  if (pathname === '/api/intellishift/vehicles') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    if (!IS_EMAIL || !IS_PASSWORD) {
      res.writeHead(503);
      return res.end(JSON.stringify({ error: 'IntelliShift credentials not configured in secrets.js' }));
    }
    (async () => { try {
      const result = await getVehiclesWithLocations();
      res.writeHead(200);
      res.end(JSON.stringify(result));
    } catch(e) {
      console.error('  [IS] Error:', e.message);
      res.writeHead(500);
      res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // IntelliShift debug probe — hit any IS path and return raw response
  if (pathname === '/api/intellishift/probe') {
    const probePath = parsed.query.path || '';
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const token = await getIntelliShiftToken();
      const r = await isGet(token, probePath);
      console.log(`  [IS probe] ${probePath} -> ${r.status}: ${JSON.stringify(r.body).substring(0, 400)}`);
      res.writeHead(200);
      res.end(JSON.stringify({ status: r.status, body: r.body }));
    } catch(e) {
      res.writeHead(200);
      res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // App version check — iOS app calls this to check for updates
  if (pathname === '/api/app-version') {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    return res.end(JSON.stringify({
      version: '1.0.0',             // Bump this when you release a new version
      minVersion: '1.0.0',          // Minimum supported version (for force-update)
      installURL: null,             // Set to your OTA install URL when ready, e.g.:
      // installURL: 'itms-services://?action=download-manifest&url=https://yourserver.com/app/manifest.plist',
      releaseNotes: 'Initial release with route planning, truck routing, and scheduling.',
    }));
  }

  // Client config — vends public tokens safe for browser use
  if (pathname === '/favicon.ico') {
    res.writeHead(204); // no favicon; 204 avoids the 404 noise
    return res.end();
  }

  if (pathname === '/api/config') {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    return res.end(JSON.stringify({ mapboxToken: MAPBOX_TOKEN }));
  }

  // Open-Meteo weather (single call, no API key needed)
  if (pathname === '/api/weather') {
    const { lat, lon } = parsed.query;
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m,weather_code,apparent_temperature&wind_speed_unit=mph&temperature_unit=fahrenheit&forecast_days=1`;
    return simpleProxy(url, res);
  }

  // --- Schedule CRUD ---
  // Handle CORS preflight for schedule endpoints
  if (req.method === 'OPTIONS' && pathname.startsWith('/api/schedule')) {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    return res.end();
  }

  // GET /api/schedule/truck-availability — check which trucks are busy on a date/time
  if (pathname === '/api/schedule/truck-availability' && req.method === 'GET') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    const dateTime = parsed.query.dateTime; // ISO string "2026-04-15T06:00:00"
    const duration = parseInt(parsed.query.duration) || 8 * 3600; // seconds, default 8h

    if (!dateTime) {
      res.writeHead(400);
      return res.end(JSON.stringify({ error: 'dateTime parameter required' }));
    }

    // Find all trucks that are busy during this window
    const busyTrucks = {};
    const checkStart = new Date(dateTime).getTime();
    const checkEnd = checkStart + duration * 1000;

    for (const s of scheduleData) {
      if (s.status !== 'scheduled' || !s.truck) continue;
      const existStart = new Date(s.scheduledAt).getTime();
      const existDuration = (s.duration || 8 * 3600) * 1000;
      const existEnd = existStart + existDuration;

      if (checkStart < existEnd && checkEnd > existStart) {
        const key = s.truck.id || s.truck.name;
        busyTrucks[key] = {
          truckId: s.truck.id,
          truckName: s.truck.name,
          scheduleId: s.id,
          scheduledAt: s.scheduledAt,
          duration: s.duration,
          mill: s.mill ? s.mill.name : null,
          yard: s.yard ? (s.yard.posNumber + ' ' + (s.yard.city || '')) : null,
        };
      }
    }

    res.writeHead(200);
    return res.end(JSON.stringify({ busyTrucks, dateTime, duration }));
  }

  // GET /api/schedule — list all (optional ?month=2026-04 or ?date=2026-04-13 filter)
  if (pathname === '/api/schedule' && req.method === 'GET') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    const month = parsed.query.month; // "2026-04"
    const date  = parsed.query.date;  // "2026-04-13"
    let results = scheduleData;
    if (date) {
      results = scheduleData.filter(r => r.scheduledAt && r.scheduledAt.startsWith(date));
    } else if (month) {
      results = scheduleData.filter(r => r.scheduledAt && r.scheduledAt.startsWith(month));
    }
    results.sort((a, b) => (a.scheduledAt || '').localeCompare(b.scheduledAt || ''));
    res.writeHead(200);
    return res.end(JSON.stringify({ schedules: results, total: results.length }));
  }

  // POST /api/schedule — create new scheduled route
  if (pathname === '/api/schedule' && req.method === 'POST') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const body = await readBody(req);
      const entry = {
        id: crypto.randomUUID(),
        createdAt: new Date().toISOString(),
        scheduledAt: body.scheduledAt,
        type: body.type || 'single',
        mill: body.mill || null,
        yard: body.yard || null,
        truck: body.truck || null,
        distance: body.distance || 0,
        duration: body.duration || 0,
        fuelCost: body.fuelCost || null,
        notes: body.notes || '',
        status: 'scheduled',
      };
      // Attach DOT HOS projection if we have a drive duration and start time
      if (entry.scheduledAt && entry.duration > 0) {
        try {
          entry.hosProjection = hos.projectDelivery({
            startTime: entry.scheduledAt,
            drivingDurationSec: entry.duration,
            cumulativeWeekHoursBeforeStart: body.cumulativeWeekHours || 0,
            schedule: body.hosSchedule || '70/8',
          });
        } catch(e) {
          console.warn('  [Schedule] HOS projection failed:', e.message);
        }
      }
      scheduleData.push(entry);
      saveSchedule();
      logActivity(req, 'create', 'schedule', {
        id: entry.id,
        scheduledAt: entry.scheduledAt,
        mill: entry.mill ? entry.mill.name : null,
        yard: entry.yard ? entry.yard.posNumber : null,
        truck: entry.truck ? entry.truck.name : null,
      });
      console.log(`  [Schedule] Created: ${entry.id} for ${entry.scheduledAt}`);
      res.writeHead(201);
      res.end(JSON.stringify(entry));
    } catch(e) {
      res.writeHead(400);
      res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // PUT /api/schedule/:id — update status or notes
  const putMatch = pathname.match(/^\/api\/schedule\/([a-f0-9-]+)$/);
  if (putMatch && req.method === 'PUT') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const id = putMatch[1];
      const body = await readBody(req);
      const idx = scheduleData.findIndex(r => r.id === id);
      if (idx === -1) { res.writeHead(404); return res.end(JSON.stringify({ error: 'Not found' })); }
      const changes = {};
      if (body.status && body.status !== scheduleData[idx].status) {
        changes.status = { from: scheduleData[idx].status, to: body.status };
        scheduleData[idx].status = body.status;
      }
      if (body.notes !== undefined && body.notes !== scheduleData[idx].notes) {
        changes.notes = { from: scheduleData[idx].notes, to: body.notes };
        scheduleData[idx].notes = body.notes;
      }
      if (body.scheduledAt && body.scheduledAt !== scheduleData[idx].scheduledAt) {
        changes.scheduledAt = { from: scheduleData[idx].scheduledAt, to: body.scheduledAt };
        scheduleData[idx].scheduledAt = body.scheduledAt;
      }
      if (body.truck) {
        changes.truck = { to: body.truck.name || body.truck.id };
        scheduleData[idx].truck = body.truck;
      }
      saveSchedule();
      logActivity(req, 'update', 'schedule', { id, changes });
      console.log(`  [Schedule] Updated: ${id} -> ${scheduleData[idx].status}`);
      res.writeHead(200);
      res.end(JSON.stringify(scheduleData[idx]));
    } catch(e) {
      res.writeHead(400);
      res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // DELETE /api/schedule/:id
  const delMatch = pathname.match(/^\/api\/schedule\/([a-f0-9-]+)$/);
  if (delMatch && req.method === 'DELETE') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    const id = delMatch[1];
    const idx = scheduleData.findIndex(r => r.id === id);
    if (idx === -1) { res.writeHead(404); return res.end(JSON.stringify({ error: 'Not found' })); }
    const removed = scheduleData[idx];
    scheduleData.splice(idx, 1);
    saveSchedule();
    logActivity(req, 'delete', 'schedule', {
      id,
      mill: removed.mill ? removed.mill.name : null,
      yard: removed.yard ? removed.yard.posNumber : null,
      scheduledAt: removed.scheduledAt,
    });
    console.log(`  [Schedule] Deleted: ${id}`);
    res.writeHead(200);
    return res.end(JSON.stringify({ ok: true }));
  }

  // ============================================================
  // MILLS / YARDS / ACTIVITY endpoints
  // ============================================================

  // CORS preflight for settings endpoints
  if (req.method === 'OPTIONS' && (pathname.startsWith('/api/mills') || pathname.startsWith('/api/yards') || pathname.startsWith('/api/activity'))) {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    });
    return res.end();
  }

  // --- MILLS ---

  // GET /api/mills
  if (pathname === '/api/mills' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    return res.end(JSON.stringify({ mills: millsData, total: millsData.length }));
  }

  // POST /api/mills/geocode-all — backfill lat/lon for mills missing coords
  // Rate-limited to ~1 req/sec to respect Nominatim's usage policy.
  if (pathname === '/api/mills/geocode-all' && req.method === 'POST') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const missing = millsData.filter(m => m.lat == null || m.lon == null);
      let succeeded = 0, failed = 0;
      const failures = [];
      console.log(`  [Mills] Geocode-all: ${missing.length} mills missing coords`);
      for (const m of missing) {
        const geo = await geocodeAddress(m.address);
        if (geo) {
          m.lat = geo.lat; m.lon = geo.lon;
          succeeded++;
          logActivity(req, 'update', 'mill', { uuid: m.uuid, name: m.name, changes: { geocoded: { to: { lat: geo.lat, lon: geo.lon } } } });
        } else {
          failed++;
          failures.push({ name: m.name, address: m.address });
        }
        // throttle: Nominatim usage policy = max 1 req/sec
        await new Promise(r => setTimeout(r, 1100));
      }
      saveMills();
      console.log(`  [Mills] Geocode-all done: ${succeeded} succeeded, ${failed} failed`);
      res.writeHead(200);
      res.end(JSON.stringify({ total: missing.length, succeeded, failed, failures }));
    } catch(e) {
      console.error('  [Mills] Geocode-all error:', e.message);
      res.writeHead(500); res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // POST /api/mills
  if (pathname === '/api/mills' && req.method === 'POST') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const body = await readBody(req);
      if (!body.name || !body.address) {
        res.writeHead(400); return res.end(JSON.stringify({ error: 'name and address are required' }));
      }
      const entry = {
        uuid: crypto.randomUUID(),
        name: body.name,
        product: body.product || '',
        vendor: body.vendor || '',
        street: body.street || '',
        city: body.city || '',
        stateZip: body.stateZip || '',
        address: body.address,
        lat: null, lon: null,
      };
      const geo = await geocodeAddress(body.address);
      if (geo) { entry.lat = geo.lat; entry.lon = geo.lon; }
      millsData.push(entry);
      saveMills();
      logActivity(req, 'create', 'mill', { uuid: entry.uuid, name: entry.name, vendor: entry.vendor });
      console.log(`  [Mills] Created: ${entry.name} (${entry.vendor}) geocoded=${!!geo}`);
      res.writeHead(201);
      res.end(JSON.stringify({ mill: entry, geocoded: !!geo }));
    } catch(e) {
      res.writeHead(400); res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // PUT /api/mills/:uuid
  const millPutMatch = pathname.match(/^\/api\/mills\/([a-f0-9-]+)$/);
  if (millPutMatch && req.method === 'PUT') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const uuid = millPutMatch[1];
      const idx = millsData.findIndex(m => m.uuid === uuid);
      if (idx === -1) { res.writeHead(404); return res.end(JSON.stringify({ error: 'Not found' })); }
      const body = await readBody(req);
      const existing = millsData[idx];
      const changes = {};
      ['name','product','vendor','street','city','stateZip','address'].forEach(k => {
        if (body[k] !== undefined && body[k] !== existing[k]) {
          changes[k] = { from: existing[k], to: body[k] };
          existing[k] = body[k];
        }
      });
      // Re-geocode if address changed
      let geocoded = false;
      if (changes.address) {
        const geo = await geocodeAddress(existing.address);
        if (geo) { existing.lat = geo.lat; existing.lon = geo.lon; geocoded = true; }
      }
      saveMills();
      logActivity(req, 'update', 'mill', { uuid, name: existing.name, changes });
      console.log(`  [Mills] Updated: ${existing.name}`);
      res.writeHead(200); res.end(JSON.stringify({ mill: existing, geocoded }));
    } catch(e) {
      res.writeHead(400); res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // DELETE /api/mills/:uuid
  const millDelMatch = pathname.match(/^\/api\/mills\/([a-f0-9-]+)$/);
  if (millDelMatch && req.method === 'DELETE') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    const uuid = millDelMatch[1];
    const idx = millsData.findIndex(m => m.uuid === uuid);
    if (idx === -1) { res.writeHead(404); return res.end(JSON.stringify({ error: 'Not found' })); }
    const removed = millsData[idx];
    millsData.splice(idx, 1);
    saveMills();
    logActivity(req, 'delete', 'mill', { uuid, name: removed.name, vendor: removed.vendor });
    console.log(`  [Mills] Deleted: ${removed.name}`);
    res.writeHead(200); return res.end(JSON.stringify({ ok: true }));
  }

  // --- YARDS ---

  // GET /api/yards
  if (pathname === '/api/yards' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    return res.end(JSON.stringify({ yards: yardsData, total: yardsData.length }));
  }

  // POST /api/yards
  if (pathname === '/api/yards' && req.method === 'POST') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const body = await readBody(req);
      if (!body.storeNumber || !body.city || !body.state) {
        res.writeHead(400); return res.end(JSON.stringify({ error: 'storeNumber, city, state are required' }));
      }
      const entry = {
        uuid: crypto.randomUUID(),
        storeNumber: body.storeNumber,
        posNumber: body.posNumber || body.storeNumber,
        storeType: body.storeType || '',
        street: body.street || '',
        city: body.city,
        state: body.state,
        zip: body.zip || '',
        lat: body.lat != null ? parseFloat(body.lat) : null,
        lon: body.lon != null ? parseFloat(body.lon) : null,
        manager: body.manager || '',
        market: body.market || '',
      };
      yardsData.push(entry);
      saveYards();
      logActivity(req, 'create', 'yard', { uuid: entry.uuid, storeNumber: entry.storeNumber, city: entry.city });
      console.log(`  [Yards] Created: ${entry.storeNumber} ${entry.city}`);
      res.writeHead(201); res.end(JSON.stringify({ yard: entry }));
    } catch(e) {
      res.writeHead(400); res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // PUT /api/yards/:uuid
  const yardPutMatch = pathname.match(/^\/api\/yards\/([a-f0-9-]+)$/);
  if (yardPutMatch && req.method === 'PUT') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const uuid = yardPutMatch[1];
      const idx = yardsData.findIndex(y => y.uuid === uuid);
      if (idx === -1) { res.writeHead(404); return res.end(JSON.stringify({ error: 'Not found' })); }
      const body = await readBody(req);
      const existing = yardsData[idx];
      const changes = {};
      ['storeNumber','posNumber','storeType','street','city','state','zip','manager','market'].forEach(k => {
        if (body[k] !== undefined && body[k] !== existing[k]) {
          changes[k] = { from: existing[k], to: body[k] };
          existing[k] = body[k];
        }
      });
      ['lat','lon'].forEach(k => {
        if (body[k] !== undefined) {
          const v = body[k] === '' || body[k] === null ? null : parseFloat(body[k]);
          if (v !== existing[k]) {
            changes[k] = { from: existing[k], to: v };
            existing[k] = v;
          }
        }
      });
      saveYards();
      logActivity(req, 'update', 'yard', { uuid, storeNumber: existing.storeNumber, changes });
      console.log(`  [Yards] Updated: ${existing.storeNumber}`);
      res.writeHead(200); res.end(JSON.stringify({ yard: existing }));
    } catch(e) {
      res.writeHead(400); res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // DELETE /api/yards/:uuid
  const yardDelMatch = pathname.match(/^\/api\/yards\/([a-f0-9-]+)$/);
  if (yardDelMatch && req.method === 'DELETE') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    const uuid = yardDelMatch[1];
    const idx = yardsData.findIndex(y => y.uuid === uuid);
    if (idx === -1) { res.writeHead(404); return res.end(JSON.stringify({ error: 'Not found' })); }
    const removed = yardsData[idx];
    yardsData.splice(idx, 1);
    saveYards();
    logActivity(req, 'delete', 'yard', { uuid, storeNumber: removed.storeNumber, city: removed.city });
    console.log(`  [Yards] Deleted: ${removed.storeNumber}`);
    res.writeHead(200); return res.end(JSON.stringify({ ok: true }));
  }

  // --- ACTIVITY LOG (read-only) ---

  if (pathname === '/api/activity' && req.method === 'GET') {
    res.writeHead(200, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' });
    const limit = Math.min(parseInt(parsed.query.limit) || 100, 500);
    const offset = parseInt(parsed.query.offset) || 0;
    const events = activityData.slice(offset, offset + limit);
    return res.end(JSON.stringify({ events, total: activityData.length, offset, limit }));
  }

  // ============================================================
  // DRIVERS — Branch 570 operators with HOS tracking
  // ============================================================

  if (pathname === '/api/drivers' && req.method === 'GET') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    (async () => { try {
      const token = await getIntelliShiftToken();

      // 1. Fetch all operators (cached 1h)
      const operators = await loadOperators(token);

      // 2. Fetch current + recent assignments (live, not cached — shifts change throughout the day)
      const assignments = await fetchAssignments(token);

      // 3. Get vehicle locations for cross-ref
      let vehicleLocations = {};
      try {
        const { vehicles } = await getVehiclesWithLocations();
        vehicles.forEach(v => { vehicleLocations[v.id] = v; });
      } catch(e) { /* proceed without locations */ }

      // 4. Build the drivers list
      const now = Date.now();
      const eightDaysAgo = now - 8 * 24 * 3600 * 1000;
      const todayStart = new Date(); todayStart.setHours(0,0,0,0);
      const todayMs = todayStart.getTime();

      // Build assignment lookups
      const activeAssignments = {};   // operatorId → current active assignment
      const weekAssignments = {};     // operatorId → array of assignments in 8-day window
      for (const a of assignments) {
        const startMs = new Date(a.startTime).getTime();
        const endMs = a.endTime ? new Date(a.endTime).getTime() : now;
        // Active = no endTime
        if (!a.endTime) activeAssignments[a.operatorId] = a;
        // Week window
        if (startMs >= eightDaysAgo || endMs >= eightDaysAgo) {
          if (!weekAssignments[a.operatorId]) weekAssignments[a.operatorId] = [];
          weekAssignments[a.operatorId].push(a);
        }
      }

      // Determine which operators are "Branch 570 relevant"
      const b570BranchIds = new Set(IS_BRANCH_IDS);
      const activeOperatorIds = new Set(Object.keys(activeAssignments).map(Number));
      const relevantOperators = operators.filter(op => {
        // Include if: has an active shift on a 570 vehicle, OR reportingBranchId is a 570 branch, OR statusId 1 + has any 570 assignment ever
        if (activeOperatorIds.has(op.id)) return true;
        if (op.reportingBranchId && b570BranchIds.has(op.reportingBranchId)) return true;
        if (weekAssignments[op.id]) return true;
        return false;
      });

      // Build enriched driver objects
      const drivers = relevantOperators.map(op => {
        const active = activeAssignments[op.id];
        const weekHistory = weekAssignments[op.id] || [];

        // Today actual hours
        let todayActualSec = 0;
        for (const a of weekHistory) {
          const start = Math.max(new Date(a.startTime).getTime(), todayMs);
          const end = a.endTime ? new Date(a.endTime).getTime() : now;
          if (end > todayMs && start < now) {
            todayActualSec += (Math.min(end, now) - start) / 1000;
          }
        }

        // Week actual hours (rolling 8-day)
        let weekActualSec = 0;
        for (const a of weekHistory) {
          const start = Math.max(new Date(a.startTime).getTime(), eightDaysAgo);
          const end = a.endTime ? new Date(a.endTime).getTime() : now;
          weekActualSec += (Math.min(end, now) - start) / 1000;
        }

        // Planned hours from schedule (match by operator name or vehicle name)
        let weekPlannedSec = 0;
        const opName = op.operatorName || '';
        const vehicleName = active ? active.assetText : '';
        for (const s of scheduleData) {
          if (s.status === 'cancelled') continue;
          if (!s.scheduledAt || !s.duration) continue;
          const schedMs = new Date(s.scheduledAt).getTime();
          if (schedMs < eightDaysAgo || schedMs > now + 7 * 24 * 3600 * 1000) continue;
          const truckMatch = s.truck && (s.truck.name === vehicleName || s.truck.driver === opName || s.truck.operator === opName);
          if (truckMatch) weekPlannedSec += s.duration;
        }

        // Vehicle location
        let currentVehicle = null;
        if (active) {
          const v = vehicleLocations[active.assetId];
          currentVehicle = {
            id: active.assetId,
            name: active.assetText,
            lat: v ? v.lat : null,
            lon: v ? v.lon : null,
            city: v ? v.city : '',
            state: v ? v.state : '',
            engineOn: v ? v.engineOn : false,
            speed: v ? v.speed : 0,
          };
        }

        // Medical card status
        let medicalCardStatus = 'unknown';
        if (op.medicalCardExpiration) {
          const expMs = new Date(op.medicalCardExpiration).getTime();
          const thirtyDays = 30 * 24 * 3600 * 1000;
          if (expMs < now) medicalCardStatus = 'expired';
          else if (expMs < now + thirtyDays) medicalCardStatus = 'expiring-soon';
          else medicalCardStatus = 'valid';
        }

        const todayActualHours = Math.round(todayActualSec / 360) / 10; // 1 decimal
        const weekActualHours = Math.round(weekActualSec / 360) / 10;
        const weekPlannedHours = Math.round(weekPlannedSec / 360) / 10;

        return {
          id: op.id,
          name: op.operatorName,
          firstName: op.firstName,
          lastName: op.lastName,
          employeeId: op.employeeId || '',
          status: active ? 'on-shift' : 'off-shift',
          todayActualHours,
          weekActualHours,
          weekPlannedHours,
          dailyRemaining: Math.max(0, Math.round((11 - todayActualHours) * 10) / 10),
          weeklyRemaining: Math.max(0, Math.round((70 - weekActualHours) * 10) / 10),
          hosSchedule: '70/8',
          currentVehicle,
          shiftStartTime: active ? active.startTime : null,
          medicalCardExpiration: op.medicalCardExpiration || null,
          medicalCardStatus,
          endorsements: (op.endorsements || []).map(e => e.name),
        };
      }).sort((a, b) => {
        // On-shift first, then by name
        if (a.status !== b.status) return a.status === 'on-shift' ? -1 : 1;
        return (a.name || '').localeCompare(b.name || '');
      });

      res.writeHead(200);
      res.end(JSON.stringify({ drivers, total: drivers.length, asOf: new Date().toISOString() }));
    } catch(e) {
      console.error('  [Drivers] Error:', e.message);
      res.writeHead(500);
      res.end(JSON.stringify({ error: e.message }));
    }})();
    return;
  }

  // Static files
  let filePath = pathname === '/' ? '/Route-Dashboard.html' : pathname;
  filePath = path.join(DIR, decodeURIComponent(filePath));
  if (!filePath.startsWith(DIR)) { res.writeHead(403); return res.end('Forbidden'); }

  const ext = path.extname(filePath).toLowerCase();
  fs.readFile(filePath, (err, data) => {
    if (err) { res.writeHead(err.code === 'ENOENT' ? 404 : 500); return res.end(err.code === 'ENOENT' ? 'Not found' : 'Error'); }
    res.writeHead(200, { 'Content-Type': MIME_TYPES[ext] || 'application/octet-stream' });
    res.end(data);
  });
});

server.listen(PORT, () => {
  console.log(`\n  Carter Lumber Route Dashboard`);
  console.log(`  http://localhost:${PORT}`);
  console.log(`\n  Routing: Mapbox -> OSRM fallback -> haversine estimate`);
  console.log(`  Logs:\n`);

  // Warm up IntelliShift asset cache in the background at startup
  if (IS_EMAIL && IS_PASSWORD) {
    loadBranch570Assets().catch(e => console.warn('  [IS] Startup preload failed:', e.message));
  }
});
