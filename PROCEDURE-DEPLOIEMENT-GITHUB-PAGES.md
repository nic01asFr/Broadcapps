# 🚀 Procédure de Déploiement GitHub Pages

## Vue d'ensemble

Le widget Grist est maintenant hébergé sur **GitHub Pages** et accessible publiquement.
Aucun build n'est nécessaire car c'est un fichier HTML autonome.

---

## ✅ Ce qui a été configuré

### 1. Workflow GitHub Actions
**Fichier** : `.github/workflows/deploy-pages.yml`

- ✅ Déploiement automatique sur push vers `main` ou `master`
- ✅ Déploiement manuel possible via l'interface GitHub
- ✅ Permissions configurées pour GitHub Pages
- ✅ Pas de build requis (fichiers statiques uniquement)

### 2. Page d'accueil
**Fichier** : `index.html`

- ✅ Page d'accueil élégante avec présentation du système
- ✅ Lien direct vers le widget
- ✅ URL du widget copiable en un clic
- ✅ Documentation intégrée

### 3. Widget Grist
**Fichier** : `grist-realtime-dashboard-widget.html`

- ✅ Widget fonctionnel prêt à l'emploi
- ✅ Autonome (pas de dépendances externes)
- ✅ Configuration SSE via interface

---

## 📋 Étapes de Mise en Œuvre

### ÉTAPE 1 : Activer GitHub Pages

1. **Accédez aux paramètres du repository** :
   ```
   https://github.com/nic01asFr/Broadcapps/settings/pages
   ```

2. **Configurez GitHub Pages** :
   - **Source** : GitHub Actions
   - Cliquez sur "Save"

3. **Attendez le premier déploiement** (2-3 minutes)

4. **Votre site sera disponible à** :
   ```
   https://nic01asfr.github.io/Broadcapps/
   ```

### ÉTAPE 2 : Merger la branche Claude

Actuellement sur la branche : `claude/init-project-013PzZywMWcgzTMbMs17P6qa`

**Option A : Via GitHub (recommandé)**
```bash
# 1. Créer une Pull Request sur GitHub
# 2. Review les changements
# 3. Merge vers main
```

**Option B : Via ligne de commande**
```bash
# 1. Basculer vers main
git checkout main

# 2. Merger la branche Claude
git merge claude/init-project-013PzZywMWcgzTMbMs17P6qa

# 3. Pousser vers GitHub
git push origin main
```

### ÉTAPE 3 : Vérifier le déploiement

1. **Accédez à l'onglet "Actions"** :
   ```
   https://github.com/nic01asFr/Broadcapps/actions
   ```

2. **Vérifiez que le workflow s'exécute** :
   - Nom : "Deploy to GitHub Pages"
   - Status : ✅ Succès (vert)
   - Durée : ~1-2 minutes

3. **Testez l'accès au site** :
   ```
   https://nic01asfr.github.io/Broadcapps/
   ```

4. **Testez l'accès direct au widget** :
   ```
   https://nic01asfr.github.io/Broadcapps/grist-realtime-dashboard-widget.html
   ```

---

## 🎯 Configuration dans Grist

### 1. Créer la table Interventions

| Colonne | Type | Configuration |
|---------|------|---------------|
| ID | Texte | Identifiant unique |
| Agent | Texte | Nom de l'agent |
| Localisation | Texte | Lieu |
| Type | Choix | Voirie, Signalisation, Bâtiment, Autre |
| Statut | Choix | En attente, En cours, Terminé, Bloqué |
| Priorite | Choix | Basse, Normale, Haute, Urgente |
| Derniere_MAJ | DateTime | Formule : `NOW()` |
| Commentaire | Texte | Notes |

### 2. Configurer le Webhook Grist

**Menu** : Document Settings → Webhooks

```
Nom : Broadcast Interventions
URL : https://votre-n8n.cerema.fr/webhook/grist-realtime
Events : add, update
Table : Interventions
Activé : ✓
```

### 3. Ajouter le Widget Custom

1. **Créer une nouvelle page** dans Grist
2. **Ajouter un widget** : "Custom Widget"
3. **Configurer** :
   - **URL** : `https://nic01asfr.github.io/Broadcapps/grist-realtime-dashboard-widget.html`
   - **Access Level** : Read table
   - **Table** : Interventions
