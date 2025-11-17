#!/bin/bash

# ============================================
# Script d'installation automatique
# Grist Realtime Broadcasting System
# CEREMA Méditerranée
# ============================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

print_header() {
    echo -e "${BLUE}"
    echo "============================================"
    echo "$1"
    echo "============================================"
    echo -e "${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
       print_error "Ce script doit être exécuté en tant que root (sudo)"
       exit 1
    fi
}

check_command() {
    if command -v $1 &> /dev/null; then
        print_success "$1 est installé"
        return 0
    else
        print_warning "$1 n'est pas installé"
        return 1
    fi
}

# ============================================
# MAIN INSTALLATION
# ============================================

print_header "🚀 Installation Grist Realtime System"

echo "Ce script va installer et configurer :"
echo "  - Redis (Pub/Sub)"
echo "  - Nginx (Hébergement widget)"
echo "  - Configuration système"
echo ""
read -p "Continuer ? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
fi

# Check if running as root
check_root

# ============================================
# STEP 1: System Update
# ============================================

print_header "📦 Mise à jour du système"

apt update -qq
apt upgrade -y -qq

print_success "Système à jour"

# ============================================
# STEP 2: Install Redis
# ============================================

print_header "🗄️ Installation Redis"

if check_command redis-server; then
    print_info "Redis déjà installé, configuration..."
else
    print_info "Installation de Redis..."
    apt install redis-server -y
    print_success "Redis installé"
fi

# Configure Redis
print_info "Configuration Redis..."

REDIS_CONF="/etc/redis/redis.conf"

# Backup original config
cp $REDIS_CONF ${REDIS_CONF}.backup

# Configure Redis for n8n
cat > $REDIS_CONF << 'EOF'
# Redis Configuration for Grist Realtime
bind 0.0.0.0
protected-mode yes
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize yes
supervised systemd
pidfile /var/run/redis/redis-server.pid
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly no
EOF

# Enable and start Redis
systemctl enable redis-server
systemctl restart redis-server

# Test Redis
sleep 2
if redis-cli ping > /dev/null 2>&1; then
    print_success "Redis configuré et opérationnel"
else
    print_error "Erreur : Redis ne répond pas"
    exit 1
fi

# ============================================
# STEP 3: Install Nginx
# ============================================

print_header "🌐 Installation Nginx"

if check_command nginx; then
    print_info "Nginx déjà installé"
else
    print_info "Installation de Nginx..."
    apt install nginx -y
    print_success "Nginx installé"
fi

# Create widget directory
WIDGET_DIR="/var/www/grist-widgets"
mkdir -p $WIDGET_DIR
chown -R www-data:www-data $WIDGET_DIR

print_success "Répertoire widget créé : $WIDGET_DIR"

# Configure Nginx site
print_info "Configuration Nginx..."

NGINX_SITE="/etc/nginx/sites-available/grist-widgets"

