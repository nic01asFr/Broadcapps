# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Grist Realtime Broadcasting System** - A real-time synchronization system for Grist using n8n and Server-Sent Events (SSE). Developed by CEREMA Méditerranée for tracking field interventions.

### Core Purpose
When a field agent updates an intervention status in Grist, all connected supervisors see the update instantly (<500ms latency) without manual refresh. The system broadcasts changes via Redis Pub/Sub and SSE streams.

## Architecture

### Four-Layer System

```
Grist Table (Data Source)
    ↓ Webhook on add/update
n8n Workflow (Orchestrator)
    ↓ HTTP POST to SSE Bridge
Redis SSE Bridge Server (Node.js)
    ↓ Redis Pub/Sub + SSE Streams
Widget Dashboards (All connected clients)
```

### Data Flow
1. **Grist**: Agent modifies row → Automatic webhook fires
2. **n8n**: Receives webhook → Validates → HTTP POST to redis-sse-bridge server
3. **redis-sse-bridge**: Publishes to Redis channel → Broadcasts to all SSE clients
4. **Widgets**: Receive SSE update → Refresh UI with animation/notification
5. **Latency**: 300-500ms end-to-end

**Why the SSE Bridge?** n8n's Redis nodes don't support `subscribe` operation or `executeCommand`. The bridge server (redis-sse-bridge.js) handles Redis Pub/Sub and maintains long-lived SSE connections to widgets, while n8n sends HTTP requests to it.

### Components

**grist-realtime-dashboard-widget.html** (1015 lines)
- Standalone HTML/JavaScript widget hosted on GitHub Pages
- Connects to Grist API for initial data load (handles columnar data format)
- Establishes SSE connection to redis-sse-bridge server
- Real-time UI updates with visual/sound notifications
- Auto-reconnection on disconnect with exponential backoff
- Filters: active/all/urgent interventions
- Stores SSE URL in localStorage for configuration

**redis-sse-bridge.js** (307 lines) - NEW CORE COMPONENT
- Node.js Express server bridging n8n, Redis, and widgets
- Exposes HTTP endpoints for n8n to publish messages
- Maintains Redis Pub/Sub subscriber listening on `grist-realtime-interventions`
- Manages long-lived SSE connections to all widget clients
- Endpoints:
  - `GET /sse-stream` - SSE endpoint for widgets (replaces n8n SSE Trigger)
  - `POST /redis/publish` - Publish to Redis channel (called by n8n)
  - `POST /redis/setex` - Cache with TTL (called by n8n)
  - `GET /redis/get/:key` - Read cached data
  - `GET /health` - Health check with client count
- Heartbeat every 30s to maintain connections
- Graceful shutdown handling (SIGTERM)

**package.json**
- Dependencies: express (4.18.2), redis (4.6.12), cors (2.8.5)
- Type: "module" (ES modules)
- Required for redis-sse-bridge.js server

**n8n-workflow-1-grist-to-sse-server.json** (256 lines)
- Production-ready n8n workflow using HTTP requests (not Redis nodes)
- Webhook: `POST /webhook/grist-realtime` - Receives Grist webhooks
- Pipeline: Webhook → Validate → Prepare → HTTP Publish → HTTP SETEX → Response
- Uses HTTP POST to redis-sse-bridge endpoints instead of n8n Redis nodes
- Urgent interventions trigger Tchap (Matrix) notifications
- Redis cache with 24h TTL via HTTP SETEX
- CORS enabled for cross-origin requests
- Metrics logging included

**n8n-workflow-2-api-interventions.json** (197 lines)
- Fallback polling endpoint: `GET /webhook/interventions`
- Uses n8n Redis nodes (KEYS, GET) to aggregate cached interventions
- Returns sorted JSON array (by priority: Urgente > Haute > Normale > Basse)
- Used when SSE is unavailable or for initial data sync
- CORS enabled, Cache-Control: no-cache

**INSTALLATION-SSE-SERVER.md** (462 lines)
- Complete installation guide for redis-sse-bridge.js server
- systemd service configuration
- Nginx reverse proxy setup for HTTPS
- Testing procedures (health check, SSE stream, publish, setex)
- Troubleshooting guide
- Monitoring commands

