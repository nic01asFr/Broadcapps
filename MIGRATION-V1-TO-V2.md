# 🔄 Migration Guide: v1.0 → v2.0

## Vue d'ensemble

La **version 2.0** introduit une architecture fondamentalement différente pour contourner les limitations des nodes Redis de n8n.

### Problème v1.0

Les workflows n8n v1.0 utilisaient directement les nodes Redis de n8n :
- ❌ Le node "Redis" ne supporte **pas** l'opération `subscribe`
- ❌ Le node "Redis" ne supporte **pas** `executeCommand`
- ❌ Impossible de maintenir des connexions SSE longue durée dans n8n
- ❌ Pas de vrai broadcasting temps réel

**Opérations disponibles** : Delete, Get, Increment, Info, Keys, Pop, **Publish**, Push, Set

### Solution v2.0

Introduction d'un **serveur Node.js intermédiaire** (redis-sse-bridge.js) :
- ✅ Reçoit HTTP POST de n8n pour publier
- ✅ Gère Redis Pub/Sub nativement (subscribe + publish)
- ✅ Maintient connexions SSE longue durée vers widgets
- ✅ Broadcast en temps réel (<500ms)

---

## Différences Architecture

### v1.0 (Tentative)

```
Grist → n8n → [Redis nodes] → ❌ Pas de SSE broadcast possible
```

### v2.0 (Production)

```
Grist → n8n → HTTP POST → redis-sse-bridge → Redis Pub/Sub → SSE → Widgets
```

---

## Étapes de Migration

### Prérequis

- Serveur avec Ubuntu/Debian
- Redis déjà installé
- n8n déjà installé
- Node.js ≥18.0.0

### 1. Installer Node.js 18+ (si nécessaire)

```bash
node --version  # Vérifier version actuelle

# Si < 18.0.0 :
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

node --version  # Doit afficher v18.x.x ou v20.x.x
```

### 2. Cloner/Mettre à jour le repository

```bash
# Si déjà cloné :
cd /opt/Broadcapps
git pull origin main

# Si nouveau :
cd /opt
git clone https://github.com/nic01asFr/Broadcapps.git
cd Broadcapps
```

### 3. Installer les dépendances Node.js

```bash
npm install
```

**Dépendances installées** :
- `express@4.18.2` : Serveur HTTP
- `redis@4.6.12` : Client Redis avec support Pub/Sub
- `cors@2.8.5` : Headers CORS

### 4. Créer le service systemd

```bash
sudo nano /etc/systemd/system/redis-sse-bridge.service
```

**Contenu** (adapter le chemin et l'utilisateur) :

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

Environment=NODE_ENV=production
Environment=PORT=3001
Environment=REDIS_HOST=localhost
Environment=REDIS_PORT=6379

[Install]
WantedBy=multi-user.target
```

### 5. Activer et démarrer le service

```bash
sudo systemctl daemon-reload
sudo systemctl enable redis-sse-bridge
sudo systemctl start redis-sse-bridge
sudo systemctl status redis-sse-bridge
```

**Sortie attendue** :
```
● redis-sse-bridge.service - Redis SSE Bridge for Grist Realtime
     Loaded: loaded (/etc/systemd/system/redis-sse-bridge.service; enabled)
     Active: active (running) since...
```

### 6. Tester le serveur SSE

```bash
# Health check
curl http://localhost:3001/health

# Attendu :
# {"status":"healthy","uptime":5.2,"clients":0,"redis":"connected",...}

# Test SSE stream
curl -N http://localhost:3001/sse-stream

# Attendu : Connexion maintenue + heartbeats
```

### 7. Supprimer l'ancien workflow n8n

Dans n8n :
1. Allez dans **Workflows**
2. Ouvrez l'ancien workflow (s'il existe)
3. **Delete** ou **Disable**

### 8. Importer le nouveau workflow v2.0

1. Dans n8n : **Workflows** → **Import from File**
2. Sélectionnez : `n8n-workflow-1-grist-to-sse-server.json`
3. Cliquez : **Import**
4. **Activez** le workflow (toggle en haut à droite)

### 9. Vérifier les credentials n8n

**Nouveau** : Aucun credential Redis n'est nécessaire dans n8n !

**Optionnel** : Credential Tchap (si notifications urgentes) :
- Type : HTTP Header Auth
- Name : "Tchap Token"
- Header : `Authorization`
- Value : `Bearer YOUR_TOKEN`

### 10. Mettre à jour le webhook Grist

**Aucun changement** : L'URL webhook reste la même
```
https://votre-n8n.cerema.fr/webhook/grist-realtime
```

### 11. Reconfigurer le widget

**Nouvelle URL SSE** à entrer dans le widget :

**Option A** : Direct (HTTP)
```
http://votre-server:3001/sse-stream
```

**Option B** : Via Nginx (HTTPS recommandé)
```
https://votre-domaine.cerema.fr/sse-stream
```

**Configuration Nginx** (si option B) :

```bash
sudo nano /etc/nginx/sites-available/grist-realtime
```

Ajouter :
```nginx
location /sse-stream {
    proxy_pass http://localhost:3001/sse-stream;
    proxy_http_version 1.1;
    proxy_set_header Connection 'keep-alive';
    proxy_set_header Host $host;
    proxy_cache_bypass $http_upgrade;

    # SSE-specific
    proxy_buffering off;
    proxy_cache off;

    # Timeouts longs
    proxy_connect_timeout 1h;
    proxy_send_timeout 1h;
    proxy_read_timeout 1h;

    # CORS
    add_header Access-Control-Allow-Origin * always;
}

location /redis/ {
    proxy_pass http://localhost:3001/redis/;
    add_header Access-Control-Allow-Origin * always;
}
```

```bash
sudo nginx -t
sudo systemctl reload nginx
```

### 12. Test complet

#### Test 1 : Webhook → n8n → SSE bridge

```bash
curl -X POST https://votre-n8n.cerema.fr/webhook/grist-realtime \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-123",
    "fields": {
      "Agent": "Test Migration",
      "Localisation": "Marseille",
      "Type": "Voirie",
      "Statut": "En cours",
      "Priorite": "Normale"
    }
  }'
