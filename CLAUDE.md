# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Grist Realtime Broadcasting System** - A real-time synchronization system for Grist using n8n and Server-Sent Events (SSE). Developed by CEREMA Méditerranée for tracking field interventions.

### Core Purpose
When a field agent updates an intervention status in Grist, all connected supervisors see the update instantly (<500ms latency) without manual refresh. The system broadcasts changes via Redis Pub/Sub and SSE streams.

## Architecture

### Three-Layer System

```
Grist Table (Data Source)
    ↓ Webhook on add/update
n8n Workflow (Orchestrator)
    ↓ Redis Pub/Sub
SSE Stream (Real-time Push)
    ↓
Widget Dashboards (All connected clients)
```

### Data Flow
1. **Grist**: Agent modifies row → Automatic webhook fires
2. **n8n**: Receives webhook → Validates → Publishes to Redis channel
3. **Redis**: Broadcasts message to all SSE subscribers
4. **Widgets**: Receive update → Refresh UI with animation/notification
5. **Latency**: 300-500ms end-to-end

### Components

**grist-realtime-dashboard-widget.html** (1015 lines)
- Standalone HTML/JavaScript widget
- Connects to Grist API for initial data load
- Establishes SSE connection to n8n endpoint
- Real-time UI updates with visual/sound notifications
- Auto-reconnection on disconnect
- Filters: active/all/urgent interventions
- Stores SSE URL in localStorage for configuration

**grist-realtime-n8n-workflow.json** (448 lines)
- Production-ready n8n workflow with 3 webhooks:
  - `POST /webhook/grist-realtime` - Receives Grist webhooks
  - `GET /webhook/sse-stream` - SSE endpoint for widgets
  - `GET /webhook/health` - Health check endpoint
- Pipeline: Webhook → Validate → Prepare → Redis Publish → Cache → Metrics
- Urgent interventions trigger Tchap (Matrix) notifications
- Redis cache with 24h TTL
- CORS enabled for cross-origin requests

**install-grist-realtime.sh** (499 lines)
- Automated installation script for production deployment
- Installs and configures: Redis, Nginx
- Creates utility scripts: `grist-status`, `grist-test`, `grist-logs`
- System optimizations for Redis performance
- Sets up monitoring service (disabled by default)

## Key Technical Patterns

### SSE Connection Management
The widget implements robust reconnection logic:
- Exponential backoff on errors (5s delay)
- Visual indicators (green=connected, red=disconnected, orange=connecting)
- Fallback to periodic polling every 60s
- Connection state stored in DOM for UI updates

### Redis Pub/Sub Architecture
- **Channel**: `grist-realtime-interventions`
- **Publisher**: n8n workflow (after webhook validation)
- **Subscribers**: All SSE streams via n8n Redis Subscribe node
- **Cache**: Separate Redis SET commands with 24h TTL per intervention

### n8n Workflow Structure
The workflow has **4 main branches**:
1. **Grist Webhook Branch**: Validation → Prepare → Redis Publish → Response
2. **SSE Stream Branch**: Redis Subscribe → Format SSE → Send to client
3. **Urgent Notification Branch**: Filter → Tchap API call + Cache
4. **Health Check Branch**: Status response with system info

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
# Automated installation (requires root)
sudo ./install-grist-realtime.sh

# Manual Redis installation
sudo apt install redis-server
sudo systemctl enable redis-server
redis-cli ping  # Should return PONG

# Manual Nginx installation
sudo apt install nginx
sudo mkdir -p /var/www/grist-widgets
sudo cp grist-realtime-dashboard-widget.html /var/www/grist-widgets/
```

### Testing
```bash
# System status check
grist-status

# Run all tests
grist-test

# Test webhook endpoint
curl -X POST https://your-n8n.cerema.fr/webhook/grist-realtime \
  -H "Content-Type: application/json" \
  -d '{"id":"test123","fields":{"Agent":"Test","Statut":"En cours"}}'

# Test SSE stream
curl -N https://your-n8n.cerema.fr/webhook/sse-stream

# Health check
curl https://your-n8n.cerema.fr/webhook/health
```

### Monitoring
```bash
# View logs
grist-logs redis        # Redis logs
grist-logs nginx        # Nginx access logs
grist-logs nginx-error  # Nginx error logs