## Key Technical Patterns

### SSE Connection Management
The widget implements robust reconnection logic:
- Exponential backoff on errors (5s delay)
- Visual indicators (green=connected, red=disconnected, orange=connecting)
- Fallback to periodic polling every 60s
- Connection state stored in DOM for UI updates

### Redis Pub/Sub Architecture
- **Channel**: `grist-realtime-interventions`
- **Publisher**: redis-sse-bridge server (triggered by n8n HTTP POST)
- **Subscriber**: redis-sse-bridge server (listening continuously)
- **SSE Broadcaster**: redis-sse-bridge server (broadcasts to all connected widgets)
- **Cache**: Redis SETEX via HTTP POST from n8n (24h TTL per intervention)

**Flow**: n8n → HTTP POST `/redis/publish` → redis-sse-bridge → Redis Pub/Sub → redis-sse-bridge → SSE broadcast to all widgets

### n8n Workflow Structure
The workflow (n8n-workflow-1-grist-to-sse-server.json) has **3 main branches**:
1. **Grist Webhook Branch**: Validation → Prepare → HTTP Publish → HTTP SETEX → Response
2. **Urgent Notification Branch**: Filter urgentes → Tchap API call
3. **Metrics Logging Branch**: Log execution metrics

**No longer using**:
- ❌ n8n SSE Trigger node (replaced by redis-sse-bridge /sse-stream endpoint)
- ❌ n8n Redis Subscribe node (not supported)
- ❌ n8n Redis Publish/Set nodes (replaced by HTTP requests to redis-sse-bridge)

### Message Format
```javascript
{
  timestamp: "2024-11-17T...",
  type: "intervention_update",
  action: "update" | "add",
  data: {
    id: "...",
    agent: "...",
    localisation: "...",
    type: "Voirie|Signalisation|Bâtiment|Autre",
    statut: "En attente|En cours|Terminé|Bloqué",
    priorite: "Basse|Normale|Haute|Urgente",
    commentaire: "..."
  },
  metadata: {
    source: "grist",
    workflowId: "...",
    executionId: "..."
  }
}
```

## Required Grist Configuration

### Table Structure
Table name: `Interventions`

| Column | Type | Notes |
|--------|------|-------|
| ID | Text | Unique identifier |
| Agent | Text | Field agent name |
| Localisation | Text | Intervention location |
| Type | Choice | Voirie, Signalisation, Bâtiment, Autre |
| Statut | Choice | En attente, En cours, Terminé, Bloqué |
| Priorite | Choice | Basse, Normale, Haute, Urgente |
| Derniere_MAJ | DateTime | Formula: `NOW()` |
| Commentaire | Text | Optional notes |

### Webhook Configuration
- Path: Document Settings → Webhooks
- URL: `https://your-n8n.cerema.fr/webhook/grist-realtime`
- Events: `add`, `update`
- Table: `Interventions`
- Enabled: Yes

## Development Commands

### Installation
```bash
# Step 1: Install Redis
sudo apt install redis-server
sudo systemctl enable redis-server
redis-cli ping  # Should return PONG

# Step 2: Install Node.js (≥18.0.0)
node --version  # Check version
# If needed:
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Step 3: Clone and install SSE bridge server
cd /opt
git clone https://github.com/nic01asFr/Broadcapps.git
cd Broadcapps
npm install  # Installs express, redis, cors

# Step 4: Configure and start SSE bridge server
# Create systemd service (see INSTALLATION-SSE-SERVER.md)
sudo systemctl enable redis-sse-bridge
sudo systemctl start redis-sse-bridge
sudo systemctl status redis-sse-bridge  # Should show "active (running)"

# Step 5: Configure Nginx reverse proxy (optional, for HTTPS)
# See INSTALLATION-SSE-SERVER.md for Nginx config
```

