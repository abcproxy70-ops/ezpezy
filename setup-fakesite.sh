#!/bin/bash
set -e

# ============================================
#  Быстрая настройка nginx + SSL + фейксайт
#  Для использования с VLESS Reality (порт 8443)
#  Шаблон: learning-zone/website-templates
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
if ss -tuln | grep -q ":443 "; then
    echo -e "${RED}Порт 443 занят! Освободите порт и запустите снова.${NC}"
    exit 1
fi

if ss -tuln | grep -q ":80 "; then
    echo -e "${RED}Порт 80 занят! Освободите порт и запустите снова.${NC}"
    exit 1
fi

echo -e "${GREEN}Порты 80 и 443 свободны.${NC}"

# --- Установка пакетов ---
echo -e "\n${YELLOW}Устанавливаю nginx, certbot, git...${NC}"
apt update -qq
apt install -y -qq nginx certbot python3-certbot-nginx git unzip > /dev/null 2>&1
systemctl stop nginx 2>/dev/null || true
echo -e "${GREEN}Установлено.${NC}"

# --- Получение SSL сертификата ---
echo -e "\n${YELLOW}Получаю SSL сертификат для ${DOMAIN}...${NC}"
certbot certonly --standalone --non-interactive --agree-tos \
    -m "admin@${DOMAIN}" \
    -d "$DOMAIN"

echo -e "${GREEN}Сертификат получен.${NC}"

# --- Скачивание шаблона сайта ---
echo -e "\n${YELLOW}Скачиваю шаблон сайта...${NC}"
rm -rf /var/www/html/*

TEMP_DIR=$(mktemp -d)
git clone --depth 1 https://github.com/learning-zone/website-templates.git "$TEMP_DIR" 2>/dev/null

# Выбор случайного шаблона
SITE_DIR=$(find "$TEMP_DIR" -mindepth 1 -maxdepth 1 -type d ! -name ".git" | shuf -n 1)

if [[ -d "$SITE_DIR" ]]; then
    cp -r "$SITE_DIR"/* /var/www/html/
    TEMPLATE_NAME=$(basename "$SITE_DIR")
    echo -e "${GREEN}Шаблон установлен: ${TEMPLATE_NAME}${NC}"
else
    echo -e "${YELLOW}Не удалось скачать шаблон, создаю простую страницу...${NC}"
    echo "<html><head><title>${DOMAIN}</title></head><body><h1>Welcome</h1></body></html>" > /var/www/html/index.html
fi

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
    listen 443 ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers on;

    location / {
        root /var/www/html;
        index index.html;
    }
}
NGINX

# --- Проверка и запуск ---
nginx -t
systemctl start nginx
systemctl enable nginx

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN} Готово!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "Сайт:         https://${DOMAIN}"
echo -e "Сертификат:   /etc/letsencrypt/live/${DOMAIN}/fullchain.pem"
echo -e "Ключ:         /etc/letsencrypt/live/${DOMAIN}/privkey.pem"
echo ""
echo -e "${YELLOW}Настройки для Remnawave (Reality inbound):${NC}"
echo -e "  dest:        ${DOMAIN}:443"
echo -e "  serverNames: ${DOMAIN}"
echo ""
echo -e "${GREEN}Порт 443 — nginx (фейксайт)${NC}"
echo -e "${GREEN}Порт 8443 — Xray (Reality)${NC}"
echo ""
echo -e "Скрипт завершён."
