const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const url = require('url');

const crypto = require('crypto');

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
    .map(a => ({ id: a.id, name: a.name || String(a.id), branchId: a.branchId }));
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
    return {
      id:         a.id,
      name:       loc.vehicleName || a.name,
      lat:        parseFloat(loc.latitude  || loc.lat  || 0),
      lon:        parseFloat(loc.longitude || loc.lon  || 0),
      speed:      loc.speed       || 0,
      heading:    loc.headingDegrees !== undefined ? loc.headingDegrees : (loc.heading || 0),
      engineOn:   loc.engineOn    || false,
      driver:     loc.driverName  || '',
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

  // Client config — vends public tokens safe for browser use
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

  // GET /api/schedule — list all (optional ?month=2026-04 filter)
  if (pathname === '/api/schedule' && req.method === 'GET') {
    res.setHeader('Access-Control-Allow-Origin', '*');
    res.setHeader('Content-Type', 'application/json');
    const month = parsed.query.month; // e.g. "2026-04"
    let results = scheduleData;
    if (month) {
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
      scheduleData.push(entry);
      saveSchedule();
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
      if (body.status) scheduleData[idx].status = body.status;
      if (body.notes !== undefined) scheduleData[idx].notes = body.notes;
      if (body.scheduledAt) scheduleData[idx].scheduledAt = body.scheduledAt;
      if (body.truck) scheduleData[idx].truck = body.truck;
      saveSchedule();
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
    scheduleData.splice(idx, 1);
    saveSchedule();
    console.log(`  [Schedule] Deleted: ${id}`);
    res.writeHead(200);
    return res.end(JSON.stringify({ ok: true }));
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
