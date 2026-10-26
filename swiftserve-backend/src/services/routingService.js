const ORS_DIRECTIONS_URL = 'https://api.openrouteservice.org/v2/directions/driving-car/geojson';
const CACHE_MAX_ENTRIES = 500;
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const REQUEST_TIMEOUT_MS = 8000;

const cache = new Map();

const routingError = (code, message) => {
  const error = new Error(message);
  error.code = code;
  return error;
};

const cacheKey = (from, to) => [from.lat, from.lng, to.lat, to.lng]
  .map((value) => Number(value).toFixed(5))
  .join(',');

const readCache = (key) => {
  const entry = cache.get(key);
  if (!entry) return null;
  if (Date.now() - entry.storedAt > CACHE_TTL_MS) {
    cache.delete(key);
    return null;
  }
  return entry.route;
};

const writeCache = (key, route) => {
  cache.delete(key);
  while (cache.size >= CACHE_MAX_ENTRIES) {
    // Map keeps insertion order, so the first key is the oldest entry.
    cache.delete(cache.keys().next().value);
  }
  cache.set(key, { route, storedAt: Date.now() });
};

const getRoadRoute = async ({ from, to }) => {
  const apiKey = process.env.ORS_API_KEY;
  if (!apiKey) {
    throw routingError('ROUTING_NOT_CONFIGURED', 'Road routing is not configured.');
  }

  const key = cacheKey(from, to);
  const cached = readCache(key);
  if (cached) return cached;

  let body;
  try {
    const response = await fetch(ORS_DIRECTIONS_URL, {
      method: 'POST',
      headers: {
        Authorization: apiKey,
        'Content-Type': 'application/json',
        Accept: 'application/geo+json, application/json',
      },
      body: JSON.stringify({ coordinates: [[from.lng, from.lat], [to.lng, to.lat]] }),
      signal: AbortSignal.timeout(REQUEST_TIMEOUT_MS),
    });
    if (!response.ok) {
      throw new Error(`ORS responded with ${response.status}`);
    }
    body = await response.json();
  } catch (error) {
    console.error('Road routing request failed:', error.message);
    throw routingError('ROUTING_UNAVAILABLE', 'Road route is unavailable right now.');
  }

  const feature = body?.features?.[0];
  const coordinates = feature?.geometry?.coordinates;
  const summary = feature?.properties?.summary;
  if (!Array.isArray(coordinates) || coordinates.length < 2) {
    throw routingError('ROUTING_UNAVAILABLE', 'No road route was found between these points.');
  }

  const route = {
    points: coordinates.map(([lng, lat]) => [lat, lng]),
    distanceMeters: Number(summary?.distance) || 0,
    durationSeconds: Number(summary?.duration) || 0,
  };
  writeCache(key, route);
  return route;
};

module.exports = { getRoadRoute };
