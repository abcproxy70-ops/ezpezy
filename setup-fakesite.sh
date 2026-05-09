#!/bin/bash
set -e

# ============================================
#  Быстрая настройка nginx + SSL + фейксайт
#  Для использования с VLESS Reality (selfSNI)
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Настройка nginx + SSL + фейксайт${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# --- Ввод домена ---
read -rp "Введите домен (например, ru.example.com): " DOMAIN

if [[ -z "$DOMAIN" ]]; then
    echo -e "${RED}Домен не может быть пустым!${NC}"
    exit 1
fi

# --- Тематика ---
echo ""
echo -e "${YELLOW}Тематика фейксайта:${NC}"
echo "  1) SaaS / Cloud Platform"
echo "  2) DevOps / Admin panel"
echo "  3) CDN / Hosting landing"
echo "  4) Documentation / Tech blog"
echo "  5) Корпоративный IT"
echo "  6) Случайный"
read -rp "Выбор [6]: " THEME
THEME=${THEME:-6}

# --- Выбор порта для nginx SSL ---
echo ""
echo -e "${YELLOW}На каком порту поднять nginx с SSL (фейксайт)?${NC}"
echo -e "Этот порт будет указан как dest в Reality."
echo -e "Не указывайте порт, который уже занят Xray!"
echo ""
read -rp "Порт для nginx SSL [443]: " NGINX_SSL_PORT
NGINX_SSL_PORT=${NGINX_SSL_PORT:-443}

if ! [[ "$NGINX_SSL_PORT" =~ ^[0-9]+$ ]] || [[ "$NGINX_SSL_PORT" -lt 1 || "$NGINX_SSL_PORT" -gt 65535 ]]; then
    echo -e "${RED}Некорректный порт!${NC}"
    exit 1
fi

echo -e "${GREEN}nginx SSL будет на порту ${NGINX_SSL_PORT}${NC}"

# --- Проверка DNS ---
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

# --- Проверка портов ---
if ss -tuln | grep -q ":80 "; then
    echo -e "${RED}Порт 80 занят! Освободите порт и запустите снова.${NC}"
    exit 1
fi

if ss -tuln | grep -q ":${NGINX_SSL_PORT} "; then
    echo -e "${RED}Порт ${NGINX_SSL_PORT} занят! Выберите другой порт.${NC}"
    exit 1
fi

echo -e "${GREEN}Порты 80 и ${NGINX_SSL_PORT} свободны.${NC}"

# --- Установка пакетов ---
echo -e "\n${YELLOW}Устанавливаю nginx, certbot, git...${NC}"
apt update -qq
apt install -y -qq nginx certbot python3-certbot-nginx git unzip > /dev/null 2>&1
systemctl stop nginx 2>/dev/null || true
echo -e "${GREEN}Установлено.${NC}"

# --- SSL ---
echo -e "\n${YELLOW}Получаю SSL сертификат для ${DOMAIN}...${NC}"
certbot certonly --standalone --non-interactive --agree-tos \
    -m "admin@${DOMAIN}" \
    -d "$DOMAIN"

echo -e "${GREEN}Сертификат получен.${NC}"

# --- Шаблон ---
TEMPLATE_REPOS_TECH=(
    "https://github.com/StartBootstrap/startbootstrap-sb-admin-2"
    "https://github.com/StartBootstrap/startbootstrap-bare"
    "https://github.com/StartBootstrap/startbootstrap-landing-page"
    "https://github.com/StartBootstrap/startbootstrap-modern-business"
)
TEMPLATE_REPOS_DOCS=("https://github.com/StartBootstrap/startbootstrap-clean-blog")
TEMPLATE_REPOS_CORP=(
    "https://github.com/StartBootstrap/startbootstrap-modern-business"
    "https://github.com/StartBootstrap/startbootstrap-business-frontpage"
)

case "$THEME" in
    1|2) REPO="https://github.com/StartBootstrap/startbootstrap-sb-admin-2" ;;
    3) REPO="https://github.com/StartBootstrap/startbootstrap-landing-page" ;;
    4) REPO="${TEMPLATE_REPOS_DOCS[$RANDOM % ${#TEMPLATE_REPOS_DOCS[@]}]}" ;;
    5) REPO="${TEMPLATE_REPOS_CORP[$RANDOM % ${#TEMPLATE_REPOS_CORP[@]}]}" ;;
    6|*) REPO="${TEMPLATE_REPOS_TECH[$RANDOM % ${#TEMPLATE_REPOS_TECH[@]}]}" ;;
esac