4. **Au premier chargement** :
   - Le widget affiche un panneau de configuration
   - Entrez l'URL SSE : `https://votre-n8n.cerema.fr/webhook/sse-stream`
   - Cliquez "Enregistrer et connecter"
5. **Vérifier** :
   - Indicateur "LIVE" doit être vert 🟢
   - Les données de la table s'affichent

---

## ⚙️ Configuration n8n (Backend)

### 1. Installer Redis

```bash
# Installation (si pas déjà fait)
sudo apt update
sudo apt install redis-server -y
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Test
redis-cli ping
# Doit retourner : PONG
```

### 2. Configurer Redis pour n8n

```bash
# Éditer la config
sudo nano /etc/redis/redis.conf

# Ajouter/modifier :
bind 0.0.0.0
protected-mode yes
maxmemory 256mb
maxmemory-policy allkeys-lru

# Redémarrer
sudo systemctl restart redis-server
```

### 3. Importer le Workflow n8n

1. **Connectez-vous à n8n** : `https://votre-n8n.cerema.fr`

2. **Créer credentials Redis** :
   - Menu : Credentials → New
   - Type : Redis
   - Nom : `Redis CEREMA`
   - Host : `localhost`
   - Port : `6379`
   - Database : `0`
   - Save

3. **Importer le workflow** :
   - Menu : Workflows → Import from File
   - Sélectionner : `grist-realtime-n8n-workflow.json`
   - Import

4. **Activer le workflow** :
   - Ouvrir le workflow
   - Toggle en haut à droite : Inactive → **Active**

5. **Noter les URLs** :
   - Webhook Grist : `https://votre-n8n.cerema.fr/webhook/grist-realtime`
   - SSE Stream : `https://votre-n8n.cerema.fr/webhook/sse-stream`
   - Health : `https://votre-n8n.cerema.fr/webhook/health`

---

## 🧪 Tests Complets

### Test 1 : GitHub Pages accessible

```bash
curl -I https://nic01asfr.github.io/Broadcapps/
# HTTP/2 200 ✅

curl -I https://nic01asfr.github.io/Broadcapps/grist-realtime-dashboard-widget.html
# HTTP/2 200 ✅
```

### Test 2 : n8n Health Check

```bash
curl https://votre-n8n.cerema.fr/webhook/health
# {"status":"healthy",...} ✅
```

### Test 3 : Webhook Grist → n8n

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
      "Priorite": "Haute"
    }
  }'

# {"success":true,"message":"Broadcast envoyé"} ✅
```

### Test 4 : Connexion SSE

```bash
curl -N https://votre-n8n.cerema.fr/webhook/sse-stream

# Connexion maintenue, attente d'événements... ✅
# (Ctrl+C pour arrêter)
```

### Test 5 : Flux complet

1. Ouvrir le widget dans Grist
2. Vérifier : Indicateur "LIVE" vert 🟢
3. Ajouter une ligne dans la table Interventions
4. Observer : Mise à jour dans le widget < 500ms ⚡
5. Vérifier : Animation flash + notification

---

## 📊 Monitoring & Maintenance

### Commandes de surveillance

Si le script `install-grist-realtime.sh` a été exécuté sur le serveur :

```bash
# Statut du système
grist-status

# Lancer tous les tests
grist-test

# Logs en temps réel
grist-logs redis
grist-logs nginx
grist-logs nginx-error

# Métriques Redis
redis-cli info stats
redis-cli info memory
```

### Vérifications régulières

**GitHub Pages** :
- ✅ Site accessible à l'URL GitHub Pages
- ✅ Workflow "Deploy to GitHub Pages" en succès

**n8n** :
- ✅ Workflow actif (pas "Inactive")
- ✅ Exécutions récentes visibles
- ✅ Pas d'erreurs dans les logs

**Redis** :
- ✅ Service running : `systemctl status redis-server`
- ✅ Ping répond : `redis-cli ping`
- ✅ Mémoire < 256MB

**Widget dans Grist** :
- ✅ Indicateur "LIVE" vert
- ✅ Données affichées
- ✅ Mise à jour temps réel fonctionnelle

---

## 🚨 Dépannage

### Widget ne charge pas

**Problème** : Le widget affiche une erreur ou ne charge pas

**Solutions** :
1. Vérifier que GitHub Pages est activé
2. Vérifier l'URL du widget : `https://nic01asfr.github.io/Broadcapps/grist-realtime-dashboard-widget.html`
3. Vérifier les logs dans la console navigateur (F12)
4. Vérifier que le workflow GitHub Actions a réussi

