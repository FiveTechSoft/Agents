// ssh-proxy.js — WebSocket-to-TCP gateway for Agents Web SSH client.
// Usage: node ssh-proxy.js [port]
//        Default port: 8080
//        Set SSL_CERT + SSL_KEY env vars for wss:// (TLS).
//
// Protocol: target is sent as query params in the WebSocket URL:
//   ws://proxy:8080/?host=example.com&port=22&user=root
// All WebSocket data frames are raw TCP in both directions.

const http = require('http');
const net = require('net');
const crypto = require('crypto');
const fs = require('fs');

const PORT = parseInt(process.argv[2]) || parseInt(process.env.PORT) || 8080;

const tlsOpts = {};
if (process.env.SSL_CERT && process.env.SSL_KEY) {
  tlsOpts.cert = fs.readFileSync(process.env.SSL_CERT);
  tlsOpts.key = fs.readFileSync(process.env.SSL_KEY);
}

const server = tlsOpts.cert
  ? require('https').createServer(tlsOpts)
  : http.createServer();

server.on('request', (req, res) => {
  if (req.url === '/health') {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', uptime: process.uptime() }));
  } else {
    res.writeHead(200, { 'content-type': 'text/plain' });
    res.end('SSH WebSocket proxy — Agents Web\nUse: ssh user@host from the web terminal');
  }
});

// Minimal WebSocket (RFC 6455) — no external dependencies
server.on('upgrade', (req, socket, head) => {
  const key = req.headers['sec-websocket-key'];
  if (!key) { socket.destroy(); return; }

  const accept = crypto.createHash('sha1')
    .update(key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11', 'binary')
    .digest('base64');

  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
    'Upgrade: websocket\r\n' +
    'Connection: Upgrade\r\n' +
    'Sec-WebSocket-Accept: ' + accept + '\r\n' +
    '\r\n'
  );

  // Parse target from query string
  let targetHost = 'localhost', targetPort = 22, targetUser = '';
  try {
    const url = new URL(req.url, 'ws://localhost');
    targetHost = url.searchParams.get('host') || targetHost;
    targetPort = parseInt(url.searchParams.get('port')) || targetPort;
    targetUser = url.searchParams.get('user') || '';
  } catch (e) {}

  console.log(`SSH ${targetUser ? targetUser + '@' : ''}${targetHost}:${targetPort}`);

  const tcp = net.createConnection({ host: targetHost, port: targetPort }, () => {
    console.log(`  TCP connected`);
  });

  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    tcp.destroy();
    socket.destroy();
  };

  // WebSocket frame parser
  let buf = Buffer.alloc(0);

  socket.on('data', (chunk) => {
    if (closed) return;
    buf = Buffer.concat([buf, chunk]);

    while (buf.length >= 2) {
      const opcode = buf[0] & 0x0f;
      const masked = (buf[1] & 0x80) !== 0;
      let payloadLen = buf[1] & 0x7f;
      let offset = 2;

      if (payloadLen === 126) {
        if (buf.length < 4) break;
        payloadLen = buf.readUInt16BE(2);
        offset = 4;
      } else if (payloadLen === 127) {
        if (buf.length < 10) break;
        payloadLen = Number(buf.readBigUInt64BE(2));
        offset = 10;
      }

      const maskLen = masked ? 4 : 0;
      const frameLen = offset + maskLen + payloadLen;
      if (buf.length < frameLen) break;

      if (opcode === 0x8) { close(); return; }           // close
      if (opcode === 0x9) {                               // ping → pong
        const pong = Buffer.alloc(2 + payloadLen);
        pong[0] = 0x8a; pong[1] = payloadLen;
        if (payloadLen && buf.length >= offset + maskLen + payloadLen) {
          buf.copy(pong, 2, offset + maskLen, offset + maskLen + payloadLen);
        }
        socket.write(pong);
        buf = buf.slice(frameLen);
        continue;
      }

      if (opcode === 0x1 || opcode === 0x2) {            // text/binary → TCP
        const payload = buf.slice(offset + maskLen, frameLen);
        if (masked) {
          const mask = buf.slice(offset, offset + 4);
          for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i % 4];
        }
        if (!tcp.destroyed) tcp.write(payload);
        buf = buf.slice(frameLen);
        continue;
      }

      buf = buf.slice(frameLen); // unknown opcode → skip
    }
  });

  tcp.on('data', (chunk) => {
    if (closed) return;
    const len = chunk.length;
    let frame;
    if (len < 126) {
      frame = Buffer.alloc(2 + len);
      frame[0] = 0x82; frame[1] = len;
      chunk.copy(frame, 2);
    } else if (len < 65536) {
      frame = Buffer.alloc(4 + len);
      frame[0] = 0x82; frame[1] = 126;
      frame.writeUInt16BE(len, 2);
      chunk.copy(frame, 4);
    } else {
      frame = Buffer.alloc(10 + len);
      frame[0] = 0x82; frame[1] = 127;
      frame.writeBigUInt64BE(BigInt(len), 2);
      chunk.copy(frame, 10);
    }
    if (!socket.destroyed) socket.write(frame);
  });

  tcp.on('error', (e) => { console.error(`  TCP: ${e.message}`); close(); });
  tcp.on('close', () => close());
  socket.on('error', (e) => { console.error(`  WS: ${e.message}`); close(); });
  socket.on('close', () => close());
});

server.listen(PORT, () => {
  const proto = tlsOpts.cert ? 'wss' : 'ws';
  console.log(`SSH proxy: ${proto}://0.0.0.0:${PORT}`);
  console.log(`Health:   http://localhost:${PORT}/health`);
});
