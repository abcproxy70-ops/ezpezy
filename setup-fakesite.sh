#!/bin/bash
set -e

# ============================================
#  Быстрая настройка Caddy + фейксайт
#  Status page (maintenance) для VLESS Reality
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Настройка Caddy + status page${NC}"
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
echo -e "${YELLOW}На каком порту поднять Caddy с SSL (фейксайт)?${NC}"
echo -e "Этот порт будет указан как dest в Reality."
echo -e "Не указывайте порт, который уже занят Xray!"
echo ""
read -rp "Порт для Caddy SSL [443]: " CADDY_SSL_PORT
CADDY_SSL_PORT=${CADDY_SSL_PORT:-443}

if ! [[ "$CADDY_SSL_PORT" =~ ^[0-9]+$ ]] || [[ "$CADDY_SSL_PORT" -lt 1 || "$CADDY_SSL_PORT" -gt 65535 ]]; then
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
# 80 нужен для ACME HTTP-01 challenge
if ss -tuln | grep -q ":80 "; then
    echo -e "${RED}Порт 80 занят! Caddy нужен 80 для получения SSL.${NC}"
    exit 1
fi
if ss -tuln | grep -q ":${CADDY_SSL_PORT} "; then
    echo -e "${RED}Порт ${CADDY_SSL_PORT} занят!${NC}"
    exit 1
fi
echo -e "${GREEN}Порты свободны.${NC}"

# --- Удаляем nginx если стоит (конфликт за порты) ---
if systemctl is-active --quiet nginx 2>/dev/null; then
    echo -e "${YELLOW}Останавливаю nginx (будет конфликт с Caddy)...${NC}"
    systemctl stop nginx
    systemctl disable nginx 2>/dev/null || true
fi

# --- Установка Caddy ---
echo -e "\n${YELLOW}Устанавливаю Caddy...${NC}"
apt update -qq
apt install -y -qq debian-keyring debian-archive-keyring apt-transport-https curl > /dev/null 2>&1

# Официальный репозиторий Caddy
if [[ ! -f /etc/apt/sources.list.d/caddy-stable.list ]]; then
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg 2>/dev/null
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list > /dev/null
    apt update -qq
fi

apt install -y -qq caddy > /dev/null 2>&1
systemctl stop caddy 2>/dev/null || true
echo -e "${GREEN}Caddy установлен.${NC}"

# --- Извлекаем имя из домена для брендинга ---
DOMAIN_NAME=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)}')
DOMAIN_TITLE=$(echo "$DOMAIN_NAME" | sed 's/.*/\u&/')
CURRENT_YEAR=$(date +"%Y")
CURRENT_DATE=$(date -u +"%Y-%m-%d")