```

**Attendu** :
```json
{"success":true,"message":"Broadcast envoyé avec succès",...}
```

#### Test 2 : Vérifier logs SSE bridge

```bash
sudo journalctl -u redis-sse-bridge -f
```

**Attendu** :
```
📤 Published to grist-realtime-interventions: {"timestamp":...}
📨 Message received on grist-realtime-interventions: {"timestamp":...}
📡 Broadcasting to 0 clients: data: {...}
```

#### Test 3 : Widget

1. Ouvrez le widget dans Grist
2. Configurez l'URL SSE (si première fois)
3. Vérifiez : Indicateur **LIVE** vert 🟢
4. Ajoutez une ligne dans Grist
5. Observez : Mise à jour instantanée

---

## Comparaison Workflows

### Workflow v1.0 (obsolète)

**Nodes** :
1. Webhook Grist
2. Validation
3. **Redis Publish** ← Node Redis n8n (limité)
4. **Redis Set** ← Node Redis n8n (limité)
5. ❌ Pas de SSE stream possible

### Workflow v2.0 (production)

**Nodes** :
1. Webhook Grist
2. Validation
3. Préparer Message
4. **HTTP Request** → POST `/redis/publish` ← redis-sse-bridge
5. **HTTP Request** → POST `/redis/setex` ← redis-sse-bridge
6. Filtre Urgentes
7. Notification Tchap (optionnel)

---

## Avantages v2.0

| Aspect | v1.0 | v2.0 |
|--------|------|------|
| **Redis Subscribe** | ❌ Non supporté | ✅ Natif dans bridge |
| **SSE Long-polling** | ❌ Impossible | ✅ Maintenu par bridge |
| **Broadcasting** | ❌ Pas de broadcast | ✅ Tous clients simultanés |
| **Latence** | - | ✅ <500ms |
| **Scalabilité** | ❌ Limitée | ✅ 100+ clients |
| **Credentials n8n** | Redis requis | ✅ Aucun (HTTP) |
| **Monitoring** | Limité | ✅ Endpoint /health |

---

## Dépannage Migration

### Erreur : "Cannot find module 'express'"

```bash
cd /opt/Broadcapps
npm install
```

### Erreur : "Redis connection refused"

```bash
# Vérifier Redis
sudo systemctl status redis-server
redis-cli ping  # Doit retourner PONG

# Redémarrer si nécessaire
sudo systemctl restart redis-server
```

### Erreur : Service ne démarre pas

```bash
# Voir logs d'erreur
sudo journalctl -u redis-sse-bridge -n 50

# Vérifier permissions
sudo chown -R www-data:www-data /opt/Broadcapps

# Vérifier Node.js
node --version  # Doit être ≥18.0.0
```

### Widget ne se connecte plus

**Vérifier l'URL SSE** :
- Avant (v1.0) : `https://n8n.../webhook/sse-stream` ← NE FONCTIONNE PLUS
- Après (v2.0) : `http://server:3001/sse-stream` ou `https://domain/sse-stream` (Nginx)

**Tester** :
```bash
curl -N http://localhost:3001/sse-stream
# Doit maintenir connexion
```

---

## Checklist Post-Migration

- [ ] Node.js ≥18 installé
- [ ] `npm install` réussi
- [ ] Service redis-sse-bridge actif
- [ ] Health check retourne "healthy"
- [ ] Nouveau workflow n8n importé et activé
- [ ] Ancien workflow n8n supprimé/désactivé
- [ ] Widget reconfiguré avec nouvelle URL SSE
- [ ] Test webhook manuel réussi
- [ ] Test flux complet Grist → Widget fonctionne
- [ ] Indicateur LIVE vert dans widget

---

## Rollback (si nécessaire)

Si la migration échoue, vous pouvez revenir à v1.0 :

```bash
# Arrêter le service SSE bridge
sudo systemctl stop redis-sse-bridge
sudo systemctl disable redis-sse-bridge

# Réactiver l'ancien workflow n8n (si conservé)
# Dans n8n : Workflows → Ancien workflow → Active

# Restaurer l'ancienne URL SSE dans widget
# (Bien que cela ne fonctionnait pas vraiment en v1.0)
```

**Note** : v1.0 n'était pas pleinement fonctionnel, il est recommandé de continuer le debugging v2.0 plutôt que de rollback.

---

## Support

Pour toute question sur la migration :

- 📖 **Documentation complète** : `INSTALLATION-SSE-SERVER.md`
- 📖 **Guide workflows** : `WORKFLOWS-N8N-GUIDE.md`
- 🐛 **Issues** : GitHub Issues
- 📧 **Email** : support-digital@cerema.fr

---

**Version du guide** : 2.0.0
**Date** : 2024-11-18
**Auteur** : Claude Code