echo -e "\n${YELLOW}Скачиваю шаблон: $(basename "$REPO")${NC}"
rm -rf /var/www/html/*
TEMP_DIR=$(mktemp -d)

git clone --depth 1 "$REPO" "$TEMP_DIR" 2>/dev/null || {
    REPO="https://github.com/StartBootstrap/startbootstrap-landing-page"
    git clone --depth 1 "$REPO" "$TEMP_DIR" 2>/dev/null
}

shopt -s dotglob
cp -r "$TEMP_DIR"/* /var/www/html/ 2>/dev/null || true
shopt -u dotglob
rm -rf /var/www/html/.git /var/www/html/.github /var/www/html/.gitignore /var/www/html/README.md 2>/dev/null || true
[[ -d /var/www/html/dist ]] && { mv /var/www/html/dist/* /var/www/html/ 2>/dev/null || true; }

if [[ ! -f /var/www/html/index.html ]]; then
    echo "<html><head><title>${DOMAIN}</title></head><body><h1>Welcome</h1></body></html>" > /var/www/html/index.html
fi

# --- Кастомизация под домен ---
DOMAIN_NAME=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)}')
DOMAIN_TITLE=$(echo "$DOMAIN_NAME" | sed 's/.*/\u&/')

find /var/www/html -type f \( -name "*.html" -o -name "*.htm" \) -exec sed -i \
    -e "s/Start Bootstrap/${DOMAIN_TITLE} Cloud/g" \
    -e "s/SB Admin/${DOMAIN_TITLE} Console/g" \
    -e "s|https://startbootstrap.com|https://${DOMAIN}|g" \
    -e "s/startbootstrap\.com/${DOMAIN}/g" \
    {} \; 2>/dev/null || true

# --- Маскировка: правдоподобная инфраструктура ---
CURRENT_DATE=$(date -u +"%Y-%m-%d")

cat > /var/www/html/robots.txt << EOF
User-agent: *
Disallow: /admin
Disallow: /api/internal
Allow: /
Sitemap: https://${DOMAIN}/sitemap.xml
EOF

cat > /var/www/html/sitemap.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://${DOMAIN}/</loc><lastmod>${CURRENT_DATE}</lastmod><priority>1.0</priority></url>
  <url><loc>https://${DOMAIN}/about</loc><lastmod>${CURRENT_DATE}</lastmod><priority>0.8</priority></url>
  <url><loc>https://${DOMAIN}/pricing</loc><lastmod>${CURRENT_DATE}</lastmod><priority>0.8</priority></url>
</urlset>
EOF

mkdir -p /var/www/html/api
cat > /var/www/html/api/health.json << EOF
{"status":"ok","service":"${DOMAIN_NAME}-api","version":"1.0.0"}
EOF

# Заглушки для /about, /pricing
for page in about pricing; do
    cat > /var/www/html/${page}.html << EOF
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<title>${page^} — ${DOMAIN_TITLE} Cloud</title></head>
<body><h1>${page^}</h1><p><a href="/">← Home</a></p></body></html>
EOF
done

rm -rf "$TEMP_DIR"

# --- Настройка nginx ---
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

    # Security headers
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

# --- Открытие порта в UFW (если активен) ---
if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    ufw allow 80/tcp > /dev/null 2>&1
    ufw allow ${NGINX_SSL_PORT}/tcp > /dev/null 2>&1
    echo -e "${GREEN}Порты 80 и ${NGINX_SSL_PORT} открыты в UFW.${NC}"
fi

# --- Проверка и запуск ---
nginx -t
systemctl start nginx
systemctl enable nginx

# --- Авто-renew с reload ---
RENEW_HOOK="/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh"
mkdir -p "$(dirname "$RENEW_HOOK")"
cat > "$RENEW_HOOK" << 'EOF'
#!/bin/bash
systemctl reload nginx
EOF
chmod +x "$RENEW_HOOK"

# --- Вывод результата ---
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Готово!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Сайт:         https://${DOMAIN}$([ "$NGINX_SSL_PORT" != "443" ] && echo ":${NGINX_SSL_PORT}")"
echo -e "Health:       https://${DOMAIN}/api/health"
echo -e "Шаблон:       $(basename "$REPO")"
echo -e "Сертификат:   /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
echo -e "Ключ:         /etc/letsencrypt/live/${DOMAIN}/privkey.pem"
echo ""
echo -e "${YELLOW}Настройки для Remnawave (Reality inbound):${NC}"
echo -e "  dest:        ${DOMAIN}:${NGINX_SSL_PORT}"
echo -e "  serverNames: ${DOMAIN}"
echo ""
echo -e "${GREEN}Порт 80            — nginx (редирект)${NC}"
echo -e "${GREEN}Порт ${NGINX_SSL_PORT}          — nginx (фейксайт SSL)${NC}"
echo ""
echo -e "Скрипт завершён."
