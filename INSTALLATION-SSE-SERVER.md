# 🚀 Installation du Serveur SSE Redis Bridge

## Vue d'ensemble

Le serveur `redis-sse-bridge.js` fait le pont entre n8n, Redis et les widgets :
- Reçoit les commandes Redis de n8n via HTTP
- Écoute Redis Pub/Sub
- Maintient les connexions SSE vers les widgets
- Broadcast en temps réel (<500ms)

---

## 📋 Prérequis

**Sur votre VPS** :
- ✅ Redis installé et opérationnel
- ✅ n8n installé et opérationnel
- ✅ Node.js ≥ 18.0.0

**Vérifier Node.js** :
```bash
node --version
# Doit afficher v18.x.x ou plus
```

**Si Node.js n'est pas installé** :
```bash
# Ubuntu/Debian
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Vérifier
node --version
npm --version
```

---

## 🔧 Installation

### Étape 1 : Cloner le Repository

```bash
# Se connecter au VPS
ssh votre-utilisateur@votre-vps.cerema.fr

# Cloner le projet
cd /opt  # ou /home/votre-user
git clone https://github.com/nic01asFr/Broadcapps.git
cd Broadcapps
```

### Étape 2 : Installer les Dépendances

```bash
npm install
```

**Dépendances installées** :
- `express` : Serveur HTTP
- `redis` : Client Redis
- `cors` : CORS headers

### Étape 3 : Configuration

**Variables d'environnement** (optionnel) :

```bash
# Créer un fichier .env
cat > .env << 'EOF'
PORT=3001
REDIS_HOST=localhost
REDIS_PORT=6379
NODE_ENV=production
EOF
```

**Par défaut** (si pas de .env) :
- Port : 3001
- Redis : localhost:6379

### Étape 4 : Test Manuel

```bash
# Lancer le serveur
node redis-sse-bridge.js
```

**Sortie attendue** :
```
✅ Connected to Redis
👂 Listening on Redis channel: grist-realtime-interventions
🚀 ======================================
🚀 Redis SSE Bridge Started!
🚀 ======================================

📡 SSE endpoint:     http://localhost:3001/sse-stream
📤 Publish endpoint: POST http://localhost:3001/redis/publish
💾 SetEx endpoint:   POST http://localhost:3001/redis/setex
❤️  Health endpoint:  http://localhost:3001/health

👂 Redis channel:    grist-realtime-interventions
🔌 Connected clients: 0
```

**Tester** (depuis un autre terminal) :
```bash
# Health check
curl http://localhost:3001/health

# Devrait retourner :
# {"status":"healthy","uptime":5.2,"clients":0,"redis":"connected","timestamp":"..."}
```

**Arrêter** : `Ctrl+C`

---

## 🚦 Installation comme Service systemd

Pour que le serveur démarre automatiquement au boot :

### Créer le service

```bash
sudo nano /etc/systemd/system/redis-sse-bridge.service
```

**Contenu** :
```ini
[Unit]
Description=Redis SSE Bridge for Grist Realtime
After=network.target redis-server.service
Requires=redis-server.service

[Service]
Type=simple
User=www-data
WorkingDirectory=/opt/Broadcapps
ExecStart=/usr/bin/node redis-sse-bridge.js
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=redis-sse-bridge

# Variables d'environnement
Environment=NODE_ENV=production
Environment=PORT=3001
Environment=REDIS_HOST=localhost
Environment=REDIS_PORT=6379

[Install]
WantedBy=multi-user.target
```

**Activer et démarrer** :
```bash
sudo systemctl daemon-reload
sudo systemctl enable redis-sse-bridge
sudo systemctl start redis-sse-bridge
```

**Vérifier le statut** :
```bash
sudo systemctl status redis-sse-bridge

# Devrait afficher : Active: active (running)
```

**Voir les logs** :
```bash
# Logs en temps réel
sudo journalctl -u redis-sse-bridge -f

# Dernières 100 lignes
sudo journalctl -u redis-sse-bridge -n 100
```

---

## 🔒 Configuration Nginx (Reverse Proxy)

Si vous utilisez Nginx, ajoutez un proxy pour exposer le serveur :

```bash
sudo nano /etc/nginx/sites-available/grist-realtime
```

**Ajouter** :
```nginx
# SSE Bridge proxy
location /sse-stream {
    proxy_pass http://localhost:3001/sse-stream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection 'keep-alive';
    proxy_set_header Host $host;
    proxy_cache_bypass $http_upgrade;

    # Headers SSE
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_buffering off;
    proxy_cache off;

    # Timeouts longs pour SSE
    proxy_connect_timeout 1h;
    proxy_send_timeout 1h;
    proxy_read_timeout 1h;
}

# API endpoints
location /redis/ {
    proxy_pass http://localhost:3001/redis/;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}

# Health check
location /sse-health {
    proxy_pass http://localhost:3001/health;
    proxy_http_version 1.1;
}
```

**Recharger Nginx** :
```bash
sudo nginx -t
sudo systemctl reload nginx
```