# --- Каталог сайта ---
WEB_ROOT="/var/www/html"
mkdir -p "$WEB_ROOT"
rm -rf "$WEB_ROOT"/*

# --- Status page ---
echo -e "\n${YELLOW}Создаю status page...${NC}"

cat > "$WEB_ROOT/index.html" << HTML
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
    cat > "$WEB_ROOT/${page}.html" << EOF
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>${page^} — ${DOMAIN_TITLE} Cloud</title>
<style>body{font-family:-apple-system,sans-serif;background:#0f1419;color:#e6e6e6;max-width:720px;margin:80px auto;padding:24px;line-height:1.6}a{color:#60a5fa}</style>
</head>
<body><h1>${page^}</h1><p>This page is currently unavailable due to scheduled maintenance.</p>
<p><a href="/">← Back to status page</a></p></body></html>
EOF
done

# --- robots.txt ---
cat > "$WEB_ROOT/robots.txt" << EOF
User-agent: *
Disallow: /admin
Disallow: /api/internal
Allow: /
Sitemap: https://${DOMAIN}/sitemap.xml
EOF

# --- sitemap.xml ---
cat > "$WEB_ROOT/sitemap.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://${DOMAIN}/</loc><lastmod>${CURRENT_DATE}</lastmod><priority>1.0</priority></url>
  <url><loc>https://${DOMAIN}/privacy</loc><lastmod>${CURRENT_DATE}</lastmod><priority>0.5</priority></url>
  <url><loc>https://${DOMAIN}/terms</loc><lastmod>${CURRENT_DATE}</lastmod><priority>0.5</priority></url>
</urlset>
EOF

# --- Health endpoint ---
mkdir -p "$WEB_ROOT/api"
cat > "$WEB_ROOT/api/health" << EOF
{"status":"maintenance","service":"${DOMAIN_NAME}-api","version":"1.0.0","message":"Scheduled maintenance in progress"}
EOF

# Права для Caddy
chown -R caddy:caddy "$WEB_ROOT" 2>/dev/null || true

echo -e "${GREEN}Status page готов.${NC}"

# --- Caddyfile ---
echo -e "\n${YELLOW}Настраиваю Caddy...${NC}"

# Если порт не 443 — отключаем авто-редирект и используем TLS-ALPN-01 не получится,
# поэтому для нестандартного порта используем HTTP-challenge через 80
if [[ "$CADDY_SSL_PORT" == "443" ]]; then
    SITE_ADDR="${DOMAIN}"
else
    SITE_ADDR="${DOMAIN}:${CADDY_SSL_PORT}"
fi

cat > /etc/caddy/Caddyfile << CADDY
{
    # Email для Let's Encrypt
    email admin@${DOMAIN}
    # HTTP-challenge через 80 порт (работает и для нестандартных SSL-портов)
    http_port 80
    https_port ${CADDY_SSL_PORT}
}

${SITE_ADDR} {
    root * ${WEB_ROOT}
    file_server

    # Health endpoint отдаёт JSON
    @health path /api/health
    header @health Content-Type application/json

    # Security headers (Caddy автоматом добавляет HSTS — не дублируем)
    header {
        X-Frame-Options SAMEORIGIN
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
        -Server
    }

    # Кэш статики
    @static path *.css *.js *.jpg *.jpeg *.png *.gif *.ico *.woff *.woff2 *.svg
    header @static Cache-Control "public, max-age=2592000, immutable"

    encode gzip zstd
}
CADDY

# --- UFW ---
if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow ${CADDY_SSL_PORT}/tcp > /dev/null 2>&1
    echo -e "${GREEN}Порты 80 и ${CADDY_SSL_PORT} открыты в UFW.${NC}"
fi

# --- Проверка конфига и запуск ---
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl restart caddy
systemctl enable caddy > /dev/null 2>&1

# Ждём пока Caddy получит сертификат (несколько секунд)
echo -e "\n${YELLOW}Жду получения SSL сертификата от Caddy...${NC}"
for i in {1..30}; do
    if curl -sk --max-time 3 "https://${DOMAIN}:${CADDY_SSL_PORT}" -o /dev/null 2>&1; then
        echo -e "${GREEN}Сертификат получен.${NC}"
        break
    fi
    sleep 2
done

# --- Результат ---
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Готово!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Сайт:         https://${DOMAIN}$([ "$CADDY_SSL_PORT" != "443" ] && echo ":${CADDY_SSL_PORT}")"
echo -e "Health:       https://${DOMAIN}$([ "$CADDY_SSL_PORT" != "443" ] && echo ":${CADDY_SSL_PORT}")/api/health"
echo -e "Caddyfile:    /etc/caddy/Caddyfile"
echo -e "Сертификаты:  /var/lib/caddy/.local/share/caddy/certificates/ (управляет Caddy сам)"
echo ""
echo -e "${YELLOW}Reality inbound:${NC}"
echo -e "  dest:        ${DOMAIN}:${CADDY_SSL_PORT}"
echo -e "  serverNames: ${DOMAIN}"
echo ""
echo -e "${GREEN}Управление:${NC}"
echo -e "  systemctl status caddy   — статус"
echo -e "  systemctl reload caddy   — применить изменения Caddyfile"
echo -e "  journalctl -u caddy -f   — логи"
echo ""
echo -e "Скрипт завершён."