### Testing
```bash
# Test SSE bridge server health
curl http://localhost:3001/health
# Expected: {"status":"healthy","uptime":...,"clients":0,"redis":"connected"}

# Test SSE stream connection
curl -N http://localhost:3001/sse-stream
# Should maintain connection and show heartbeats

# Test Redis publish (simulates n8n)
curl -X POST http://localhost:3001/redis/publish \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "grist-realtime-interventions",
    "message": {"type":"test","data":{"id":"test-123","agent":"Test"}}
  }'

# Test n8n webhook endpoint
curl -X POST https://your-n8n.cerema.fr/webhook/grist-realtime \
  -H "Content-Type: application/json" \
  -d '{"id":"test123","fields":{"Agent":"Test","Statut":"En cours"}}'

# Check SSE server logs
sudo journalctl -u redis-sse-bridge -f
```

### Monitoring
```bash
# View SSE bridge server logs
sudo journalctl -u redis-sse-bridge -f        # Real-time logs
sudo journalctl -u redis-sse-bridge -n 100    # Last 100 lines
sudo journalctl -u redis-sse-bridge --since today  # Today's logs

# Check SSE bridge server status
curl http://localhost:3001/health | jq '.clients'  # Number of connected widgets

# Redis stats
redis-cli info stats
redis-cli info memory
redis-cli KEYS "intervention:*"  # List cached interventions
redis-cli TTL "intervention:test-123"  # Check TTL

# Check SSE connections
netstat -an | grep :3001 | grep ESTABLISHED | wc -l

# Monitor server resources
ps aux | grep redis-sse-bridge  # CPU and memory usage
```

## Important Implementation Details

### Widget Loading Sequence
1. Check for SSE URL in localStorage
2. If missing → Show config panel for URL entry (should be redis-sse-bridge /sse-stream endpoint)
3. Connect to Grist API with `requiredAccess: 'read table'`
4. Fetch initial data from selected table (handles Grist columnar data format)
5. Establish SSE connection to redis-sse-bridge server (not n8n)
6. Render dashboard with stats and interventions list
7. Set up periodic refresh fallback (60s interval)
8. On SSE message → Parse JSON → Update interventions → Re-render → Show notification

**Correct SSE URL**: `http://your-server:3001/sse-stream` or `https://your-domain/sse-stream` (via Nginx)

### Redis Configuration for Production
Recommended settings in `/etc/redis/redis.conf`:
- `bind 127.0.0.1` - Localhost only (redis-sse-bridge runs on same server)
- `maxmemory 256mb` - Memory limit for caching
- `maxmemory-policy allkeys-lru` - Eviction policy (remove least recently used)
- `protected-mode yes` - Security enabled
- Save snapshots: 900s/1 change, 300s/10 changes, 60s/10000 changes
- Default port: 6379

**Connection**: redis-sse-bridge.js connects to `localhost:6379` by default (configurable via env vars)

### Nginx Reverse Proxy Configuration (Optional)
For exposing redis-sse-bridge via HTTPS:

```nginx
# SSE Stream endpoint
location /sse-stream {
    proxy_pass http://localhost:3001/sse-stream;
    proxy_http_version 1.1;
    proxy_set_header Connection 'keep-alive';
    proxy_set_header Host $host;
    proxy_cache_bypass $http_upgrade;

    # SSE-specific headers
    proxy_buffering off;
    proxy_cache off;
    proxy_set_header X-Real-IP $remote_addr;

    # Long timeouts for SSE
    proxy_connect_timeout 1h;
    proxy_send_timeout 1h;
    proxy_read_timeout 1h;

    # CORS headers
    add_header Access-Control-Allow-Origin * always;
}

# API endpoints
location /redis/ {
    proxy_pass http://localhost:3001/redis/;
    add_header Access-Control-Allow-Origin * always;
}
```

See `INSTALLATION-SSE-SERVER.md` for complete Nginx configuration.

### n8n Credentials Required
**Only 1 credential needed** (Redis credential no longer required):

1. **Tchap credential** (optional, for urgent notifications):
   - Type: HTTP Header Auth
   - Name: "Tchap Token"
   - Header: Authorization
   - Value: `Bearer YOUR_TCHAP_TOKEN`

