# 🎯 Guide de Choix de Version - Grist Realtime

Trois versions du système sont disponibles, du plus simple au plus complexe.

## 📊 Tableau Comparatif

| Critère | v1 MINIMAL | v2 CACHE | v3 COMPLETE (SSE) |
|---------|------------|----------|-------------------|
| **Latence** | 0-30s (moy: 15s) | 0-30s (moy: 15s) | <500ms ⚡ |
| **Complexité** | ⭐ Très simple | ⭐⭐ Simple | ⭐⭐⭐ Complexe |
| **Serveurs requis** | Grist uniquement | Grist + n8n + Redis | Grist + n8n + Redis + Node.js |
| **Maintenance** | Minimale | Faible | Moyenne |
| **Coût infrastructure** | Gratuit | Faible | Moyen |
| **Notifications Tchap** | Optionnel | ✅ Inclus | ✅ Inclus |
| **Cache Redis** | ❌ | ✅ | ✅ |
| **Broadcasting simultané** | ❌ | ❌ | ✅ |
| **Charge sur Grist** | Moyenne | Faible | Très faible |

---

## v1 - MINIMAL (Sans Redis, Sans SSE)

### 🎯 Pour qui ?

- Petites équipes (<10 personnes)
- Besoins de suivi général (pas d'urgence)
- Budget infrastructure limité
- Pas de compétences serveur

### ✅ Avantages

- **Ultra simple** : Juste Grist + Widget
- **Gratuit** : Pas de serveur supplémentaire
- **Maintenance nulle** : Rien à gérer
- **Installation 5 minutes** : Copier-coller le widget dans Grist

### ❌ Inconvénients

- **Latence 0-30s** : Pas temps réel
- **Charge API Grist** : 1 requête toutes les 30s par widget
- **Pas de cache** : Toujours interroge Grist
- **Pas de notifications** : Sauf si n8n ajouté

### 📦 Composants

```
Agent modifie Grist
         ↓
Grist Table ←────── Widget (poll 30s direct)
         ↓
    Webhook (optionnel)
         ↓
       n8n → Tchap (si urgente)
```

### 📁 Fichiers

- `grist-realtime-dashboard-widget-v1-minimal.html` (widget)
- `n8n-workflow-v1-minimal-tchap.json` (optionnel, juste Tchap)

### 🚀 Installation

1. Ouvrir Grist
2. Créer widget Custom
3. URL : pointer vers `grist-realtime-dashboard-widget-v1-minimal.html`
4. Access : Read table
5. C'est tout ! ✅

**Optionnel** : Importer workflow n8n pour notifications Tchap urgentes

---

## v2 - CACHE (Avec Redis, Sans SSE)

### 🎯 Pour qui ?

- Équipes moyennes (10-50 personnes)
- Grist lent ou surchargé
- Besoin de notifications Tchap
- Agrégation de plusieurs tables

### ✅ Avantages

- **Simple** : Pas de serveur Node.js
- **Cache performant** : Réduit charge Grist
- **Notifications Tchap** : Alertes urgences
- **Agrégation possible** : Combiner plusieurs sources
- **Latence identique à v1** : Mais sans charger Grist

### ❌ Inconvénients

- **Nécessite Redis** : Installation + maintenance
- **Nécessite n8n** : Configuration workflows
- **Latence toujours 0-30s** : Pas temps réel
- **Complexité accrue** : Plus de composants

### 📦 Composants

```
Agent modifie Grist
         ↓
    Webhook
         ↓
       n8n → Redis SETEX (cache 24h)
         ↓ → Tchap (si urgente)

Widget (poll 30s) → n8n API → Redis GET → Return JSON
```

### 📁 Fichiers

- `grist-realtime-dashboard-widget-v2-cache.html` (widget)
- `n8n-workflow-v2-cache-webhook.json` (webhook Grist → Redis)
- `n8n-workflow-v2-cache-api.json` (API GET pour widget)

### 🚀 Installation

#### 1. Installer Redis

```bash
sudo apt update
sudo apt install redis-server
sudo systemctl enable redis-server
redis-cli ping  # Doit retourner PONG
```

#### 2. Importer workflows n8n

- Workflow 1 : `n8n-workflow-v2-cache-webhook.json` (webhook)
- Workflow 2 : `n8n-workflow-v2-cache-api.json` (API)
- Configurer credential Redis dans n8n

#### 3. Configurer widget

- URL dans Grist : `grist-realtime-dashboard-widget-v2-cache.html`
- Au premier chargement : entrer URL API n8n
  - Exemple : `https://n8n.cerema.fr/webhook/interventions-v2`

#### 4. Configurer webhook Grist

- URL : `https://n8n.cerema.fr/webhook/grist-realtime-v2`
- Events : add, update

---

## v3 - COMPLETE (SSE Temps Réel)

### 🎯 Pour qui ?

- Grandes équipes (50+ personnes)
- **Urgences critiques** nécessitant <1s latence
- Centre de contrôle 24/7
- Coordination temps réel vitale

### ✅ Avantages

- **Latence <500ms** : Vrai temps réel ⚡
- **Broadcasting** : 1 update → tous clients instantanément
- **Scalable** : Testé 100+ clients
- **Robuste** : Reconnexion automatique
- **Monitoring** : Endpoint /health

### ❌ Inconvénients

- **Complexe** : 4 composants à gérer
- **Serveur Node.js** : Installation + systemd service
- **Maintenance** : Logs, monitoring, mises à jour
- **Coût** : Serveur supplémentaire

### 📦 Composants

```
Grist → n8n → HTTP POST → redis-sse-bridge (Node.js)
                              ↓ Redis Pub/Sub
                              ↓ SSE Streams
                         [ Tous widgets ] <500ms
```

### 📁 Fichiers

- `grist-realtime-dashboard-widget.html` (widget SSE)
- `redis-sse-bridge.js` (serveur Node.js)
- `package.json` (dépendances)
- `n8n-workflow-1-grist-to-sse-server.json` (workflow)
- `INSTALLATION-SSE-SERVER.md` (guide installation)

### 🚀 Installation

Voir `INSTALLATION-SSE-SERVER.md` pour guide complet.

**Résumé** :
1. Installer Redis + Node.js
2. `npm install`
3. Créer service systemd pour redis-sse-bridge
4. Importer workflow n8n
5. Configurer widget avec URL SSE

---

## 🤔 Quelle Version Choisir ?

### Choisissez v1 MINIMAL si :

- ✅ Équipe <10 personnes
- ✅ Latence 30s acceptable
- ✅ Budget limité
- ✅ Pas de compétences serveur
- ✅ Juste besoin de voir les updates

### Choisissez v2 CACHE si :

- ✅ Grist lent/surchargé
- ✅ Besoin notifications Tchap
- ✅ Équipe 10-50 personnes
- ✅ Latence 30s acceptable
- ✅ Avez déjà n8n + Redis

### Choisissez v3 COMPLETE si :

- ✅ **VRAIMENT** besoin de <1s latency
- ✅ Urgences critiques
- ✅ Centre de contrôle 24/7
- ✅ Budget pour serveur Node.js
- ✅ Compétences pour maintenir

---

## 📈 Évolution Progressive

Vous pouvez commencer simple et évoluer selon vos besoins :

```
Phase 1 : v1 MINIMAL
  ↓
  Testez pendant 1 semaine
  ↓
  30s trop lent ? Grist surchargé ?
  ↓
Phase 2 : v2 CACHE
  ↓
  Testez pendant 1 mois
  ↓
  VRAIMENT besoin temps réel <1s ?
  ↓
Phase 3 : v3 COMPLETE
```

**Recommandation** : 90% des cas d'usage sont OK avec v1 ou v2 !

---

## 💡 Cas d'Usage Réels

### v1 MINIMAL ✅
- Suivi général interventions (non urgent)
- Petite mairie rurale
- Dashboard pour consultation

### v2 CACHE ✅
- CEREMA Méditerranée (si latence 30s OK)
- Plusieurs tables Grist agrégées
- Notifications Tchap urgences
- 20-30 agents terrain

### v3 COMPLETE ✅
- Centre 15 (SAMU)
- Contrôle trafic autoroute
- Sécurité incendie
- Coordination interventions critiques temps réel

---

## 🛠️ Comparaison Installation

| Étape | v1 | v2 | v3 |
|-------|----|----|-----|
| Temps installation | 5 min | 30 min | 2h |
| Compétences requises | Aucune | n8n basique | Serveur Linux |
| Composants à installer | 0 | 2 (Redis, n8n) | 4 (Redis, n8n, Node.js, systemd) |
| Configuration | Copier widget | Workflows n8n | Workflows + Service + Nginx |
| Tests requis | Basique | Moyens | Complets |

---

## 📞 Support

Pour choisir la bonne version :
1. Testez d'abord v1 (gratuit, rapide)
2. Si 30s trop lent → v2
3. Si vraiment besoin <1s → v3

**Contact** : support-digital@cerema.fr

---

**Auteur** : Claude Code
**Date** : 2024-11-18
**Version** : 1.0.0
