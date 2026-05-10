#!/bin/bash
# ============================================
#  Selfsteal Installer (Caddy + Docker)
#  Поднимает fakesite на своём домене
#  для использования как Reality dest на 127.0.0.1:443
# ============================================
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

INSTALL_DIR="/opt/selfsteal"

err() { echo -e "${RED}[ERR]${NC} $*" >&2; }
ok()  { echo -e "${GREEN}[OK]${NC}  $*"; }
warn(){ echo -e "${YELLOW}[!]${NC}   $*"; }
info(){ echo -e "${BLUE}[i]${NC}   $*"; }

echo -e "${BLUE}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   Selfsteal Installer                            ║"
echo "║   Caddy + Docker fakesite для Reality            ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"

if [[ $EUID -ne 0 ]]; then
   err "Запусти от root."
   exit 1
fi

# === Ввод домена ===
echo ""
read -rp "Домен fakesite (например: cdn.example.com): " DOMAIN
if [[ -z "$DOMAIN" ]]; then
    err "Домен пустой."
    exit 1
fi

read -rp "Email для Let's Encrypt (по умолчанию admin@$DOMAIN): " EMAIL
EMAIL="${EMAIL:-admin@$DOMAIN}"

# === Зависимости ===
info "Проверяю зависимости..."

if ! command -v docker &>/dev/null; then
    info "Ставлю Docker..."
    curl -fsSL https://get.docker.com | sh
    systemctl enable --now docker
fi

if ! docker compose version &>/dev/null; then
    info "Ставлю Docker Compose plugin..."
    apt-get update -qq
    apt-get install -y docker-compose-plugin
fi

for pkg in curl dig openssl; do
    if ! command -v $pkg &>/dev/null; then
        apt-get install -y dnsutils curl openssl
        break
    fi
done

ok "Зависимости готовы."

# === DNS ===
info "Проверяю DNS для $DOMAIN..."
SERVER_IP=$(curl -s --max-time 5 -4 https://api.ipify.org)
RESOLVED=$(dig +short "$DOMAIN" A | sort -u)

echo "  IP сервера: $SERVER_IP"
echo "  A-записи домена:"
echo "$RESOLVED" | sed 's/^/    /'

if [[ -z "$RESOLVED" ]]; then
    err "У домена $DOMAIN нет A-записей. Настрой DNS и запусти снова."
    exit 1
fi

if ! echo "$RESOLVED" | grep -qx "$SERVER_IP"; then
    err "IP сервера ($SERVER_IP) не найден среди A-записей."
    exit 1
fi
ok "DNS ок."

# === Освобождение портов ===
info "Проверяю порты 80 и 443..."

stop_old() {
    if docker ps -a --format '{{.Names}}' | grep -qx selfsteal-caddy; then
        warn "Останавливаю старый контейнер selfsteal-caddy..."
        docker stop selfsteal-caddy 2>/dev/null || true
        docker rm selfsteal-caddy 2>/dev/null || true
    fi
    if systemctl is-active --quiet caddy 2>/dev/null; then
        warn "Останавливаю системный caddy.service..."
        systemctl stop caddy
        systemctl disable caddy 2>/dev/null || true
    fi
    if systemctl is-active --quiet nginx 2>/dev/null; then
        warn "Останавливаю системный nginx..."
        systemctl stop nginx
        systemctl disable nginx 2>/dev/null || true
    fi
}

if ss -tln | grep -qE ':(80|443)\s'; then
    stop_old
    sleep 2
    if ss -tln | grep -qE ':(80|443)\s'; then
        err "Порты 80/443 всё ещё заняты:"
        ss -tlnp | grep -E ':(80|443)\s'
        exit 1
    fi
fi
ok "Порты свободны."

# === Структура ===
info "Создаю $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"/{html,data,logs}
cd "$INSTALL_DIR"

# === Caddyfile ===
cat > Caddyfile << CADDY
{
    email $EMAIL
    http_port 80
    https_port 443
    storage file_system /data
}

$DOMAIN {
    root * /srv
    try_files {path} {path}.html {path}/index.html
    file_server

    @health path /api/health
    header @health Content-Type application/json
    respond @health \`{"status":"ok"}\`

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
        -Server
    }

    @static path *.css *.js *.jpg *.jpeg *.png *.gif *.ico *.woff *.woff2 *.svg
    header @static Cache-Control "public, max-age=2592000, immutable"

    encode gzip zstd

    log {
        output file /logs/access.log {
            roll_size 10mb
            roll_keep 5
        }
        format json
    }
}
CADDY

# === docker-compose.yml ===
cat > docker-compose.yml << 'COMPOSE'
services:
  caddy:
    image: caddy:2-alpine
    container_name: selfsteal-caddy
    restart: always
    network_mode: host
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./html:/srv:ro
      - ./data:/data
      - ./logs:/logs
    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:80"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
COMPOSE

# === .env ===
cat > .env << ENV
DOMAIN=$DOMAIN
EMAIL=$EMAIL
ENV

# === Минимальный fakesite ===
if [[ ! -f html/index.html ]]; then
    cat > html/index.html << 'HTML'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Edge Node</title>
<style>
body{font-family:-apple-system,sans-serif;max-width:600px;margin:80px auto;padding:0 20px;color:#333}
h1{font-size:1.8em}code{background:#f4f4f4;padding:2px 6px;border-radius:3px}
</style>
</head>
<body>
<h1>It works!</h1>
<p>Edge node online. Documentation: <code>/docs</code></p>
</body>
</html>
HTML
fi

ok "Конфигурация готова."

# === Запуск ===
info "Запускаю Caddy..."
docker compose up -d

echo ""
info "Жду выпуска сертификата (до 60 сек)..."
for i in {1..30}; do
    sleep 2
    if echo | openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" 2>/dev/null \
        | openssl x509 -noout -subject 2>/dev/null | grep -q "$DOMAIN"; then
        ok "Сертификат получен."
        break
    fi
    [[ $i -eq 30 ]] && warn "Серт ещё не получен, проверь логи: docker logs selfsteal-caddy"
done

# === Финал ===
echo ""
info "Проверка:"
echo | openssl s_client -connect 127.0.0.1:443 -servername "$DOMAIN" 2>/dev/null \
    | openssl x509 -noout -subject -dates 2>/dev/null | sed 's/^/  /'

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   ГОТОВО                         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "В XRay Reality инбаунде укажи:"
echo "  \"dest\": \"127.0.0.1:443\""
echo "  \"serverNames\": [\"$DOMAIN\"]"
echo ""
echo "Логи:    docker logs -f selfsteal-caddy"
echo "Рестарт: cd $INSTALL_DIR && docker compose restart"
echo "Стоп:    cd $INSTALL_DIR && docker compose down"
