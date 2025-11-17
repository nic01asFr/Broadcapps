# 🔧 Guide d'Utilisation des Workflows n8n

## 📦 Fichiers Créés

1. **`n8n-workflow-1-grist-to-redis.json`** - Webhook Grist → Redis
2. **`n8n-workflow-2-api-interventions.json`** - API GET pour le widget

---

## 🚀 Workflow 1 : Webhook Grist → Redis

### Architecture

```
Webhook POST /webhook/grist-realtime
  ↓
Validation Payload (vérifie que ID existe)
  ↓
Préparer Message (structure le JSON)
  ↓
Redis Publish (canal: grist-realtime-interventions)
  ↓
Redis SET (clé: intervention:{id}, TTL: 24h)
  ↓
Filtre Urgentes (priorite === "Urgente")
  ↓ (si urgente)
Notification Tchap
  ↓
Réponse Succès + Log Metrics
```

### URL du Webhook

Une fois importé et activé, le webhook sera accessible à :
```
https://votre-n8n.cerema.fr/webhook/grist-realtime
```

### Configuration Grist

Dans Grist → Document Settings → Webhooks :
- **URL** : `https://votre-n8n.cerema.fr/webhook/grist-realtime`
- **Events** : `add`, `update`
- **Table** : `Interventions`
- **Activé** : ✓

### Credentials Requises

**Redis** :
- Type : Redis
- ID utilisé : "1"
- Nom : "Redis CEREMA"
- Host : localhost
- Port : 6379
- Database : 0

**Tchap (optionnel)** :
- Type : HTTP Header Auth
- ID utilisé : "2"
- Nom : "Tchap Token"
- Header : Authorization
- Value : `Bearer YOUR_TCHAP_TOKEN`

**Variable d'environnement** :
- `TCHAP_ROOM_ID` : L'ID de la room Tchap (ex: `!abc123:agent.tchap.gouv.fr`)

### Test Manuel

```bash
curl -X POST https://votre-n8n.cerema.fr/webhook/grist-realtime \
  -H "Content-Type: application/json" \
  -d '{
    "id": "test-123",
    "fields": {
      "Agent": "Test Agent",
      "Localisation": "Marseille",
      "Type": "Voirie",
      "Statut": "En cours",
      "Priorite": "Haute",
      "Commentaire": "Test intervention"
    }
  }'
```

**Réponse attendue** :
```json
{
  "success": true,
  "message": "Broadcast envoyé avec succès",
  "timestamp": "2024-11-17T...",
  "interventionId": "test-123"
}
```

---

## 📡 Workflow 2 : API Interventions (GET)

### Architecture

```
Webhook GET /api/interventions
  ↓
Redis KEYS "intervention:*"
  ↓
Transformer Keys (split en array)
  ↓
Préparer Lecture (pour chaque clé)
  ↓
Redis GET (récupère chaque intervention)
  ↓
Agréger Interventions (construit le JSON final)
  ↓
Réponse JSON
```

### URL de l'API

Une fois importé et activé, l'API sera accessible à :
```
https://votre-n8n.cerema.fr/webhook/interventions
```

### Format de Réponse

```json
{
  "success": true,
  "count": 15,
  "timestamp": "2024-11-17T10:30:00.000Z",
  "interventions": [
    {
      "id": "INT-001",
      "agent": "Marie Durand",
      "localisation": "Avenue de la République, Marseille",
      "type": "Voirie",
      "statut": "En cours",
      "priorite": "Urgente",
      "commentaire": "Nid-de-poule important"
    },
    {
      "id": "INT-002",
      ...
    }
  ]
}
```

**Caractéristiques** :
- ✅ Interventions triées par priorité (Urgente > Haute > Normale > Basse)
- ✅ Headers CORS configurés (accessible depuis GitHub Pages)
- ✅ Cache-Control: no-cache (données toujours fraîches)

### Test Manuel

```bash
curl https://votre-n8n.cerema.fr/webhook/interventions
```

---

## 🔄 Configuration du Widget pour Polling

Le widget doit être modifié pour utiliser le polling au lieu de SSE :

```javascript
// Supprimer la partie SSE
// Ajouter polling API

async function loadDataFromAPI() {
  try {
    const response = await fetch('https://votre-n8n.cerema.fr/webhook/interventions');
    const data = await response.json();

    if (data.success) {
      // Détecter les nouvelles interventions
      const newInterventions = data.interventions.filter(intervention =>
        !interventions.find(i => i.id === intervention.id)
      );

      // Mettre à jour
      interventions = data.interventions;
      calculateStats();
      renderDashboard();

      // Notifications pour nouveaux items
      if (newInterventions.length > 0) {
        showNotification(`${newInterventions.length} nouvelle(s) intervention(s)`, 'info');
        if (CONFIG.soundEnabled) playNotificationSound();
      }
    }
  } catch (e) {
    console.error('Erreur chargement API:', e);
  }
}

// Polling toutes les 5 secondes
setInterval(loadDataFromAPI, 5000);
```

---

## 📋 Procédure d'Installation dans n8n

### Étape 1 : Importer les Workflows

1. **Connectez-vous à n8n** : `https://votre-n8n.cerema.fr`

2. **Importez Workflow 1** :
   - Menu : Workflows → Import from File
   - Sélectionnez : `n8n-workflow-1-grist-to-redis.json`
   - Cliquez : Import

