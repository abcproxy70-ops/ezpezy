#!/bin/bash
set -e

# ============================================
#  Быстрая настройка nginx + SSL + фейксайт
#  Status page (maintenance) для VLESS Reality
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Настройка nginx + SSL + status page${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# --- Ввод домена ---
read -rp "Введите домен (например, ru.example.com): " DOMAIN

if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}Домен не может быть пустым!${NC}"
    exit 1
fi

# --- Выбор порта ---
echo ""
echo -e "${YELLOW}На каком порту поднять nginx с SSL (фейксайт)?${NC}"
echo -e "Этот порт будет указан как dest в Reality."
echo ""
read -rp "Порт для nginx SSL [443]: " NGINX_SSL_PORT
NGINX_SSL_PORT=${NGINX_SSL_PORT:-443}

if ! [[ "$NGINX_SSL_PORT" =~ ^[0-9]+$ ]] || [[ "$NGINX_SSL_PORT" -lt 1 || "$NGINX_SSL_PORT" -gt 65535 ]]; then
    echo -e "${RED}Некорректный порт!${NC}"
    exit 1
fi

# --- DNS ---
echo -e "\n${YELLOW}Проверяю DNS для ${DOMAIN}...${NC}"
SERVER_IP=$(curl -s --max-time 3 -4 https://api.ipify.org)
DOMAIN_IP=$(dig +short "$DOMAIN" A | tail -1)
echo "IP сервера:  $SERVER_IP"
echo "IP домена:   $DOMAIN_IP"

if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
    echo -e "${RED}A-запись домена ($DOMAIN_IP) не совпадает с IP сервера ($SERVER_IP)!${NC}"
    exit 1
fi
echo -e "${GREEN}DNS ок.${NC}"

# --- Порты ---
if ss -tuln | grep -q ":80 "; then
    echo -e "${RED}Порт 80 занят!${NC}"
    exit 1
fi
if ss -tuln | grep -q ":${NGINX_SSL_PORT} "; then
    echo -e "${RED}Порт ${NGINX_SSL_PORT} занят!${NC}"
    exit 1
fi
echo -e "${GREEN}Порты свободны.${NC}"

# --- Установка ---
echo -e "\n${YELLOW}Устанавливаю nginx, certbot...${NC}"
apt update -qq
apt install -y -qq nginx certbot python3-certbot-nginx > /dev/null 2>&1
systemctl stop nginx 2>/dev/null || true
echo -e "${GREEN}Установлено.${NC}"

# --- SSL ---
echo -e "\n${YELLOW}Получаю SSL сертификат...${NC}"
certbot certonly --standalone --non-interactive --agree-tos \
    -m "admin@${DOMAIN}" -d "$DOMAIN"
echo -e "${GREEN}Сертификат получен.${NC}"

# --- Извлекаем имя из домена для брендинга ---
DOMAIN_NAME=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)}')
DOMAIN_TITLE=$(echo "$DOMAIN_NAME" | sed 's/.*/\u&/')
CURRENT_YEAR=$(date +"%Y")
CURRENT_DATE=$(date -u +"%Y-%m-%d")

