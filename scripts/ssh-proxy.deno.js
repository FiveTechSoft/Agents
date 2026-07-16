// ssh-proxy.deno.js — SSH WebSocket tunnel for Deno Deploy (free tier).
// Deploy: https://dash.deno.com → New Playground → paste this → Deploy
// The free tier includes WebSocket + TCP connect. No credit card required.
//
// Usage in Agents Web:
//   sshproxy wss://your-project.deno.dev/ssh
//   /ssh anto@192.168.18.184

Deno.serve(async (req) => {
  const url = new URL(req.url);

  // Health check
  if (url.pathname === '/health') {
    return new Response(JSON.stringify({ status: 'ok' }), {
      headers: { 'content-type': 'application/json', 'access-control-allow-origin': '*' }
    });
  }

  // SSH WebSocket tunnel
  if (url.pathname === '/ssh' && req.headers.get('upgrade') === 'websocket') {
    const host = url.searchParams.get('host') || 'localhost';
    const port = parseInt(url.searchParams.get('port')) || 22;

    try {
      const { socket, response } = Deno.upgradeWebSocket(req);
      const tcp = await Deno.connect({ hostname: host, port, transport: 'tcp' });

      let closed = false;
      const cleanup = () => {
        if (closed) return;
        closed = true;
        try { socket.close(); } catch (_) {}
        try { tcp.close(); } catch (_) {}
      };

      socket.onopen = () => {};
      socket.onmessage = (ev) => {
        if (closed) return;
        try {
          const data = ev.data instanceof ArrayBuffer
            ? new Uint8Array(ev.data)
            : new TextEncoder().encode(ev.data);
          tcp.write(data);
        } catch (_) { cleanup(); }
      };
      socket.onclose = cleanup;
      socket.onerror = cleanup;

      // TCP → WebSocket
      (async () => {
        const buf = new Uint8Array(8192);
        try {
          while (!closed) {
            const n = await tcp.read(buf);
            if (n === null) break;
            if (closed) break;
            socket.send(buf.slice(0, n));
          }
        } catch (_) {}
        cleanup();
      })();

      return response;
    } catch (e) {
      return new Response('SSH tunnel error: ' + e.message, {
        status: 500,
        headers: { 'access-control-allow-origin': '*' }
      });
    }
  }

  // Landing page
  return new Response(
    'SSH tunnel — Agents Web\nUse: wss://' + url.host + '/ssh?host=target&port=22\nHealth: /health',
    { headers: { 'content-type': 'text/plain', 'access-control-allow-origin': '*' } }
  );
});