cat > $NGINX_SITE << 'EOF'
server {
    listen 80;
    server_name widgets.cerema.local;
    
    root /var/www/grist-widgets;
    index grist-realtime-dashboard-widget.html;
    
    # CORS headers for Grist
    add_header Access-Control-Allow-Origin * always;
    add_header Access-Control-Allow-Methods 'GET, POST, OPTIONS' always;
    add_header Access-Control-Allow-Headers 'Content-Type' always;
    
    location / {
        try_files $uri $uri/ =404;
    }
    
    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        expires 7d;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Enable site
ln -sf $NGINX_SITE /etc/nginx/sites-enabled/grist-widgets

# Test nginx config
if nginx -t > /dev/null 2>&1; then
    systemctl reload nginx
    print_success "Nginx configuré et rechargé"
else
    print_error "Erreur configuration Nginx"
    exit 1
fi

# ============================================
# STEP 4: System Optimization
# ============================================

print_header "⚙️ Optimisation système"

# Increase file limits for Redis
cat >> /etc/security/limits.conf << 'EOF'
# Redis limits
redis soft nofile 65535
redis hard nofile 65535
EOF

# Sysctl optimization
cat > /etc/sysctl.d/99-grist-realtime.conf << 'EOF'
# Redis optimization
vm.overcommit_memory = 1
net.core.somaxconn = 65535
EOF

sysctl -p /etc/sysctl.d/99-grist-realtime.conf > /dev/null 2>&1

print_success "Système optimisé"

# ============================================
# STEP 5: Create Configuration Files
# ============================================

print_header "📝 Création fichiers de configuration"

# Create config directory
CONFIG_DIR="/etc/grist-realtime"
mkdir -p $CONFIG_DIR

# Main config file
cat > $CONFIG_DIR/config.env << 'EOF'
# Grist Realtime Configuration
# Generated on $(date)

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0

# n8n URLs (à compléter)
N8N_BASE_URL=https://votre-n8n.cerema.fr
N8N_WEBHOOK_GRIST=/webhook/grist-realtime
N8N_SSE_STREAM=/webhook/sse-stream

# Widget
WIDGET_URL=http://widgets.cerema.local/grist-realtime-dashboard-widget.html

# Monitoring
LOG_LEVEL=info
METRICS_ENABLED=true
EOF

print_success "Configuration créée dans $CONFIG_DIR"

# ============================================
# STEP 6: Create Helper Scripts
# ============================================

print_header "🛠️ Création scripts utilitaires"

# Status check script
cat > /usr/local/bin/grist-status << 'EOF'
#!/bin/bash

echo "=== Grist Realtime System Status ==="
echo ""

# Redis
echo "📊 Redis:"
if systemctl is-active --quiet redis-server; then
    echo "  ✓ Service: Running"
    redis-cli ping > /dev/null 2>&1 && echo "  ✓ Connection: OK" || echo "  ✗ Connection: Failed"
    echo "  Memory: $(redis-cli info memory | grep used_memory_human | cut -d: -f2)"
else
    echo "  ✗ Service: Stopped"
fi

echo ""

# Nginx
echo "🌐 Nginx:"
if systemctl is-active --quiet nginx; then
    echo "  ✓ Service: Running"
else
    echo "  ✗ Service: Stopped"
fi

echo ""

# Widget files
echo "📁 Widget Files:"
if [ -d "/var/www/grist-widgets" ]; then
    echo "  ✓ Directory exists"
    FILE_COUNT=$(ls -1 /var/www/grist-widgets/*.html 2>/dev/null | wc -l)
    echo "  Files: $FILE_COUNT HTML file(s)"
else
    echo "  ✗ Directory not found"
fi

echo ""

# Network
echo "🔌 Network:"
echo "  Redis Port: $(netstat -tuln | grep :6379 | wc -l) listener(s)"
echo "  Nginx Port: $(netstat -tuln | grep :80 | wc -l) listener(s)"
EOF

chmod +x /usr/local/bin/grist-status

print_success "Script de status créé : grist-status"

# Test script
cat > /usr/local/bin/grist-test << 'EOF'
#!/bin/bash

echo "=== Grist Realtime System Tests ==="
echo ""

# Test Redis
echo "🧪 Test Redis..."
if redis-cli ping > /dev/null 2>&1; then
    echo "  ✓ Redis: OK"
else
    echo "  ✗ Redis: FAILED"
fi

# Test Nginx
echo ""
echo "🧪 Test Nginx..."
if curl -s http://localhost > /dev/null; then
    echo "  ✓ Nginx: OK"
else
    echo "  ✗ Nginx: FAILED"
fi

# Test widget access
echo ""
echo "🧪 Test Widget Access..."
WIDGET_URL="http://localhost/grist-realtime-dashboard-widget.html"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" $WIDGET_URL)
if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✓ Widget accessible: OK"
else
    echo "  ⚠ Widget not found (HTTP $HTTP_CODE)"
    echo "  → Copiez grist-realtime-dashboard-widget.html dans /var/www/grist-widgets/"
fi

echo ""
echo "Tests terminés !"
EOF

chmod +x /usr/local/bin/grist-test

print_success "Script de test créé : grist-test"

# Logs viewer script
cat > /usr/local/bin/grist-logs << 'EOF'
#!/bin/bash

case "$1" in
    redis)
        tail -f /var/log/redis/redis-server.log
        ;;
    nginx)
        tail -f /var/log/nginx/access.log
        ;;
    nginx-error)
        tail -f /var/log/nginx/error.log
        ;;
    *)
        echo "Usage: grist-logs [redis|nginx|nginx-error]"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/grist-logs

print_success "Script de logs créé : grist-logs"

# ============================================
# STEP 7: Create Systemd Service (Monitoring)
# ============================================

print_header "📊 Configuration monitoring"

cat > /etc/systemd/system/grist-monitor.service << 'EOF'
[Unit]
Description=Grist Realtime Monitoring
After=network.target redis-server.service

[Service]
Type=simple
ExecStart=/usr/local/bin/grist-status
Restart=on-failure
RestartSec=60

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload

print_success "Service de monitoring créé (non activé par défaut)"

# ============================================
# STEP 8: Firewall Configuration
# ============================================

print_header "🔥 Configuration Firewall"

if check_command ufw; then
    print_info "Configuration UFW..."
    ufw allow 80/tcp comment 'Nginx - Widget'
    ufw allow 6379/tcp comment 'Redis'
    print_success "Règles firewall ajoutées"
else
    print_warning "UFW non installé, configuration firewall manuelle recommandée"
fi

# ============================================
# FINAL STEPS
# ============================================

print_header "✅ Installation Terminée !"

echo ""
echo "📋 Résumé de l'installation :"
echo "  • Redis : ✓ Installé et configuré"
echo "  • Nginx : ✓ Installé et configuré"
echo "  • Scripts utilitaires : ✓ Créés"
echo "  • Optimisations système : ✓ Appliquées"
echo ""

print_info "🎯 Prochaines étapes :"
echo ""
echo "1. Copiez le widget HTML dans le répertoire :"
echo "   cp grist-realtime-dashboard-widget.html /var/www/grist-widgets/"
echo ""
echo "2. Importez le workflow n8n :"
echo "   • Connectez-vous à n8n"
echo "   • Import from File : grist-realtime-n8n-workflow.json"
echo ""
echo "3. Configurez le webhook dans Grist :"
echo "   • URL : https://votre-n8n.cerema.fr/webhook/grist-realtime"
echo "   • Events : add, update"
echo ""
echo "4. Testez l'installation :"
echo "   grist-test"
echo ""
echo "5. Vérifiez le statut :"
echo "   grist-status"
echo ""

print_info "📚 Commandes utiles :"
echo "  • grist-status    : Affiche l'état du système"
echo "  • grist-test      : Lance les tests"
echo "  • grist-logs redis: Affiche logs Redis"
echo "  • grist-logs nginx: Affiche logs Nginx"
echo ""

print_info "📖 Documentation complète : DEPLOIEMENT-RAPIDE.md"

echo ""
print_success "Installation réussie ! 🎉"
echo ""

# Save installation info
cat > $CONFIG_DIR/install.info << EOF
Installation Date: $(date)
System: $(uname -a)
Redis Version: $(redis-server --version)
Nginx Version: $(nginx -v 2>&1 | cut -d'/' -f2)
Script Version: 1.0.0
EOF

exit 0
