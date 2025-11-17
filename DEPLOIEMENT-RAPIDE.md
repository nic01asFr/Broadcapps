# 🚀 Déploiement Rapide - Dashboard Temps Réel Grist

## 📋 Prérequis

- ✅ Instance n8n accessible (https://votre-n8n.cerema.fr)
- ✅ Redis installé (pour Pub/Sub)
- ✅ Base Grist avec table Interventions
- ✅ (Optionnel) Token Tchap pour notifications

---

## ⚡ Installation Express (15 minutes)

### ÉTAPE 1 : Configuration Redis (5 min)

**Installation Redis (si pas déjà fait)** :
```bash
# Debian/Ubuntu
sudo apt update
sudo apt install redis-server -y
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Test connexion
redis-cli ping
# Devrait retourner: PONG
```

**Configuration Redis pour n8n** :
```bash
# Éditer config Redis
sudo nano /etc/redis/redis.conf

# Ajouter/modifier :
bind 0.0.0.0
protected-mode no
maxmemory 256mb
maxmemory-policy allkeys-lru

# Redémarrer
sudo systemctl restart redis-server
```

---

### ÉTAPE 2 : Import Workflow n8n (3 min)

1. **Connectez-vous à n8n** : https://votre-n8n.cerema.fr

2. **Créez credentials Redis** :
   - Menu : Credentials → New
   - Type : Redis
   - Nom : `Redis CEREMA`
   - Host : `localhost` (ou IP Redis)
   - Port : `6379`
   - Database : `0`
   - Save

3. **Importez le workflow** :
   - Menu : Workflows → Import from File
   - Sélectionnez : `grist-realtime-n8n-workflow.json`
   - Cliquez : Import

4. **Activez le workflow** :
   - Ouvrez le workflow importé
   - Bouton en haut à droite : `Inactive` → `Active`

5. **Notez les URLs des webhooks** :
   - Webhook Grist : `https://votre-n8n.cerema.fr/webhook/grist-realtime`
   - SSE Stream : `https://votre-n8n.cerema.fr/webhook/sse-stream`
   - Health Check : `https://votre-n8n.cerema.fr/webhook/health`

---

### ÉTAPE 3 : Configuration Grist (5 min)

#### 3.1 Structure de table

**Créez/vérifiez la table `Interventions`** avec colonnes :

| Nom colonne | Type | Options |
|-------------|------|---------|
| ID | Texte | - |
| Agent | Texte | - |
| Localisation | Texte | - |
| Type | Choix | Voirie, Signalisation, Bâtiment, Autre |
| Statut | Choix | En attente, En cours, Terminé, Bloqué |
| Priorite | Choix | Basse, Normale, Haute, Urgente |
| Derniere_MAJ | Date/Heure | Formule: `NOW()` |
| Commentaire | Texte | - |

#### 3.2 Webhook Grist

1. **Accédez aux paramètres du document** : Menu ⚙️ → Document Settings

2. **Ajoutez un webhook** :
   - Onglet : Webhooks
   - Bouton : + Add Webhook
   
3. **Configuration** :
   ```
   Nom: Broadcast Interventions Temps Réel
   URL: https://votre-n8n.cerema.fr/webhook/grist-realtime
   Types d'événements: ✓ add, ✓ update
   Table: Interventions
   Activé: ✓
   ```

4. **Testez le webhook** :
   - Ajoutez une ligne test dans Interventions
   - Vérifiez dans n8n : Executions → Devrait voir une exécution réussie

---

### ÉTAPE 4 : Installation Widget (2 min)

#### 4.1 Hébergement du widget

**Option A : Hébergement local (recommandé production)**
```bash
# Créer répertoire web
sudo mkdir -p /var/www/grist-widgets
sudo chown -R www-data:www-data /var/www/grist-widgets

# Copier le fichier widget
sudo cp grist-realtime-dashboard-widget.html /var/www/grist-widgets/

# Configuration nginx
sudo nano /etc/nginx/sites-available/grist-widgets
```

**Config nginx** :
```nginx
server {
    listen 80;
    server_name widgets.cerema.fr;
    
    root /var/www/grist-widgets;
    index index.html;
    
    location / {
        try_files $uri $uri/ =404;
        add_header Access-Control-Allow-Origin *;
    }
}
```

```bash
# Activer site
sudo ln -s /etc/nginx/sites-available/grist-widgets /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl reload nginx
```

**Option B : Hébergement rapide (test/dev)**

Utilisez GitHub Pages ou Netlify :
1. Push `grist-realtime-dashboard-widget.html` sur repo GitHub
2. Activez GitHub Pages
3. URL disponible en 1 min

#### 4.2 Ajout du widget dans Grist

1. **Créez une nouvelle page** : + Add New → Page

2. **Ajoutez le widget** :
   - Add New → Custom Widget
   - Access Level : `Read table`
   - Widget URL : `https://widgets.cerema.fr/grist-realtime-dashboard-widget.html`
   - (ou l'URL GitHub Pages)

3. **Configuration initiale** :
   - Au premier chargement, le widget affiche un panneau config
   - Entrez l'URL SSE : `https://votre-n8n.cerema.fr/webhook/sse-stream`
   - Cliquez : Enregistrer et connecter

4. **Liez à la table** :
   - Widget Options → Select Data → `Interventions`
   - Save

---

## ✅ Tests de Validation

### Test 1 : Webhook Grist → n8n

```bash
# Test manuel avec curl
curl -X POST https://votre-n8n.cerema.fr/webhook/grist-realtime \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-123",
    "fields": {
      "Agent": "Test Agent",
      "Localisation": "Marseille Test",
      "Type": "Voirie",
      "Statut": "En cours",
      "Priorite": "Haute",
      "Commentaire": "Test webhook"
    }
  }'

# Réponse attendue :
# {"success":true,"message":"Broadcast envoyé avec succès",...}
```

### Test 2 : Connexion SSE

```bash
# Test connexion SSE
curl -N https://votre-n8n.cerema.fr/webhook/sse-stream

# Devrait rester connecté et afficher :
# event: message
# id: ...
# data: {...}
```

### Test 3 : Health Check

```bash
curl https://votre-n8n.cerema.fr/webhook/health

# Réponse attendue :
# {"status":"healthy","timestamp":"...","services":{"redis":"connected",...}}
```

### Test 4 : Flux Complet

1. **Ouvrez le widget** dans Grist
2. **Vérifiez** : Indicateur "LIVE" est vert
3. **Ajoutez une ligne** dans la table Interventions
4. **Observez** : Le widget se met à jour automatiquement (~500ms)
5. **Vérifiez** : Animation flash verte sur la nouvelle ligne
6. **Testez** : Notification visuelle apparaît en haut à droite

---

## 🎯 Configuration Avancée (Optionnel)

### Notifications Tchap

**Prérequis** : Token d'authentification Tchap

1. **Créez credential Tchap dans n8n** :
   ```
   Type : HTTP Header Auth
   Nom : Tchap Token
   Header Name : Authorization
   Header Value : Bearer VOTRE_TOKEN_TCHAP
   ```

2. **Ajoutez variable d'environnement** :
   ```bash
   # Dans docker-compose.yml de n8n
   environment:
     - TCHAP_ROOM_ID=!VotreRoomID:agent.tchap.gouv.fr
   ```

3. **Le workflow enverra automatiquement** :
   - Notification Tchap pour toutes interventions "Urgente"
   - Format : "🚨 URGENCE: [Agent] - [Lieu] ([Statut])"

### Monitoring Grafana

**Ajoutez node de monitoring** dans workflow n8n :

```json
{
  "name": "Grafana Metrics",
  "type": "n8n-nodes-base.httpRequest",
  "parameters": {
    "url": "http://votre-grafana:9091/metrics/job/grist_realtime",
    "method": "POST",
    "bodyParameters": {
      "intervention_updates_total": "={{ $execution.customData.broadcastCount }}",
      "processing_time_ms": "={{ $json.processingTime }}"
    }
  }
}
```

### Filtrage géographique

**Ajoutez node de filtrage** dans workflow :

```javascript
// Dans node "Code"
const interventions = $json.data;

// Filtre département 13 (Bouches-du-Rhône)
if (interventions.localisation.match(/^13/)) {
  return { json: interventions };
}

// Sinon, skip
return null;
```

---

## 📊 Monitoring Production

### Métriques à surveiller

```bash
# Nombre d'exécutions n8n
curl https://votre-n8n.cerema.fr/api/v1/executions?workflowId=XXX

# Statut Redis
redis-cli info stats

# Connexions SSE actives
netstat -an | grep :80 | grep ESTABLISHED | wc -l
```

### Logs

```bash
# Logs n8n
docker logs -f n8n

# Logs Redis
sudo tail -f /var/log/redis/redis-server.log

# Logs nginx
sudo tail -f /var/log/nginx/access.log
```

### Alertes recommandées

**À configurer dans votre monitoring** :

- ⚠️ Redis down → Alert critique
- ⚠️ n8n workflow fails > 5 en 10 min → Alert haute
- ⚠️ SSE connexions = 0 pendant > 5 min → Alert moyenne
- ⚠️ Latence webhook > 2s → Alert basse

---

## 🐛 Dépannage

### Problème : Widget ne se connecte pas au SSE

**Vérifications** :
```bash
# 1. Vérifier CORS nginx
curl -H "Origin: https://docs.getgrist.com" \
     -H "Access-Control-Request-Method: GET" \
     -X OPTIONS \
     https://votre-n8n.cerema.fr/webhook/sse-stream

# Doit retourner header : Access-Control-Allow-Origin: *

# 2. Tester SSE directement
curl -N https://votre-n8n.cerema.fr/webhook/sse-stream

# 3. Vérifier logs n8n
docker logs n8n | grep SSE
```

**Solution** : Ajouter config CORS dans nginx :
```nginx
location /webhook/ {
    add_header Access-Control-Allow-Origin *;
    add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS';
    add_header Access-Control-Allow-Headers 'Content-Type';
    
    if ($request_method = 'OPTIONS') {
        return 204;
    }
}
```

### Problème : Webhook Grist ne déclenche pas

**Vérifications** :
```bash
# 1. Test webhook manuel
curl -X POST https://votre-n8n.cerema.fr/webhook/grist-realtime \
  -H "Content-Type: application/json" \
  -d '{"id":"test","fields":{"Agent":"Test"}}'

# 2. Vérifier URL webhook dans Grist
# Document Settings → Webhooks → Vérifier URL exacte

# 3. Vérifier logs Grist
# Voir console admin Grist
```

**Solution** : Vérifier que :
- Webhook activé dans Grist ✓
- URL correcte (pas de trailing slash)
- Events add/update cochés

### Problème : Redis connexion failed

**Vérifications** :
```bash
# 1. Vérifier Redis running
sudo systemctl status redis-server

# 2. Test connexion
redis-cli ping

# 3. Vérifier bind address
redis-cli CONFIG GET bind
```

**Solution** :
```bash
# Si Redis pas accessible
sudo nano /etc/redis/redis.conf
# Modifier : bind 0.0.0.0
sudo systemctl restart redis-server
```

---

## 📚 Ressources

### URLs importantes

- **n8n** : https://votre-n8n.cerema.fr
- **Webhook Grist** : https://votre-n8n.cerema.fr/webhook/grist-realtime
- **SSE Stream** : https://votre-n8n.cerema.fr/webhook/sse-stream
- **Health Check** : https://votre-n8n.cerema.fr/webhook/health
- **Widget** : https://widgets.cerema.fr/grist-realtime-dashboard-widget.html

### Documentation

- n8n Redis node : https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.redis/
- Grist Webhooks : https://support.getgrist.com/webhooks/
- Server-Sent Events : https://developer.mozilla.org/en-US/docs/Web/API/Server-sent_events

### Support

- **Issues techniques** : Ouvrir ticket dans votre système interne
- **Logs** : Toujours joindre logs n8n + Redis
- **Tests** : Utiliser les commandes curl ci-dessus

---

## ✅ Checklist Post-Déploiement

- [ ] Redis installé et opérationnel
- [ ] Workflow n8n importé et activé
- [ ] Webhook Grist configuré et testé
- [ ] Widget hébergé et accessible
- [ ] Widget ajouté dans page Grist
- [ ] URL SSE configurée dans widget
- [ ] Test complet réussi (ajout ligne → mise à jour temps réel)
- [ ] Indicateur LIVE vert dans widget
- [ ] Notifications visuelles fonctionnelles
- [ ] Notifications Tchap configurées (optionnel)
- [ ] Monitoring en place
- [ ] Documentation équipe distribuée

---

## 🎓 Formation Utilisateurs Finaux

### Pour les agents terrain

**Actions** :
1. Ouvrir table Interventions dans Grist
2. Modifier le statut d'une intervention
3. La mise à jour apparaît instantanément sur tous les dashboards ouverts

**Astuce** : Ajoutez des commentaires pour informer l'équipe

### Pour les superviseurs

**Actions** :
1. Ouvrir la page Dashboard dans Grist
2. Laisser l'onglet ouvert (pas besoin de rafraîchir)
3. Indicateur "LIVE" vert = connexion active
4. Flash vert sur ligne = modification récente

**Filtres disponibles** :
- 🔄 Actives : Interventions non terminées
- 📋 Toutes : Toutes les interventions
- 🚨 Urgentes : Priorité urgente uniquement

**Notifications** :
- 🔔 Son activé/désactivé : Bouton en haut
- Notifications visuelles : Coin supérieur droit

---

## 🚀 Évolutions Futures

### Version 2.0 (planifié)

- [ ] Carte interactive OpenStreetMap
- [ ] Timeline historique modifications
- [ ] Graphiques temps réel (Chart.js)
- [ ] Export PDF automatique
- [ ] Intégration Albert API pour suggestions
- [ ] Mode hors-ligne avec sync
- [ ] Application mobile (PWA)

### Contributions bienvenues

Ce système est open-source et extensible. Suggestions d'amélioration : ouvrir une issue.

---

**Version** : 1.0.0  
**Date** : 2024-11-17  
**Auteur** : CEREMA Méditerranée - Groupe Ingénierie de la Donnée  
**Licence** : Libre - Réutilisation autorisée