3. **Importez Workflow 2** :
   - Menu : Workflows → Import from File
   - Sélectionnez : `n8n-workflow-2-api-interventions.json`
   - Cliquez : Import

### Étape 2 : Configurer les Credentials

**Créer credential Redis** :
1. Menu : Credentials → New
2. Type : Redis
3. Nom : `Redis CEREMA`
4. Host : `localhost`
5. Port : `6379`
6. Database : `0`
7. Save

**Note** : L'ID du credential doit être "1" ou vous devez éditer les workflows pour correspondre.

**Créer credential Tchap (optionnel)** :
1. Menu : Credentials → New
2. Type : HTTP Header Auth
3. Nom : `Tchap Token`
4. Header Name : `Authorization`
5. Header Value : `Bearer YOUR_TCHAP_TOKEN`
6. Save

### Étape 3 : Configurer les Variables d'Environnement

Si vous utilisez Tchap, ajoutez dans les paramètres n8n :
```bash
TCHAP_ROOM_ID=!votre-room-id:agent.tchap.gouv.fr
```

### Étape 4 : Activer les Workflows

Pour chaque workflow :
1. Ouvrez le workflow
2. Cliquez sur le toggle en haut à droite : `Inactive` → **`Active`**
3. Vérifiez que le statut passe à "Active" (vert)

### Étape 5 : Tester

**Test Workflow 1** :
```bash
curl -X POST https://votre-n8n.cerema.fr/webhook/grist-realtime \
  -H "Content-Type: application/json" \
  -d '{"id":"test","fields":{"Agent":"Test","Statut":"En cours"}}'
```

**Test Workflow 2** :
```bash
curl https://votre-n8n.cerema.fr/webhook/interventions
```

---

## 🐛 Dépannage

### Workflow 1 : Erreurs Communes

**Erreur** : `Redis connection refused`
- **Solution** : Vérifier que Redis tourne : `systemctl status redis-server`
- Tester : `redis-cli ping` (doit retourner PONG)

**Erreur** : `Credential not found`
- **Solution** : Vérifier que le credential Redis existe avec ID "1"
- Ou éditer le workflow pour changer l'ID du credential

**Erreur** : `Tchap notification failed`
- **Solution** : Vérifier le token Tchap
- Vérifier que `TCHAP_ROOM_ID` est configuré
- C'est optionnel, le workflow continue sans Tchap

### Workflow 2 : Erreurs Communes

**Erreur** : `No keys found`
- **Normal** : Aucune intervention en cache
- Insérer des données via Workflow 1

**Erreur** : `CORS blocked`
- **Solution** : Vérifier les headers CORS dans le node "Réponse JSON"
- `Access-Control-Allow-Origin: *` doit être présent

---

## 📊 Monitoring

### Vérifier les Exécutions

Dans n8n :
1. Menu : Executions
2. Filtrer par workflow
3. Vérifier les statuts :
   - ✅ Success (vert)
   - ❌ Error (rouge)

### Logs Redis

```bash
# Voir toutes les clés interventions
redis-cli KEYS "intervention:*"

# Voir une intervention spécifique
redis-cli GET "intervention:test-123"

# Compter les interventions en cache
redis-cli KEYS "intervention:*" | wc -l
```

### Métriques

Le Workflow 1 log automatiquement :
- Timestamp
- Type d'événement
- Priorité
- Statut
- Agent
- Temps de traitement

Accessible dans les logs d'exécution n8n.

---

## 🎯 Prochaines Étapes

1. ✅ Installer Redis sur le serveur
2. ✅ Importer les 2 workflows dans n8n
3. ✅ Configurer les credentials Redis
4. ✅ Activer les workflows
5. ✅ Configurer le webhook dans Grist
6. ⚠️ Modifier le widget pour utiliser polling (à la place de SSE)
7. ✅ Tester le flux complet

---

## 📝 Notes Importantes

### Limitation : Pas de SSE Natif

Ces workflows utilisent **polling** (5-10s latence) au lieu de SSE (<500ms).

**Pourquoi ?** :
- n8n ne peut pas maintenir des connexions SSE longue durée vers plusieurs clients
- Redis Pub/Sub dans n8n ne peut pas broadcaster vers des connexions HTTP maintenues

**Alternatives pour du vrai SSE** :
- Mini serveur Node.js (100 lignes) à côté de n8n
- Service externe type Pusher, Ably
- WebSockets au lieu de SSE

**Mais le polling fonctionne très bien** pour la majorité des cas d'usage !

---

## ✅ Checklist Installation

- [ ] Redis installé et opérationnel
- [ ] Workflows importés dans n8n
- [ ] Credential Redis créé (ID: 1)
- [ ] Credential Tchap créé (optionnel, ID: 2)
- [ ] Variable TCHAP_ROOM_ID configurée (optionnel)
- [ ] Workflow 1 activé
- [ ] Workflow 2 activé
- [ ] Webhook Grist configuré
- [ ] Test webhook manuel réussi
- [ ] Test API GET manuel réussi
- [ ] Widget modifié pour polling
- [ ] Test flux complet Grist → Widget

---

**Version** : 1.0.0
**Date** : 2024-11-17
**Auteur** : Claude Code