### Indicateur "DÉCONNECTÉ" (rouge)

**Problème** : Le widget charge mais reste déconnecté

**Solutions** :
1. Vérifier l'URL SSE configurée dans le widget
2. Tester la connexion SSE : `curl -N https://votre-n8n.cerema.fr/webhook/sse-stream`
3. Vérifier que le workflow n8n est actif
4. Vérifier les credentials Redis dans n8n
5. Vérifier que Redis tourne : `systemctl status redis-server`

### Webhook Grist ne déclenche rien

**Problème** : Modifications dans Grist n'apparaissent pas dans le widget

**Solutions** :
1. Vérifier la configuration webhook dans Grist (URL correcte ?)
2. Tester manuellement le webhook avec curl (voir Test 3)
3. Vérifier les exécutions dans n8n (onglet "Executions")
4. Vérifier les logs n8n pour erreurs
5. Vérifier que la table est bien "Interventions"

### Erreur CORS

**Problème** : Console navigateur affiche des erreurs CORS

**Solutions** :
1. Vérifier que le workflow n8n a les headers CORS :
   ```
   Access-Control-Allow-Origin: *
   X-Accel-Buffering: no
   ```
2. Pour SSE, les headers doivent inclure :
   ```
   Content-Type: text/event-stream
   Cache-Control: no-cache
   Connection: keep-alive
   ```

---

## 🔄 Mises à Jour Futures

### Pour modifier le widget

1. **Éditer** `grist-realtime-dashboard-widget.html`
2. **Commit** les changements :
   ```bash
   git add grist-realtime-dashboard-widget.html
   git commit -m "Update widget: description"
   git push origin main
   ```
3. **Attendre** 2-3 minutes (déploiement auto)
4. **Vérifier** la nouvelle version sur GitHub Pages
5. **Rafraîchir** le widget dans Grist (Ctrl+F5)

### Pour modifier le workflow n8n

1. **Éditer** dans l'interface n8n
2. **Tester** avec "Execute Workflow"
3. **Sauvegarder** dans n8n
4. **(Optionnel)** Exporter et commit le JSON mis à jour

---

## 📚 Ressources

- **Documentation complète** : [README.md](README.md)
- **Guide installation serveur** : [DEPLOIEMENT-RAPIDE.md](DEPLOIEMENT-RAPIDE.md)
- **Guide technique détaillé** : [grist-realtime-sync-guide.md](grist-realtime-sync-guide.md)
- **Guide Claude Code** : [CLAUDE.md](CLAUDE.md)
- **GitHub Actions** : https://github.com/nic01asfr/Broadcapps/actions
- **GitHub Pages** : https://nic01asfr.github.io/Broadcapps/

---

## ✅ Checklist Finale

Avant de considérer le système opérationnel :

- [ ] GitHub Pages activé dans les settings du repo
- [ ] Workflow GitHub Actions déployé avec succès
- [ ] Page d'accueil accessible : `https://nic01asfr.github.io/Broadcapps/`
- [ ] Widget accessible : `https://nic01asfr.github.io/Broadcapps/grist-realtime-dashboard-widget.html`
- [ ] Redis installé et opérationnel sur le serveur
- [ ] Workflow n8n importé et activé
- [ ] Credentials Redis configurés dans n8n
- [ ] Webhook Grist configuré et pointant vers n8n
- [ ] Table Interventions créée dans Grist avec bonnes colonnes
- [ ] Widget ajouté dans Grist avec URL GitHub Pages
- [ ] URL SSE configurée dans le widget
- [ ] Indicateur "LIVE" vert dans le widget
- [ ] Test complet : modification Grist → update widget < 500ms

---

**Version** : 1.0.0
**Date** : 2024-11-17
**Auteur** : Claude Code
**Repository** : https://github.com/nic01asfr/Broadcapps