# Redis stats
redis-cli info stats
redis-cli info memory

# Check SSE connections
netstat -an | grep :80 | grep ESTABLISHED | wc -l
```

## Important Implementation Details

### Widget Loading Sequence
1. Check for SSE URL in localStorage
2. If missing → Show config panel for URL entry
3. Connect to Grist API with `requiredAccess: 'read table'`
4. Fetch initial data from selected table
5. Establish SSE connection to configured URL
6. Render dashboard with stats and interventions list
7. Set up periodic refresh fallback (60s interval)

### Redis Configuration for Production
From install script (lines 114-139):
- `bind 0.0.0.0` - Listen on all interfaces
- `maxmemory 256mb` - Memory limit
- `maxmemory-policy allkeys-lru` - Eviction policy
- `protected-mode yes` - Security enabled
- Save snapshots: 900s/1 change, 300s/10 changes, 60s/10000 changes

### Nginx CORS Configuration
Critical for Grist widget access (lines 188-191):
```nginx
add_header Access-Control-Allow-Origin * always;
add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS' always;
add_header Access-Control-Allow-Headers 'Content-Type' always;
```

### n8n Credentials Required
1. **Redis credential** (used in 4 nodes):
   - Type: Redis
   - Name: "Redis CEREMA"
   - Host: localhost
   - Port: 6379
   - Database: 0

2. **Tchap credential** (optional, for urgent notifications):
   - Type: HTTP Header Auth
   - Header: Authorization
   - Value: Bearer YOUR_TCHAP_TOKEN

### SSE Format Requirements
The n8n Format SSE node (lines 146-152) creates standard SSE messages:
```
event: message
id: 1700000000000
retry: 5000
data: {"timestamp":"...","type":"intervention_update",...}

```
Note: Double newline at end is required by SSE spec.

## Deployment Checklist

When deploying or modifying this system:

- [ ] Redis installed and `redis-cli ping` returns PONG
- [ ] Nginx configured with CORS headers for widgets
- [ ] Widget HTML copied to `/var/www/grist-widgets/`
- [ ] n8n workflow imported and activated
- [ ] Redis credentials configured in n8n
- [ ] Grist webhook created pointing to n8n URL
- [ ] Test webhook with curl (should return `{"success":true}`)
- [ ] Test SSE stream connection (should maintain connection)
- [ ] Widget loaded in Grist with correct SSE URL
- [ ] Live indicator shows green (connected)
- [ ] Test real update: modify row → see instant update in widget

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
- Check SSE URL is correct in widget config
- Verify n8n workflow is active
- Test SSE endpoint with `curl -N`
- Check CORS headers in n8n response
- Inspect browser console for detailed errors

### Webhook not triggering n8n
- Verify webhook URL in Grist settings
- Check n8n workflow is active (not inactive)
- Test with manual curl to webhook endpoint
- Check n8n execution history for errors
- Verify network connectivity Grist → n8n

### Redis connection refused
- Check Redis service: `systemctl status redis-server`
- Test connection: `redis-cli ping`
- Verify bind address in `/etc/redis/redis.conf`
- Check firewall rules for port 6379

## File References

- Widget implementation: `grist-realtime-dashboard-widget.html:520-562` (init function)
- SSE connection logic: `grist-realtime-dashboard-widget.html:591-630` (connectSSE)
- n8n workflow structure: `grist-realtime-n8n-workflow.json:288-415` (connections)
- Redis Pub/Sub nodes: `grist-realtime-n8n-workflow.json:47-63` (publish) and `grist-realtime-n8n-workflow.json:128-143` (subscribe)
- Installation script: `install-grist-realtime.sh:60-498` (main installation)
- Utility scripts creation: `install-grist-realtime.sh:283-400` (helper scripts)

## Notes for Future Development

- No build system or package.json - all files are standalone
- Widget is a single HTML file with embedded CSS and JavaScript
- n8n workflow is imported as JSON (no code repository)
- Bash script handles full system installation
- All documentation is in French for CEREMA users
- System designed for French government sovereign infrastructure (Tchap, Albert API compatible)
