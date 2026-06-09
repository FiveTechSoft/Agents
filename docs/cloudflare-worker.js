/**
 * Agents Web — CORS proxy (Cloudflare Worker, free tier).
 *
 * Two call styles:
 *   1) Generic:  https://YOUR-WORKER/?url=https%3A%2F%2Fhost%2Ffile.zip   (curl/wget, binary OK)
 *   2) Path:     https://YOUR-WORKER/https://github.com/owner/repo.git/...  (isomorphic-git smart-http)
 *
 * Passes method, headers (incl. Authorization) and body through; streams binary
 * responses unchanged; adds permissive CORS so a static page can use it.
 *
 * Deploy (1 minute):
 *   - https://dash.cloudflare.com -> Workers & Pages -> Create Worker
 *   - paste this file, Deploy. Copy the *.workers.dev URL.
 *   - in Agents Web run:  /proxy https://your-worker.your-name.workers.dev
 * Or with wrangler:  npx wrangler deploy cloudflare-worker.js
 */
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS,HEAD',
  'Access-Control-Allow-Headers': '*',
  'Access-Control-Expose-Headers': '*',
  'Access-Control-Max-Age': '86400',
};

export default {
  async fetch(request) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: CORS });

    const u = new URL(request.url);
    // target: ?url=<encoded>  OR  everything after the leading slash (git smart-http style)
    let target = u.searchParams.get('url');
    if (!target) target = decodeURIComponent(u.pathname.slice(1)) + (u.search || '');
    if (!/^https?:\/\//i.test(target)) {
      return new Response('Usage: /?url=<https url>  or  /<https url>', { status: 400, headers: CORS });
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
