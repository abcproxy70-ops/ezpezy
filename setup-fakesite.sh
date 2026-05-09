#!/bin/bash
set -e

# ============================================
#  nginx + SSL + фейксайт (tech-стиль)
#  Для VLESS Reality (selfSNI)
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Настройка nginx + SSL + tech-фейксайт${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

# --- Ввод домена ---
read -rp "Введите домен (например, ru.example.com): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}Домен не может быть пустым!${NC}"; exit 1; }

# --- Выбор тематики ---
echo ""
echo -e "${YELLOW}Выберите тематику фейксайта:${NC}"
echo "  1) SaaS / Cloud Platform (API, dashboard)"
echo "  2) DevOps / Monitoring (status page)"
echo "  3) CDN / Hosting (landing)"
echo "  4) Documentation / Tech blog"
echo "  5) Корпоративный (consulting/IT)"
echo "  6) Случайный из tech-категорий"
read -rp "Тематика [6]: " THEME
THEME=${THEME:-6}

# --- Порт ---
echo ""
read -rp "Порт для nginx SSL [443]: " NGINX_SSL_PORT
NGINX_SSL_PORT=${NGINX_SSL_PORT:-443}

if ! [[ "$NGINX_SSL_PORT" =~ ^[0-9]+$ ]] || [[ "$NGINX_SSL_PORT" -lt 1 || "$NGINX_SSL_PORT" -gt 65535 ]]; then
    echo -e "${RED}Некорректный порт!${NC}"
    exit 1
fi