**Environment Variables**:
- `TCHAP_ROOM_ID`: Matrix room ID (ex: `!abc123:agent.tchap.gouv.fr`)

**No Redis credential needed**: The workflow uses HTTP requests to redis-sse-bridge, not n8n Redis nodes.

### SSE Format Requirements
The redis-sse-bridge server creates standard SSE messages:
```javascript
// In redis-sse-bridge.js line 87
const sseMessage = `data: ${message}\n\n`;
```

**Standard SSE format**:
```
data: {"timestamp":"2024-11-17T...","type":"intervention_update","action":"update","data":{...}}

```

**Key points**:
- Prefix with `data: ` (SSE spec requirement)
- End with double newline `\n\n` (required by SSE spec)
- Heartbeat comments `: heartbeat\n\n` every 30s to keep connection alive
- Connection header: `Content-Type: text/event-stream`, `Cache-Control: no-cache`

## Deployment Checklist

When deploying or modifying this system:

### Backend (VPS Server)
- [ ] Redis installed and `redis-cli ping` returns PONG
- [ ] Node.js ≥18.0.0 installed (`node --version`)
- [ ] Repository cloned to `/opt/Broadcapps`
- [ ] Dependencies installed (`npm install`)
- [ ] redis-sse-bridge.js systemd service created and enabled
- [ ] redis-sse-bridge service running (`systemctl status redis-sse-bridge`)
- [ ] Health check returns healthy: `curl http://localhost:3001/health`
- [ ] SSE stream maintains connection: `curl -N http://localhost:3001/sse-stream`
- [ ] (Optional) Nginx reverse proxy configured for HTTPS
- [ ] n8n workflows imported (n8n-workflow-1-grist-to-sse-server.json)
- [ ] n8n workflows activated (check Active toggle)
- [ ] (Optional) Tchap credential configured in n8n
- [ ] Grist webhook created pointing to n8n URL

### Frontend (GitHub Pages)
- [ ] GitHub Pages enabled on repository
- [ ] Widget accessible at: `https://nic01asfr.github.io/Broadcapps/grist-realtime-dashboard-widget.html`
- [ ] .nojekyll file present (prevents Jekyll parsing errors)

### Integration Testing
- [ ] Test n8n webhook: `curl -X POST https://n8n.../webhook/grist-realtime -d '{...}'`
- [ ] Webhook returns `{"success":true}`
- [ ] Check redis-sse-bridge logs show published message
- [ ] Widget loaded in Grist with SSE URL: `http://server:3001/sse-stream` (or HTTPS via Nginx)
- [ ] Live indicator shows green (connected)
- [ ] Connected clients count > 0: `curl localhost:3001/health | jq '.clients'`
- [ ] Test real update: modify Grist row → see instant update in widget (<500ms)
- [ ] Notification sound/animation works
- [ ] Urgent priority triggers Tchap notification (if configured)

## Performance Characteristics

Based on production usage at CEREMA:

| Metric | Value | Notes |
|--------|-------|-------|
| End-to-end latency | <500ms | Grist → Widget update |
| Concurrent clients | 100+ | Tested without degradation |
| Bandwidth per client | ~1KB/min | Very low impact |
| Redis memory | ~50MB | For 10K messages/day |
| n8n CPU usage | <5% | Normal load |
| Availability | 99.9% | With auto-reconnect |

## Common Issues

### Widget shows "DÉCONNECTÉ" (disconnected)
- Check SSE URL points to redis-sse-bridge (not n8n): `http://server:3001/sse-stream`
- Verify redis-sse-bridge service is running: `systemctl status redis-sse-bridge`
- Test SSE endpoint: `curl -N http://localhost:3001/sse-stream`
- Check CORS headers in redis-sse-bridge response
- Inspect browser console for detailed errors
- Check redis-sse-bridge logs: `journalctl -u redis-sse-bridge -f`

### Webhook not triggering n8n
- Verify webhook URL in Grist settings points to n8n
- Check n8n workflow is active (not inactive)
- Test with manual curl to webhook endpoint
- Check n8n execution history for errors
- Verify network connectivity Grist → n8n