**Les endpoints seront accessibles via** :
- `https://votre-domaine.cerema.fr/sse-stream`
- `https://votre-domaine.cerema.fr/redis/publish`
- `https://votre-domaine.cerema.fr/sse-health`

---

## 🧪 Tests Complets

### Test 1 : Health Check

```bash
curl http://localhost:3001/health
```

**Attendu** :
```json
{
  "status": "healthy",
  "uptime": 123.45,
  "clients": 0,
  "redis": "connected",
  "timestamp": "2024-11-17T..."
}
```

### Test 2 : Connexion SSE

```bash
curl -N http://localhost:3001/sse-stream
```

**Attendu** : Connexion maintenue + heartbeats toutes les 30s
```
data: {"type":"connected","timestamp":"...","message":"Connexion SSE établie"}

: heartbeat

: heartbeat
```

### Test 3 : Publish (simuler n8n)

```bash
curl -X POST http://localhost:3001/redis/publish \
  -H "Content-Type: application/json" \
  -d '{
    "channel": "grist-realtime-interventions",
    "message": {
      "type": "test",
      "data": {"id": "test-123", "agent": "Test"}
    }
  }'
```

**Attendu** :
```json
{
  "success": true,
  "channel": "grist-realtime-interventions",
  "timestamp": "..."
}
```

**Et dans le terminal SSE** (Test 2), vous devriez voir :
```
data: {"type":"test","data":{"id":"test-123","agent":"Test"}}
```

### Test 4 : SETEX (cache)

```bash
curl -X POST http://localhost:3001/redis/setex \
  -H "Content-Type: application/json" \
  -d '{
    "key": "intervention:test-123",
    "value": {"id": "test-123", "agent": "Test"},
    "ttl": 86400
  }'
```

**Vérifier dans Redis** :
```bash
redis-cli GET intervention:test-123
# Devrait retourner : "{\"id\":\"test-123\",\"agent\":\"Test\"}"

redis-cli TTL intervention:test-123
# Devrait retourner : ~86400 (décrémente chaque seconde)
```

---

## 🐛 Dépannage

### Erreur : "Cannot find module 'express'"

```bash
cd /opt/Broadcapps
npm install
```

### Erreur : "Redis connection refused"

```bash
# Vérifier Redis
systemctl status redis-server
redis-cli ping

# Si arrêté
sudo systemctl start redis-server
```

### Service ne démarre pas

```bash
# Voir les logs d'erreur
sudo journalctl -u redis-sse-bridge -n 50

# Vérifier les permissions
sudo chown -R www-data:www-data /opt/Broadcapps
```

### Port 3001 déjà utilisé

```bash
# Trouver le processus
sudo lsof -i :3001

# Changer le port dans .env ou systemd service
PORT=3002
```

### Clients SSE ne reçoivent pas les messages

```bash
# Vérifier que Redis Pub/Sub fonctionne
# Terminal 1
redis-cli
SUBSCRIBE grist-realtime-interventions

# Terminal 2
redis-cli
PUBLISH grist-realtime-interventions "test message"

# Terminal 1 devrait afficher le message
```

---

## 📊 Monitoring

### Nombre de clients connectés

```bash
curl http://localhost:3001/health | jq '.clients'
```

### Métriques système

```bash
# CPU et mémoire
ps aux | grep redis-sse-bridge

# Connexions réseau
netstat -an | grep 3001
```

### Logs applicatifs

```bash
# Logs en continu
sudo journalctl -u redis-sse-bridge -f

# Filtrer les erreurs
sudo journalctl -u redis-sse-bridge | grep "❌"

# Statistiques aujourd'hui
sudo journalctl -u redis-sse-bridge --since today
```

---

## 🔄 Mise à Jour

```bash
cd /opt/Broadcapps
git pull origin main
npm install
sudo systemctl restart redis-sse-bridge
```

---

## ✅ Checklist Post-Installation

- [ ] Node.js ≥ 18 installé
- [ ] Repository cloné
- [ ] `npm install` réussi
- [ ] Test manuel fonctionne
- [ ] Service systemd créé et activé
- [ ] Service démarré (`systemctl status` = active)
- [ ] Health check retourne "healthy"
- [ ] Test SSE maintient la connexion
- [ ] Test Publish fonctionne
- [ ] Logs accessibles (`journalctl`)
- [ ] (Optionnel) Nginx configuré
- [ ] Firewall configuré si nécessaire

---

## 🎯 Prochaines Étapes

Une fois le serveur SSE installé et opérationnel :

1. **Importer les workflows n8n modifiés**
   - Utilisent HTTP requests vers ce serveur
   - Pas de nodes Redis standards

2. **Configurer le widget**
   - URL SSE : `https://votre-domaine.cerema.fr/sse-stream`
   - Ou : `http://votre-vps-ip:3001/sse-stream`

3. **Configurer le webhook Grist**
   - Pointe vers n8n qui pointe vers ce serveur

---

**Le serveur est maintenant prêt à recevoir les messages de n8n et à les broadcaster en temps réel vers tous les widgets connectés ! 🚀**
