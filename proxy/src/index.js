// Rooster's proxy (Cloudflare Worker). The app reaches third-party services
// through it so their API keys stay here and users' IPs stay with us:
//
//   /proxy/klipy/api/v2/{search,featured}  KLIPY's Tenor-compatible API; we
//                                          add the key (secret KLIPY_API_KEY)
//   /proxy/klipy/media/<path>              static.klipy.com, the GIF files
//   /proxy/signal/stickers/<path>          Signal's sticker CDN (pack import)
//
// Only GET, only these routes, and only the query parameters the app sends.

const KLIPY_ENDPOINTS = new Set(["search", "featured"]);
const KLIPY_PARAMS = ["q", "pos", "limit", "locale"];

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });
    if (request.method !== "GET") return text("Method not allowed", 405);

    const url = new URL(request.url);
    const path = url.pathname;

    const api = path.match(/^\/proxy\/klipy\/api\/v2\/([a-z]+)$/);
    if (api) {
      if (!KLIPY_ENDPOINTS.has(api[1])) return text("Not found", 404);
      if (!env.KLIPY_API_KEY) return text("GIF search is not configured", 503);
      const upstream = new URL(`https://api.klipy.com/v2/${api[1]}`);
      for (const name of KLIPY_PARAMS) {
        const value = url.searchParams.get(name);
        if (value !== null) upstream.searchParams.set(name, value);
      }
      upstream.searchParams.set("key", env.KLIPY_API_KEY);
      upstream.searchParams.set("client_key", "rooster");
      upstream.searchParams.set("contentfilter", "medium");
      return relay(upstream, 300);
    }

    if (path.startsWith("/proxy/klipy/media/")) {
      return relay(`https://static.klipy.com/${path.slice(19)}`, 86400);
    }

    if (path.startsWith("/proxy/signal/stickers/")) {
      return relay(`https://cdn-ca.signal.org/${path.slice(14)}`, 86400);
    }

    return text("Not found", 404);
  },
};

// An upstream that hangs must not hang the app's request with it (the GIF
// picker waited on the browser's own limit), and one that fails must come
// back as a response with CORS headers, not as a thrown exception the
// browser shows the app as an opaque CORS failure.
const UPSTREAM_TIMEOUT_MS = 8000;

async function relay(upstream, cacheSeconds) {
  let response;
  try {
    response = await fetch(upstream, {
      cf: { cacheEverything: true, cacheTtl: cacheSeconds },
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    });
  } catch (error) {
    const timedOut = error && error.name === "TimeoutError";
    return text(timedOut ? "Upstream timed out" : "Upstream unavailable", timedOut ? 504 : 502);
  }
  const headers = new Headers(CORS);
  // Not Content-Length: the runtime may have decompressed the body, and a
  // length that no longer matches it truncates the response.
  for (const name of ["Content-Type", "Cache-Control"]) {
    const value = response.headers.get(name);
    if (value) headers.set(name, value);
  }
  return new Response(response.body, { status: response.status, headers });
}

function text(body, status) {
  return new Response(body, { status, headers: CORS });
}
