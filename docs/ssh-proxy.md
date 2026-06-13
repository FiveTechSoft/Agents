# SSH Proxy — Agents Web

Gateway WebSocket↔TCP para el cliente SSH embebido en Agents Web.

## Arquitectura

```
Navegador                    Proxy (Node.js)              Servidor SSH
────────                     ────────────────              ────────────
xterm.js ──▶ WebSocket ──▶  WS frame parse ──▶ TCP ──▶  sshd :22
           ◀── WebSocket ◀── WS frame build ◀── TCP ◀──
```

- El proxy **no** descifra SSH. Es un pipe transparente de bytes.
- La autenticación SSH ocurre entre el navegador y el servidor SSH.
- Target (`host`, `port`, `user`) se envía como query params en la URL del WebSocket.

## Requisitos

- Node.js 18+
- Sin dependencias npm (usa solo módulos estándar: `http`, `net`, `crypto`)

## Uso

```bash
# Puerto por defecto (8080, ws://)
node ssh-proxy.js

# Puerto específico
node ssh-proxy.js 3000

# Con TLS (wss://) para usar desde GitHub Pages (HTTPS)
SSL_CERT=/etc/letsencrypt/live/proxy.example.com/fullchain.pem \
SSL_KEY=/etc/letsencrypt/live/proxy.example.com/privkey.pem \
node ssh-proxy.js 8443
```

## Cómo usarlo

### Opción A: Deno Deploy (gratis, recomendado)

[Deno Deploy](https://dash.deno.com) ofrece WebSocket + TCP en su tier gratuito.
Sin tarjeta de crédito. Despliegue en 30 segundos:

1. Ve a https://dash.deno.com → **New Playground** (o crea un proyecto)
2. Pega el contenido de `ssh-proxy.deno.js`
3. Haz clic en **Deploy**
4. Copia la URL (tipo `https://tu-proyecto.deno.dev`)
5. En Agents Web:

```bash
sshproxy wss://tu-proyecto.deno.dev/ssh
/ssh anto@192.168.18.184
```

Ventajas: siempre disponible, TLS incluido, gratis, sin instalar nada local.

### Opción B: Cloudflare Worker (Workers Paid, $5/mes)

Requiere Workers Paid por la API `connect()`. El worker `cloudflare-worker.js`
ya incluye el endpoint `/ssh`.

```bash
sshproxy wss://tu-worker.workers.dev/ssh
```

### Opción C: Proxy local (ssh-proxy.js)

```bash
node ssh-proxy.js 8080
```

En Agents Web:

```bash
sshproxy ws://localhost:8080        # desarrollo local
sshproxy wss://proxy.example.com    # producción con TLS
/ssh anto@192.168.18.184            # conectar
/ssh -p 2222 admin@10.0.0.1         # puerto personalizado
/ssh anto@host.com 2222             # puerto sin -p
```

## Health check

```bash
curl http://localhost:8080/health
# {"status":"ok","uptime":12.5}
```

## Seguridad

- **No usar sin TLS en producción.** `ws://` envía tráfico en claro.
- Para exponerlo a internet, ponlo detrás de un reverse proxy con TLS (nginx, Caddy)
  o usa `SSL_CERT`/`SSL_KEY` para TLS nativo.
- El proxy **no** autentica — la autenticación la hace SSH.
- No expone credenciales: el tráfico SSH viaja cifrado de extremo a extremo.
- Limita acceso por IP en el firewall si es posible.

## Protocolo

WebSocket estándar (RFC 6455), implementación mínima:

1. Cliente abre `ws://proxy:8080/?host=example.com&port=22&user=root`
2. Proxy hace upgrade HTTP→WebSocket, parsea query params
3. Proxy abre TCP socket a `example.com:22`
4. Todos los frames WebSocket (binary/text) → reenviados a TCP
5. Datos TCP → frames WebSocket binary → cliente
6. Cualquiera cierra → se cierra el otro lado