# --- Генерация status page ---
echo -e "\n${YELLOW}Создаю status page...${NC}"
rm -rf /var/www/html/*

cat > /var/www/html/index.html << HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${DOMAIN_TITLE} Cloud — Service Status</title>
<meta name="description" content="${DOMAIN_TITLE} Cloud service status and maintenance information">
<meta name="robots" content="noindex, nofollow">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><circle cx='50' cy='50' r='40' fill='%23f59e0b'/></svg>">
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', sans-serif;
    background: #0f1419;
    color: #e6e6e6;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    line-height: 1.6;
}
.container {
    flex: 1;
    max-width: 720px;
    margin: 0 auto;
    padding: 80px 24px 40px;
    width: 100%;
}
.logo {
    display: flex;
    align-items: center;
    gap: 12px;
    margin-bottom: 60px;
    font-size: 18px;
    font-weight: 600;
}
.logo-mark {
    width: 32px;
    height: 32px;
    border-radius: 8px;
    background: linear-gradient(135deg, #3b82f6, #8b5cf6);
}
.status-icon {
    width: 64px;
    height: 64px;
    border-radius: 50%;
    background: rgba(245, 158, 11, 0.15);
    display: flex;
    align-items: center;
    justify-content: center;
    margin-bottom: 24px;
}
.status-icon::before {
    content: '';
    width: 32px;
    height: 32px;
    border-radius: 50%;
    background: #f59e0b;
    animation: pulse 2s ease-in-out infinite;
}
@keyframes pulse {
    0%, 100% { opacity: 1; transform: scale(1); }
    50% { opacity: 0.6; transform: scale(0.92); }
}
h1 {
    font-size: 32px;
    font-weight: 700;
    margin-bottom: 16px;
    letter-spacing: -0.5px;
}
.subtitle {
    font-size: 17px;
    color: #9ca3af;
    margin-bottom: 40px;
    max-width: 540px;
}
.status-card {
    background: #1a1f2e;
    border: 1px solid #2d3748;
    border-radius: 12px;
    padding: 24px;
    margin-bottom: 16px;
}
.status-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 0;
    border-bottom: 1px solid #2d3748;
}
.status-row:last-child { border-bottom: none; }
.service-name { font-weight: 500; }
.status-badge {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 14px;
    color: #9ca3af;
}
.dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
}
.dot.ok { background: #10b981; }
.dot.warn { background: #f59e0b; }
.info-block {
    background: #1a1f2e;
    border: 1px solid #2d3748;
    border-radius: 12px;
    padding: 20px 24px;
    margin-top: 24px;
    font-size: 14px;
    color: #9ca3af;
}
.info-block strong { color: #e6e6e6; }
footer {
    border-top: 1px solid #1f2937;
    padding: 24px;
    text-align: center;
    font-size: 13px;
    color: #6b7280;
}
footer a { color: #9ca3af; text-decoration: none; margin: 0 8px; }
footer a:hover { color: #e6e6e6; }
</style>
</head>
<body>
<div class="container">
    <div class="logo">
        <div class="logo-mark"></div>
        <span>${DOMAIN_TITLE} Cloud</span>
    </div>

    <div class="status-icon"></div>
    <h1>Scheduled Maintenance</h1>
    <p class="subtitle">We're performing routine infrastructure updates to improve performance and reliability. Service will be restored shortly.</p>

    <div class="status-card">
        <div class="status-row">
            <span class="service-name">API Gateway</span>
            <span class="status-badge"><span class="dot warn"></span>Maintenance</span>
        </div>
        <div class="status-row">
            <span class="service-name">Web Console</span>
            <span class="status-badge"><span class="dot warn"></span>Maintenance</span>
        </div>
        <div class="status-row">
            <span class="service-name">CDN Edge</span>
            <span class="status-badge"><span class="dot ok"></span>Operational</span>
        </div>
        <div class="status-row">
            <span class="service-name">Authentication</span>
            <span class="status-badge"><span class="dot ok"></span>Operational</span>
        </div>
    </div>

    <div class="info-block">
        <strong>Need help?</strong> Contact <a href="mailto:support@${DOMAIN}" style="color:#60a5fa;">support@${DOMAIN}</a> for urgent issues.
    </div>
</div>

<footer>
    © ${CURRENT_YEAR} ${DOMAIN_TITLE} Cloud
    <a href="/privacy">Privacy</a>·
    <a href="/terms">Terms</a>·
    <a href="/api/health">Status API</a>
</footer>
</body>
</html>
HTML

# --- Заглушки для /privacy и /terms ---
for page in privacy terms; do
    cat > /var/www/html/${page}.html << EOF
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>${page^} — ${DOMAIN_TITLE} Cloud</title>
<style>body{font-family:-apple-system,sans-serif;background:#0f1419;color:#e6e6e6;max-width:720px;margin:80px auto;padding:24px;line-height:1.6}a{color:#60a5fa}</style>
</head>
<body><h1>${page^}</h1><p>This page is currently unavailable due to scheduled maintenance.</p>
<p><a href="/">← Back to status page</a></p></body></html>
EOF
done

# --- robots.txt ---
cat > /var/www/html/robots.txt << EOF
User-agent: *
Disallow: /admin
Disallow: /api/internal
Allow: /
Sitemap: https://${DOMAIN}/sitemap.xml
EOF

# --- sitemap.xml ---
cat > /var/www/html/sitemap.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://${DOMAIN}/</loc><lastmod>${CURRENT_DATE}</lastmod><priority>1.0</priority></url>
  <url><loc>https://${DOMAIN}/privacy</loc><lastmod>${CURRENT_DATE}</lastmod><priority>0.5</priority></url>
  <url><loc>https://${DOMAIN}/terms</loc><lastmod>${CURRENT_DATE}</lastmod><priority>0.5</priority></url>
</urlset>
EOF

# --- Health endpoint (JSON) ---
mkdir -p /var/www/html/api
cat > /var/www/html/api/health.json << EOF
{"status":"maintenance","service":"${DOMAIN_NAME}-api","version":"1.0.0","message":"Scheduled maintenance in progress"}
EOF

echo -e "${GREEN}Status page готов.${NC}"

# --- nginx config ---
echo -e "\n${YELLOW}Настраиваю nginx...${NC}"
rm -f /etc/nginx/sites-enabled/*
rm -f /etc/nginx/sites-available/default

cat > /etc/nginx/sites-enabled/"$DOMAIN" << NGINX
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen ${NGINX_SSL_PORT} ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    server_tokens off;

    root /var/www/html;
    index index.html;

    location / {
        try_files \$uri \$uri.html \$uri/ /index.html;
    }

    location = /api/health {
        default_type application/json;
        alias /var/www/html/api/health.json;
    }
}
NGINX

# --- UFW ---
if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow ${NGINX_SSL_PORT}/tcp > /dev/null 2>&1
fi

# --- Запуск ---
nginx -t
systemctl start nginx
systemctl enable nginx

# --- Auto-renew hook ---
RENEW_HOOK="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
mkdir -p "$(dirname "$RENEW_HOOK")"
cat > "$RENEW_HOOK" << 'EOF'
#!/bin/bash
systemctl reload nginx
EOF
chmod +x "$RENEW_HOOK"

# --- Результат ---
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Готово!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Сайт:         https://${DOMAIN}$([ "$NGINX_SSL_PORT" != "443" ] && echo ":${NGINX_SSL_PORT}")"
echo -e "Health:       https://${DOMAIN}/api/health"
echo -e "Сертификат:   /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
echo ""
echo -e "${YELLOW}Reality inbound:${NC}"
echo -e "  dest:        ${DOMAIN}:${NGINX_SSL_PORT}"
echo -e "  serverNames: ${DOMAIN}"
echo ""
echo -e "Скрипт завершён."
