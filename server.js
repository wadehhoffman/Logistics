const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const url = require('url');

const PORT = 3003;
const DIR = __dirname;

// Load secrets from secrets.js (gitignored) — never commit API keys
let secrets = {};
try { secrets = require('./secrets'); } catch(e) {}
const MAPBOX_TOKEN = secrets.MAPBOX_TOKEN || process.env.MAPBOX_TOKEN || '';

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
    const qs = `?geometries=geojson&overview=${overview}&access_token=${MAPBOX_TOKEN}`;
    const mapbox = `https://api.mapbox.com/directions/v5/mapbox/driving/${coords}${qs}`;
    const osrmFallback = `https://router.project-osrm.org/route/v1/driving/${coords}?overview=${overview}&geometries=geojson`;
    console.log('  Route request — Mapbox primary, OSRM fallback, haversine estimate');
    return proxyRequest(mapbox, res, [osrmFallback], () => generateFallbackRoute(coords, overview));
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

  // Open-Meteo weather (single call, no API key needed)
  if (pathname === '/api/weather') {
    const { lat, lon } = parsed.query;
    const url = `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,relative_humidity_2m,wind_speed_10m,wind_direction_10m,weather_code,apparent_temperature&wind_speed_unit=mph&temperature_unit=fahrenheit&forecast_days=1`;
    return simpleProxy(url, res);
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
  console.log(`\n  Routing: OSRM -> FOSSGIS mirror -> haversine estimate`);
  console.log(`  Logs:\n`);
});