# --- DNS ---
echo -e "\n${YELLOW}Проверяю DNS...${NC}"
SERVER_IP=$(curl -s --max-time 5 -4 https://api.ipify.org)
DOMAIN_IP=$(dig +short "$DOMAIN" A | tail -1)
echo "IP сервера:  $SERVER_IP"
echo "IP домена:   $DOMAIN_IP"
[[ "$SERVER_IP" != "$DOMAIN_IP" ]] && { echo -e "${RED}A-запись не совпадает!${NC}"; exit 1; }
echo -e "${GREEN}DNS ок.${NC}"

# --- Порты ---
ss -tuln | grep -q ":80 " && { echo -e "${RED}Порт 80 занят!${NC}"; exit 1; }
ss -tuln | grep -q ":${NGINX_SSL_PORT} " && { echo -e "${RED}Порт ${NGINX_SSL_PORT} занят!${NC}"; exit 1; }
echo -e "${GREEN}Порты свободны.${NC}"

# --- Установка ---
echo -e "\n${YELLOW}Устанавливаю пакеты...${NC}"
apt update -qq
apt install -y -qq nginx certbot python3-certbot-nginx git unzip curl > /dev/null 2>&1
systemctl stop nginx 2>/dev/null || true

# --- SSL ---
echo -e "\n${YELLOW}Получаю SSL...${NC}"
certbot certonly --standalone --non-interactive --agree-tos \
    -m "admin@${DOMAIN}" -d "$DOMAIN"
echo -e "${GREEN}Сертификат получен.${NC}"

# --- Курируемые tech-шаблоны ---
# Подобраны репы с подходящими IT/SaaS лендингами
declare -A TEMPLATES_SAAS=(
    ["cruip-tailwind-landing"]="https://github.com/cruip/open-react-template"
    ["tailwindcss-startup"]="https://github.com/cruip/tailwind-landing-page-template"
)

# Готовые HTML-шаблоны (без сборки)
TEMPLATE_REPOS_TECH=(
    "https://github.com/StartBootstrap/startbootstrap-sb-admin-2"
    "https://github.com/StartBootstrap/startbootstrap-bare"
    "https://github.com/StartBootstrap/startbootstrap-landing-page"
    "https://github.com/StartBootstrap/startbootstrap-modern-business"
    "https://github.com/StartBootstrap/startbootstrap-clean-blog"
)

TEMPLATE_REPOS_DOCS=(
    "https://github.com/StartBootstrap/startbootstrap-clean-blog"
)

TEMPLATE_REPOS_CORP=(
    "https://github.com/StartBootstrap/startbootstrap-modern-business"
    "https://github.com/StartBootstrap/startbootstrap-business-frontpage"
    "https://github.com/StartBootstrap/startbootstrap-business-casual"
)

# --- Скачивание шаблона ---
echo -e "\n${YELLOW}Скачиваю шаблон...${NC}"
rm -rf /var/www/html/*
TEMP_DIR=$(mktemp -d)

case "$THEME" in
    1) REPO="https://github.com/StartBootstrap/startbootstrap-sb-admin-2" ;;
    2) REPO="https://github.com/StartBootstrap/startbootstrap-sb-admin-2" ;;
    3) REPO="https://github.com/StartBootstrap/startbootstrap-landing-page" ;;
    4) REPO="${TEMPLATE_REPOS_DOCS[$RANDOM % ${#TEMPLATE_REPOS_DOCS[@]}]}" ;;
    5) REPO="${TEMPLATE_REPOS_CORP[$RANDOM % ${#TEMPLATE_REPOS_CORP[@]}]}" ;;
    6|*) REPO="${TEMPLATE_REPOS_TECH[$RANDOM % ${#TEMPLATE_REPOS_TECH[@]}]}" ;;
esac

echo "Репозиторий: $REPO"
git clone --depth 1 "$REPO" "$TEMP_DIR" 2>/dev/null || {
    echo -e "${YELLOW}Не удалось склонировать, пробую запасной вариант${NC}"
    REPO="https://github.com/StartBootstrap/startbootstrap-landing-page"
    git clone --depth 1 "$REPO" "$TEMP_DIR" 2>/dev/null
}

# Копируем содержимое (без .git и служебных файлов)
shopt -s dotglob
cp -r "$TEMP_DIR"/* /var/www/html/ 2>/dev/null || true
shopt -u dotglob
rm -rf /var/www/html/.git /var/www/html/.github /var/www/html/.gitignore 2>/dev/null || true

# Если есть dist/ — используем его
if [[ -d /var/www/html/dist ]]; then
    mv /var/www/html/dist/* /var/www/html/ 2>/dev/null || true
fi

# Проверяем наличие index.html
if [[ ! -f /var/www/html/index.html ]]; then
    echo -e "${YELLOW}index.html не найден, создаю заглушку${NC}"
    cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html><head><title>Cloud Platform</title></head>
<body><h1>Service is running</h1></body></html>
EOF
fi

# --- Кастомизация: подменяем заголовки и тексты под домен ---
echo -e "${YELLOW}Кастомизирую под домен...${NC}"
DOMAIN_NAME=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)}')
DOMAIN_TITLE=$(echo "$DOMAIN_NAME" | sed 's/.*/\u&/')

# Заменяем самые палевные строки шаблонов на нейтральные
find /var/www/html -type f \( -name "*.html" -o -name "*.htm" \) -exec sed -i \
    -e "s/Start Bootstrap/${DOMAIN_TITLE} Cloud/g" \
    -e "s/SB Admin/${DOMAIN_TITLE} Console/g" \
    -e "s|https://startbootstrap.com|https://${DOMAIN}|g" \
    -e "s/startbootstrap\.com/${DOMAIN}/g" \
    {} \; 2>/dev/null || true

# Robots.txt — запретить индексацию
cat > /var/www/html/robots.txt << EOF
User-agent: *
Disallow: /
EOF

rm -rf "$TEMP_DIR"
echo -e "${GREEN}Шаблон установлен.${NC}"

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
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305;
    ssl_prefer_server_ciphers on;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;

    # Реалистичные заголовки tech-сайта
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Strict-Transport-Security "max-age=31536000" always;

    # Скрываем версию nginx
    server_tokens off;

    root /var/www/html;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Кэш статики
    location ~* \.(jpg|jpeg|png|gif|ico|css|js|woff|woff2|ttf|svg)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
    }

    # Скрываем доступ к скрытым файлам
    location ~ /\. {
        deny all;
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
systemctl enable nginx > /dev/null 2>&1

# --- Авто-обновление сертификата ---
(crontab -l 2>/dev/null | grep -v certbot; echo "0 3 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -

# --- Результат ---
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Готово!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Сайт:         https://${DOMAIN}$([ "$NGINX_SSL_PORT" != "443" ] && echo ":${NGINX_SSL_PORT}")"
echo -e "Шаблон:       $(basename "$REPO")"
echo ""
echo -e "${YELLOW}Reality inbound:${NC}"
echo -e "  dest:        ${DOMAIN}:${NGINX_SSL_PORT}"
echo -e "  serverNames: ${DOMAIN}"
echo ""