### redis-sse-bridge not starting
- Check Node.js version: `node --version` (must be ≥18.0.0)
- Verify dependencies installed: `npm install` in `/opt/Broadcapps`
- Check Redis is running: `systemctl status redis-server`
- Check systemd service logs: `journalctl -u redis-sse-bridge -n 50`
- Verify port 3001 is not already in use: `lsof -i :3001`

### Redis connection refused
- Check Redis service: `systemctl status redis-server`
- Test connection: `redis-cli ping`
- Verify bind address in `/etc/redis/redis.conf`
- Check firewall rules for port 6379
- Check redis-sse-bridge can connect: see logs in `journalctl`

### Messages not reaching widgets
- Verify n8n workflow successfully publishes: check n8n execution logs
- Test publish endpoint manually: `curl -X POST http://localhost:3001/redis/publish -d '{...}'`
- Check redis-sse-bridge received message: `journalctl -u redis-sse-bridge | grep "📨 Message received"`
- Verify Redis Pub/Sub works: `redis-cli` → `SUBSCRIBE grist-realtime-interventions`
- Check widget SSE connection: browser console should show SSE messages

## File References

### Core Server Files
- SSE bridge server: `redis-sse-bridge.js:1-307` (complete implementation)
- Redis Pub/Sub listener: `redis-sse-bridge.js:83-91` (subscribes and broadcasts)
- SSE endpoint: `redis-sse-bridge.js:111-144` (/sse-stream handler)
- HTTP publish endpoint: `redis-sse-bridge.js:147-177` (called by n8n)
- HTTP setex endpoint: `redis-sse-bridge.js:180-211` (cache with TTL)
- Dependencies: `package.json:1-18` (express, redis, cors)

### Widget Files
- Widget implementation: `grist-realtime-dashboard-widget.html:520-562` (init function)
- SSE connection logic: `grist-realtime-dashboard-widget.html:591-630` (connectSSE)
- Grist columnar data parsing: `grist-realtime-dashboard-widget.html:370-395` (loadData)

### n8n Workflow Files
- Main workflow: `n8n-workflow-1-grist-to-sse-server.json:1-256` (HTTP-based architecture)
- Webhook node: `n8n-workflow-1-grist-to-sse-server.json:4-18` (receives Grist webhooks)
- HTTP Publish node: `n8n-workflow-1-grist-to-sse-server.json:48-61` (publishes to redis-sse-bridge)
- HTTP SETEX node: `n8n-workflow-1-grist-to-sse-server.json:63-76` (caches interventions)
- Workflow connections: `n8n-workflow-1-grist-to-sse-server.json:150-247` (node flow)
- Fallback API workflow: `n8n-workflow-2-api-interventions.json:1-197` (polling endpoint)

### Documentation Files
- Installation guide: `INSTALLATION-SSE-SERVER.md:1-462` (complete setup guide)
- n8n workflows guide: `WORKFLOWS-N8N-GUIDE.md:1-388` (import and configuration)
- GitHub Pages setup: `PROCEDURE-DEPLOIEMENT-GITHUB-PAGES.md` (deployment guide)

## Notes for Future Development

- **Build system**: Now uses Node.js with `package.json` (express, redis, cors)
- **Widget**: Single HTML file with embedded CSS and JavaScript (hosted on GitHub Pages)
- **SSE Bridge**: Standalone Node.js server (`redis-sse-bridge.js`) - CORE COMPONENT
- **n8n workflow**: Imported as JSON, uses HTTP requests (not Redis nodes)
- **Architecture limitation**: n8n Redis nodes don't support `subscribe` or `executeCommand`
- **Solution**: HTTP bridge pattern - n8n → HTTP POST → redis-sse-bridge → Redis Pub/Sub → SSE
- **Deployment**: Widget on GitHub Pages (static), server on VPS (systemd service)
- **All documentation in French** for CEREMA users
- **System designed for French government sovereign infrastructure** (Tchap, Albert API compatible)
- **No external dependencies**: Runs entirely on sovereign infrastructure (n8n, Redis, Nginx on VPS)
