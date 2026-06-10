/**
 * Agents Web — CORS proxy + short session links (Cloudflare Worker, free tier).
 *
 * Call styles:
 *   1) Generic proxy:  https://YOUR-WORKER/?url=https%3A%2F%2Fhost%2Ffile.zip   (curl/wget, binary OK)
 *   2) Path proxy:     https://YOUR-WORKER/https://github.com/owner/repo.git/...  (isomorphic-git smart-http)
 *   3) Sessions (KV):  POST /session  (JSON body)  -> {"id":"aB3xYz12k"}
 *                      GET  /session/<id>          -> the stored JSON
 *
 * Proxy passes method, headers (incl. Authorization) and body through; streams binary
 * responses unchanged; adds permissive CORS so a static page can use it.
 *
 * Deploy (2 minutes):
 *   - https://dash.cloudflare.com -> Workers & Pages -> Create Worker -> paste this file, Deploy.
 *   - Sessions need a KV namespace: Storage & Databases -> KV -> Create namespace "agents-sessions",
 *     then Worker -> Settings -> Bindings -> Add -> KV namespace, variable name SESSIONS.
 *   - in Agents Web run:  /proxy https://your-worker.your-name.workers.dev
 *     From then on the Share button stores sessions in KV and yields short links.
 * Or with wrangler, create wrangler.toml:
 *   name = "agents-proxy"
 *   main = "cloudflare-worker.js"
 *   compatibility_date = "2026-01-01"
 *   [[kv_namespaces]]
 *   binding = "SESSIONS"
 *   id = "<your-kv-namespace-id>"
 * and run:  npx wrangler deploy
 *
 * Sessions expire after 180 days (SESSION_TTL). Size cap 2 MB.
 */
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Expose-Headers': '*',
  'Access-Control-Max-Age': '86400',
};
const SESSION_TTL = 60 * 60 * 24 * 180;   // 180 days
const SESSION_MAX = 2_000_000;            // 2 MB

const json = (obj, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...CORS, 'content-type': 'application/json' } });

const ALPHA = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
function newId(len = 10) {
  const r = crypto.getRandomValues(new Uint8Array(len));
  let id = ''; for (const b of r) id += ALPHA[b % ALPHA.length];
  return id;
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });

    const u = new URL(request.url);

    // ---- short session links (KV) ----
    if (u.pathname === '/session' && request.method === 'POST') {
      if (!env || !env.SESSIONS) return json({ error: 'KV namespace SESSIONS not bound (see file header)' }, 501);
      const body = await request.text();
      if (!body) return json({ error: 'empty body' }, 400);
      if (body.length > SESSION_MAX) return json({ error: 'session too big (2MB max)' }, 413);
      try { JSON.parse(body); } catch (e) { return json({ error: 'body must be JSON' }, 400); }
      const id = newId();
      await env.SESSIONS.put(id, body, { expirationTtl: SESSION_TTL });
      return json({ id });
    }
    if (u.pathname.startsWith('/session/') && request.method === 'GET') {
      if (!env || !env.SESSIONS) return json({ error: 'KV namespace SESSIONS not bound (see file header)' }, 501);
      const v = await env.SESSIONS.get(u.pathname.slice('/session/'.length));
      if (v == null) return json({ error: 'not found or expired' }, 404);
      return new Response(v, { headers: { ...CORS, 'content-type': 'application/json' } });
    }

    // ---- generic CORS proxy ----
    // target: ?url=<encoded>  OR  everything after the leading slash (git smart-http style)
    let target = u.searchParams.get('url');
    if (!target) target = decodeURIComponent(u.pathname.slice(1)) + (u.search || '');
    // isomorphic-git's corsProxy strips the scheme: /github.com/owner/repo.git/... -> add https://
    if (!/^https?:\/\//i.test(target) && /^[\w.-]+\.[a-z]{2,}(:\d+)?\//i.test(target)) target = 'https://' + target;
    if (!/^https?:\/\//i.test(target)) {
      return new Response('Usage: /?url=<https url>  or  /<https url>  or  POST /session', { status: 400, headers: CORS });
    }

    const h = new Headers(request.headers);
    h.delete('host'); h.delete('origin'); h.delete('referer'); h.delete('cf-connecting-ip');

    const init = { method: request.method, headers: h, redirect: 'follow' };
    if (!['GET', 'HEAD'].includes(request.method)) init.body = request.body;

    let resp;
    try { resp = await fetch(target, init); }
    catch (e) { return new Response('proxy fetch failed: ' + e, { status: 502, headers: CORS }); }

    const out = new Headers(resp.headers);
    for (const k in CORS) out.set(k, CORS[k]);
    return new Response(resp.body, { status: resp.status, statusText: resp.statusText, headers: out });
  },
};
