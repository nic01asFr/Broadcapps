# 📦 Grist Realtime - Toutes les Versions

Ce repository contient **3 versions** du système de synchronisation temps réel pour Grist, chacune adaptée à des besoins différents.

---

## 🎯 Choix Rapide

| Besoin | Version Recommandée | Latence | Complexité |
|--------|---------------------|---------|------------|
| Suivi général, petite équipe | **v1 MINIMAL** | 0-30s | ⭐ Simple |
| Cache performance, notifications | **v2 CACHE** | 0-30s | ⭐⭐ Moyen |
| Urgences critiques temps réel | **v3 COMPLETE** | <500ms | ⭐⭐⭐ Complexe |

**📖 Guide détaillé** : [`GUIDE-CHOIX-VERSION.md`](GUIDE-CHOIX-VERSION.md)

---

## v1 - MINIMAL (Sans Redis, Sans SSE)

### Architecture
```
Grist ←──── Widget (polling 30s)
  ↓
n8n (optionnel, Tchap)
```

### Fichiers
- 🎨 `grist-realtime-dashboard-widget-v1-minimal.html`
- ⚙️ `n8n-workflow-v1-minimal-tchap.json` (optionnel)

### Installation
```bash
# Aucune installation ! Juste charger le widget dans Grist
```

**Avantages** : Ultra simple, gratuit, 0 serveur
**Inconvénient** : Latence 0-30s

---

## v2 - CACHE (Avec Redis, Sans SSE)

### Architecture
```
Grist → n8n → Redis (cache)
              ↑
Widget ───────┘ (polling 30s)
```

### Fichiers
- 🎨 `grist-realtime-dashboard-widget-v2-cache.html`
- ⚙️ `n8n-workflow-v2-cache-webhook.json` (webhook)
- ⚙️ `n8n-workflow-v2-cache-api.json` (API)

### Installation
```bash
# 1. Redis
sudo apt install redis-server

# 2. Importer workflows dans n8n

# 3. Charger widget, configurer URL API
```

**Avantages** : Cache, notifications, agrégation
**Inconvénient** : Nécessite Redis + n8n

---

## v3 - COMPLETE (SSE Temps Réel)

### Architecture
```
Grist → n8n → redis-sse-bridge (Node.js)
                    ↓ SSE
              [ Widgets ] <500ms
```

### Fichiers
- 🎨 `grist-realtime-dashboard-widget.html`
- 🔧 `redis-sse-bridge.js`
- 📦 `package.json`
- ⚙️ `n8n-workflow-1-grist-to-sse-server.json`
- 📖 `INSTALLATION-SSE-SERVER.md`

### Installation
```bash
# 1. Redis + Node.js
sudo apt install redis-server nodejs

# 2. Clone + install
git clone https://github.com/nic01asFr/Broadcapps.git
cd Broadcapps
npm install

# 3. Service systemd
sudo systemctl enable redis-sse-bridge
sudo systemctl start redis-sse-bridge

# 4. Workflows n8n + widget
```

**Avantages** : <500ms latence, broadcasting, robuste
**Inconvénient** : 4 composants à gérer

---

## 📊 Comparaison Complète

| Critère | v1 | v2 | v3 |
|---------|----|----|-----|
| **Latence** | 0-30s | 0-30s | <500ms |
| **Serveurs** | 0 | 2 | 4 |
| **Installation** | 5 min | 30 min | 2h |
| **Coût** | Gratuit | Faible | Moyen |
| **Broadcasting** | ❌ | ❌ | ✅ |
| **Cache Redis** | ❌ | ✅ | ✅ |
| **Notifications Tchap** | ⚠️ | ✅ | ✅ |
| **Scalabilité** | 10 users | 50 users | 100+ users |

---

## 🚀 Démarrage Rapide

### 1. Pour tester rapidement (5 min)
```bash
# Utilisez v1 MINIMAL
# Chargez juste grist-realtime-dashboard-widget-v1-minimal.html dans Grist
```

### 2. Pour production avec cache (30 min)
```bash
# Utilisez v2 CACHE
# Installez Redis + n8n
# Importez les 2 workflows
```

### 3. Pour temps réel critique (2h)
```bash
# Utilisez v3 COMPLETE
# Suivez INSTALLATION-SSE-SERVER.md
```

---

## 📚 Documentation

- 📖 **Guide de choix** : [`GUIDE-CHOIX-VERSION.md`](GUIDE-CHOIX-VERSION.md)
- 🏗️ **Architecture v3** : [`README.md`](README.md)
- 🛠️ **Installation SSE** : [`INSTALLATION-SSE-SERVER.md`](INSTALLATION-SSE-SERVER.md)
- 🔄 **Migration v1→v2** : [`MIGRATION-V1-TO-V2.md`](MIGRATION-V1-TO-V2.md)
- 💻 **Guide Claude** : [`CLAUDE.md`](CLAUDE.md)

---

## 🧪 Tests

### Test v1
```bash
# Ouvrir widget dans Grist
# Modifier une ligne
# Attendre max 30s → update visible
```

### Test v2
```bash
# 1. Tester API
curl https://n8n.cerema.fr/webhook/interventions-v2

# 2. Tester webhook
curl -X POST https://n8n.cerema.fr/webhook/grist-realtime-v2 \
  -d '{"id":"test","fields":{"Agent":"Test"}}'

# 3. Ouvrir widget, vérifier polling
```

### Test v3
```bash
# 1. Health check
curl http://localhost:3001/health

# 2. SSE stream
curl -N http://localhost:3001/sse-stream

# 3. Test complet end-to-end
```

---

## 💡 Recommandations

### Débutants → v1 MINIMAL
- Pas de serveur
- Installation immédiate
- Testez si 30s latence OK

### Équipes moyennes → v2 CACHE
- Cache améliore performances
- Notifications Tchap incluses
- Pas de serveur Node.js

### Centres critiques → v3 COMPLETE
- <500ms requis
- Broadcasting robuste
- Infrastructure complète

---

## 🔄 Migration

Vous pouvez évoluer progressivement :

```
v1 → v2 : Ajouter Redis + n8n (workflows différents)
v2 → v3 : Ajouter redis-sse-bridge.js
v3 → v2 : Arrêter redis-sse-bridge, utiliser polling
```

Pas de perte de données, juste changement de widget et workflows.

---

## 📞 Support

- 📧 Email : support-digital@cerema.fr
- 🐛 Issues : GitHub Issues
- 💬 Tchap : #grist-realtime

---

## 📅 Versions

- **v1.0.0** (2024-11-17) : Version initiale (tentative SSE dans n8n)
- **v2.0.0** (2024-11-18) : redis-sse-bridge.js + 3 versions du système

---

## 🌟 Contribuer

Les contributions sont bienvenues !

1. Fork le projet
2. Créer une branche feature
3. Commit les changements
4. Push et créer Pull Request

---

**Développé par** : CEREMA Méditerranée - Groupe Ingénierie de la Donnée et Innovations
**Licence** : Open Source
**Année** : 2024
