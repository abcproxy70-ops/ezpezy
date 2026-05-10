#!/bin/bash
# ╔═════════════════════════════════════════════════════════════╗
# ║  Selfsteal v3 — Reality traffic masking                    ║
# ║  Docker Caddy + reverse-proxy на реальные сайты            ║
# ║  Лучше DigneZzZ: умная маскировка через настоящий контент  ║
# ╚═════════════════════════════════════════════════════════════╝

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
NC='\033[0m'

APP_DIR="/opt/selfsteal"
HTML_DIR="$APP_DIR/html"
LOG_DIR="$APP_DIR/logs"
CADDY_DATA_DIR="$APP_DIR/data"
BIN_PATH="/usr/local/bin/selfsteal"
SCRIPT_VERSION="3.0"

err() { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }
ok()  { echo -e "${GREEN}✓ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠ $1${NC}"; }
info(){ echo -e "${CYAN}→ $1${NC}"; }

banner() {
    echo -e "${CYAN}╔═════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Selfsteal v${SCRIPT_VERSION}${NC} — Reality fakesite                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Docker Caddy + reverse-proxy + offline шаблоны             ${CYAN}║${NC}"
    echo -e "${CYAN}╚═════════════════════════════════════════════════════════════╝${NC}"
}

require_root() {
    [[ $EUID -eq 0 ]] || err "Запусти от root (sudo bash $0)"
}

install_docker_if_needed() {
    if command -v docker &>/dev/null && docker compose version &>/dev/null; then
        ok "Docker уже установлен"
        return
    fi
    info "Устанавливаю Docker..."
    curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
    systemctl enable --now docker > /dev/null 2>&1
    ok "Docker установлен"
}

check_dns() {
    local domain=$1
    local server_ip=$(curl -s --max-time 5 -4 https://api.ipify.org 2>/dev/null || curl -s --max-time 5 -4 https://ifconfig.me 2>/dev/null)
    local domain_ip=$(dig +short A "$domain" @1.1.1.1 2>/dev/null | tail -1)

    [[ -z "$server_ip" ]] && err "Не могу определить IP сервера"
    [[ -z "$domain_ip" ]] && err "DNS A-записи для $domain не найдено"

    echo "  IP сервера: $server_ip"
    echo "  IP домена:  $domain_ip"
    [[ "$server_ip" != "$domain_ip" ]] && err "DNS не указывает на этот сервер"
    ok "DNS корректный"
}

check_ports() {
    local port=$1
    if ss -tuln 2>/dev/null | grep -qE ":(80|${port}) "; then
        local who=$(ss -tlnp 2>/dev/null | grep -E ":(80|${port}) " | awk '{print $NF}' | head -1)
        warn "Порт 80 или $port занят: $who"
        read -rp "Остановить занявший процесс? [y/N]: " stop
        if [[ "$stop" =~ ^[Yy]$ ]]; then
            systemctl stop nginx caddy apache2 2>/dev/null || true
            sleep 1
            ss -tuln 2>/dev/null | grep -qE ":(80|${port}) " && err "Порт всё ещё занят, разберись вручную"
        else
            err "Освободи порты и запусти скрипт снова"
        fi
    fi
    ok "Порты 80 и $port свободны"
}

# Каталог шаблонов с реальными сайтами для proxy + fallback HTML
get_template_list() {
cat << 'TEMPLATES'
1|MDN Web Docs|developer.mozilla.org|Документация для веб-разработчиков
2|Linux Kernel Archives|www.kernel.org|Зеркало kernel.org
3|Project Gutenberg|www.gutenberg.org|Бесплатная библиотека книг
4|Apache Foundation|www.apache.org|Open-source софт фонд
5|Debian|www.debian.org|Debian Linux
6|Wikipedia (RU)|ru.wikipedia.org|Википедия (опасно — заметят)
7|Custom — свой URL|custom|Введи свой источник для proxy
8|Static SaaS лендинг|local|Без proxy, локальный HTML
9|Static API Docs|local|Без proxy, локальный HTML
10|Static Status Page|local|Без proxy, локальный HTML
TEMPLATES
}

choose_template() {
    echo ""
    echo -e "${YELLOW}Выберите шаблон fakesite:${NC}"
    echo ""
    echo -e "  ${GRAY}=== Reverse-proxy на реальные сайты (лучшая маскировка) ===${NC}"
    get_template_list | while IFS='|' read -r id name host desc; do
        if [[ "$host" != "local" && "$id" != "7" ]]; then
            printf "  ${BLUE}%2s)${NC} %-25s ${GRAY}— %s${NC}\n" "$id" "$name" "$desc"
        fi
    done
    echo ""
    echo -e "  ${GRAY}=== Кастомные ===${NC}"
    printf "  ${BLUE}%2s)${NC} %-25s ${GRAY}— %s${NC}\n" "7" "Custom URL" "Свой URL для reverse-proxy"
    echo ""
    echo -e "  ${GRAY}=== Локальные шаблоны (без интернета) ===${NC}"
    printf "  ${BLUE}%2s)${NC} %-25s ${GRAY}— %s${NC}\n" "8" "SaaS лендинг" "Продукт + pricing"
    printf "  ${BLUE}%2s)${NC} %-25s ${GRAY}— %s${NC}\n" "9" "API Docs" "Документация"
    printf "  ${BLUE}%2s)${NC} %-25s ${GRAY}— %s${NC}\n" "10" "Status Page" "Системный статус"
    echo ""
    read -rp "Шаблон [1]: " TEMPLATE
    TEMPLATE=${TEMPLATE:-1}

    case "$TEMPLATE" in
        1) PROXY_TARGET="https://developer.mozilla.org"; TEMPLATE_NAME="MDN Web Docs" ;;
        2) PROXY_TARGET="https://www.kernel.org"; TEMPLATE_NAME="Linux Kernel" ;;
        3) PROXY_TARGET="https://www.gutenberg.org"; TEMPLATE_NAME="Project Gutenberg" ;;
        4) PROXY_TARGET="https://www.apache.org"; TEMPLATE_NAME="Apache Foundation" ;;
        5) PROXY_TARGET="https://www.debian.org"; TEMPLATE_NAME="Debian" ;;
        6) PROXY_TARGET="https://ru.wikipedia.org"; TEMPLATE_NAME="Wikipedia"
           warn "Wikipedia может палиться — РКН следит за wiki-доменами"
           ;;
        7)
            read -rp "Введи URL для reverse-proxy (https://example.com): " PROXY_TARGET
            [[ -z "$PROXY_TARGET" || "$PROXY_TARGET" != http* ]] && err "Некорректный URL"
            TEMPLATE_NAME="Custom: $PROXY_TARGET"
            ;;
        8) PROXY_TARGET="local-saas"; TEMPLATE_NAME="SaaS лендинг" ;;
        9) PROXY_TARGET="local-docs"; TEMPLATE_NAME="API Docs" ;;
        10) PROXY_TARGET="local-status"; TEMPLATE_NAME="Status Page" ;;
        *) err "Некорректный выбор" ;;
    esac
}

generate_brand() {
    local domain=$1
    local hash=$(echo -n "$domain" | md5sum | cut -c1-2)
    local products=("Nimbus" "Helix" "Vortex" "Quanta" "Lumina" "Stellar" "Cobalt" "Drift" "Pulse" "Forge" "Axiom" "Beacon" "Cipher" "Delta" "Echo" "Falcon")
    local idx=$((16#${hash} % 16))
    echo "${products[$idx]}"
}

build_local_saas() {
    local title=$1
    local domain=$2
    local year=$(date +%Y)
    cat > "$HTML_DIR/index.html" << HTML
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>${title} — Modern infrastructure for developers</title>
<meta name="description" content="${title} provides reliable cloud infrastructure and developer tools.">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><rect x='10' y='10' width='80' height='80' rx='20' fill='%236366f1'/></svg>">
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;background:#0a0a0f;color:#e6e6e6;line-height:1.6}nav{position:sticky;top:0;background:rgba(10,10,15,.85);backdrop-filter:blur(10px);border-bottom:1px solid #1f2937;padding:16px 0}.nav-inner{max-width:1200px;margin:0 auto;padding:0 24px;display:flex;justify-content:space-between;align-items:center}.brand{display:flex;align-items:center;gap:10px;font-weight:700;font-size:18px}.brand-mark{width:28px;height:28px;border-radius:6px;background:linear-gradient(135deg,#6366f1,#8b5cf6)}.nav-links{display:flex;gap:32px;font-size:14px}.nav-links a{color:#9ca3af;text-decoration:none}.nav-links a:hover{color:#fff}.btn{display:inline-block;padding:10px 20px;border-radius:8px;text-decoration:none;font-weight:500;font-size:14px}.btn-primary{background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff}.btn-ghost{color:#e6e6e6;border:1px solid #374151}.hero{max-width:900px;margin:0 auto;padding:100px 24px 80px;text-align:center}.badge{display:inline-block;padding:6px 14px;border-radius:999px;background:rgba(99,102,241,.1);color:#a5b4fc;font-size:13px;margin-bottom:24px;border:1px solid rgba(99,102,241,.3)}h1{font-size:56px;font-weight:800;line-height:1.1;margin-bottom:24px;letter-spacing:-1.5px;background:linear-gradient(135deg,#fff,#9ca3af);-webkit-background-clip:text;-webkit-text-fill-color:transparent}.hero-sub{font-size:20px;color:#9ca3af;max-width:640px;margin:0 auto 40px}.hero-cta{display:flex;gap:16px;justify-content:center;flex-wrap:wrap}.features{max-width:1200px;margin:0 auto;padding:80px 24px;display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}.feature{padding:32px;background:#11131a;border:1px solid #1f2937;border-radius:16px}.feature-icon{width:48px;height:48px;border-radius:12px;background:rgba(99,102,241,.1);display:flex;align-items:center;justify-content:center;margin-bottom:20px;font-size:24px}.feature h3{font-size:20px;margin-bottom:12px}.feature p{color:#9ca3af;font-size:15px}footer{border-top:1px solid #1f2937;padding:40px 24px;color:#6b7280;font-size:14px;text-align:center}@media(max-width:640px){h1{font-size:36px}.nav-links{display:none}}</style>
</head><body>
<nav><div class="nav-inner"><div class="brand"><div class="brand-mark"></div><span>${title}</span></div><div class="nav-links"><a href="/features">Features</a><a href="/pricing">Pricing</a><a href="/docs">Docs</a><a href="/blog">Blog</a></div><a href="/signin" class="btn btn-ghost">Sign in</a></div></nav>
<section class="hero"><div class="badge">★ New: Edge functions in beta</div><h1>Build. Deploy.<br>Scale instantly.</h1><p class="hero-sub">${title} is a developer-first platform for shipping production apps without managing infrastructure.</p><div class="hero-cta"><a href="/signup" class="btn btn-primary">Start free trial</a><a href="/docs" class="btn btn-ghost">Read the docs</a></div></section>
<section class="features"><div class="feature"><div class="feature-icon">⚡</div><h3>Edge runtime</h3><p>Run code in 280+ regions worldwide.</p></div><div class="feature"><div class="feature-icon">🔒</div><h3>Built-in security</h3><p>DDoS protection, WAF, and TLS by default.</p></div><div class="feature"><div class="feature-icon">📊</div><h3>Real-time metrics</h3><p>Trace requests across services.</p></div><div class="feature"><div class="feature-icon">🚀</div><h3>Git-driven</h3><p>Push to deploy. Preview branches.</p></div><div class="feature"><div class="feature-icon">🔧</div><h3>Powerful CLI</h3><p>First-class TypeScript support.</p></div><div class="feature"><div class="feature-icon">💼</div><h3>Team collaboration</h3><p>SSO/SAML, audit logs, RBAC.</p></div></section>
<footer>© ${year} ${title}. All rights reserved.</footer></body></html>
HTML
    for p in features pricing docs blog signin signup contact; do
        cat > "$HTML_DIR/${p}.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${p^} — ${title}</title><style>body{font-family:-apple-system,sans-serif;background:#0a0a0f;color:#e6e6e6;max-width:760px;margin:80px auto;padding:24px;line-height:1.7}a{color:#a5b4fc}</style></head><body><h1>${p^}</h1><p>This section is being updated.</p><p><a href="/">← Home</a></p></body></html>
EOF
    done
}

build_local_docs() {
    local title=$1
    local domain=$2
    local date=$(date -u +"%Y-%m-%d")
    cat > "$HTML_DIR/index.html" << HTML
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>${title} API Reference — Documentation</title>
<meta name="description" content="${title} REST API documentation.">
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#fafbfc;color:#1a1f2e;line-height:1.6;font-size:15px}.layout{display:flex;min-height:100vh}.sidebar{width:280px;background:#fff;border-right:1px solid #e5e7eb;padding:24px 0;position:sticky;top:0;height:100vh;overflow-y:auto}.sidebar-brand{padding:0 24px 24px;border-bottom:1px solid #e5e7eb;display:flex;align-items:center;gap:10px;font-weight:700;font-size:17px}.sidebar-brand-mark{width:28px;height:28px;border-radius:6px;background:linear-gradient(135deg,#10b981,#059669)}.sidebar h4{padding:20px 24px 8px;font-size:11px;color:#6b7280;text-transform:uppercase;letter-spacing:1px}.sidebar a{display:block;padding:7px 24px;color:#4b5563;text-decoration:none;font-size:14px}.sidebar a.active{background:#ecfdf5;color:#059669;font-weight:500}.content{flex:1;padding:48px 60px;max-width:900px}.breadcrumb{color:#6b7280;font-size:13px;margin-bottom:16px}h1{font-size:36px;font-weight:700;margin-bottom:16px}h2{font-size:24px;font-weight:700;margin:40px 0 16px;padding-top:16px;border-top:1px solid #e5e7eb}p{margin-bottom:16px;color:#374151}code{background:#f3f4f6;padding:2px 6px;border-radius:4px;font-family:monospace;color:#be185d}pre{background:#0d1117;color:#e6edf3;padding:20px;border-radius:8px;overflow-x:auto;margin:16px 0}.method{display:inline-block;padding:3px 10px;border-radius:4px;font-size:12px;font-weight:700;font-family:monospace}.method.get{background:#dbeafe;color:#1e40af}.method.post{background:#dcfce7;color:#166534}.endpoint{background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:16px;margin:12px 0;font-family:monospace}@media(max-width:768px){.sidebar{display:none}.content{padding:32px 24px}}</style>
</head><body><div class="layout"><aside class="sidebar"><div class="sidebar-brand"><div class="sidebar-brand-mark"></div>${title} Docs</div><h4>Getting started</h4><a href="/" class="active">Introduction</a><a href="/quickstart">Quickstart</a><a href="/authentication">Authentication</a><h4>API Reference</h4><a href="/api/users">Users</a><a href="/api/projects">Projects</a><a href="/api/deployments">Deployments</a></aside><main class="content"><div class="breadcrumb">Docs › Getting started</div><h1>Introduction</h1><p>${title} provides a REST API to manage your projects programmatically.</p><h2>Base URL</h2><pre><code>https://api.${domain}/v1</code></pre><h2>Authentication</h2><p>The API uses bearer tokens:</p><pre><code>curl https://api.${domain}/v1/projects \\
  -H "Authorization: Bearer \$TOKEN"</code></pre><h2>Resources</h2><div class="endpoint"><span class="method get">GET</span> /v1/projects</div><div class="endpoint"><span class="method post">POST</span> /v1/projects</div></main></div></body></html>
HTML
    for p in quickstart authentication; do
        cat > "$HTML_DIR/${p}.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${p^} — ${title}</title><style>body{font-family:sans-serif;background:#fafbfc;max-width:760px;margin:60px auto;padding:24px;line-height:1.7}a{color:#10b981}</style></head><body><h1>${p^}</h1><p>Documentation under update.</p><p><a href="/">← Back</a></p></body></html>
EOF
    done
}

build_local_status() {
    local title=$1
    local year=$(date +%Y)
    cat > "$HTML_DIR/index.html" << HTML
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>${title} — System Status</title>
<style>*{margin:0;padding:0;box-sizing:border-box}body{font-family:-apple-system,sans-serif;background:#f5f7fa;color:#1a1f2e;min-height:100vh;line-height:1.6}.container{max-width:780px;margin:0 auto;padding:48px 24px}.brand{display:flex;align-items:center;gap:10px;font-weight:700;font-size:18px;margin-bottom:40px}.brand-mark{width:32px;height:32px;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669)}.banner{background:linear-gradient(135deg,#10b981,#059669);color:#fff;padding:24px 28px;border-radius:12px;margin-bottom:32px;display:flex;align-items:center;gap:16px}.dot{width:14px;height:14px;border-radius:50%;background:#fff;animation:p 2s infinite}@keyframes p{0%,100%{opacity:1}50%{opacity:.5}}.card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:24px;margin-bottom:16px}.card h3{font-size:14px;color:#6b7280;text-transform:uppercase;letter-spacing:1px;margin-bottom:16px}.row{display:flex;justify-content:space-between;align-items:center;padding:12px 0;border-bottom:1px solid #f3f4f6}.row:last-child{border-bottom:none}.uptime{display:flex;gap:2px;margin-top:6px}.bar{width:6px;height:20px;border-radius:2px;background:#10b981}.badge{font-size:13px;color:#6b7280}.badge::before{content:'●';color:#10b981;margin-right:6px}</style>
</head><body><div class="container"><div class="brand"><div class="brand-mark"></div>${title} Status</div>
<div class="banner"><div class="dot"></div><div><h2>All systems operational</h2><p style="font-size:14px;opacity:.9">Last checked $(date -u +"%H:%M UTC")</p></div></div>
<div class="card"><h3>Current status</h3>
<div class="row"><div><div style="font-weight:500">API Gateway</div><div class="uptime">$(for i in $(seq 1 30); do echo -n '<div class="bar"></div>'; done)</div></div><span class="badge">Operational</span></div>
<div class="row"><div><div style="font-weight:500">Web Console</div><div class="uptime">$(for i in $(seq 1 30); do echo -n '<div class="bar"></div>'; done)</div></div><span class="badge">Operational</span></div>
<div class="row"><div><div style="font-weight:500">CDN</div><div class="uptime">$(for i in $(seq 1 30); do echo -n '<div class="bar"></div>'; done)</div></div><span class="badge">Operational</span></div>
<div class="row"><div><div style="font-weight:500">Database</div><div class="uptime">$(for i in $(seq 1 30); do echo -n '<div class="bar"></div>'; done)</div></div><span class="badge">Operational</span></div>
</div></div></body></html>
HTML
}

write_caddyfile_proxy() {
    local domain=$1
    local port=$2
    local target=$3

    # Извлекаем хост из URL для Host header
    local target_host=$(echo "$target" | sed -E 's|https?://||' | cut -d/ -f1)

    cat > "$APP_DIR/Caddyfile" << CADDY
{
    email admin@${domain}
    http_port 80
    https_port ${port}
    storage file_system /data
}

${domain}$([ "$port" != "443" ] && echo ":${port}") {
    # Reverse-proxy на реальный сайт — лучшая маскировка
    reverse_proxy ${target} {
        header_up Host ${target_host}
        header_up X-Forwarded-Host {host}
        header_up X-Real-IP {remote_host}
        # Убираем заголовки которые могут спалить
        header_down -X-Frame-Options
        header_down -Content-Security-Policy
        header_down -Strict-Transport-Security
    }

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options nosniff
        Referrer-Policy strict-origin-when-cross-origin
        -Server
        -X-Powered-By
    }

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
}

write_caddyfile_local() {
    local domain=$1
    local port=$2

    cat > "$APP_DIR/Caddyfile" << CADDY
{
    email admin@${domain}
    http_port 80
    https_port ${port}
    storage file_system /data
}

${domain}$([ "$port" != "443" ] && echo ":${port}") {
    root * /srv
    try_files {path} {path}.html {path}/index.html
    file_server

    @health path /api/health
    header @health Content-Type application/json
    respond @health \`{"status":"ok","timestamp":$(date +%s)}\`

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
}

write_compose() {
    local port=$1
    local mode=$2  # proxy | local

    local volumes='      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - ./data:/data
      - ./logs:/logs'

    if [[ "$mode" == "local" ]]; then
        volumes="$volumes
      - ./html:/srv:ro"
    fi

    cat > "$APP_DIR/docker-compose.yml" << COMPOSE
services:
  caddy:
    image: caddy:2-alpine
    container_name: selfsteal-caddy
    restart: always
    network_mode: host
    volumes:
${volumes}
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
}

write_env() {
    local domain=$1
    local port=$2
    local target=$3
    cat > "$APP_DIR/.env" << EOF
# Selfsteal Configuration
SELF_STEAL_DOMAIN=${domain}
SELF_STEAL_PORT=${port}
TEMPLATE=${TEMPLATE_NAME}
TARGET=${target}
INSTALLED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SERVER_IP=$(curl -s --max-time 3 -4 https://api.ipify.org 2>/dev/null)
EOF
}

install_cli() {
    cat > "$BIN_PATH" << 'CLI'
#!/usr/bin/env bash
APP_DIR="/opt/selfsteal"
cd "$APP_DIR" 2>/dev/null || { echo "Selfsteal not installed"; exit 1; }

case "$1" in
    up|start)     docker compose up -d ;;
    down|stop)    docker compose down ;;
    restart)      docker compose restart ;;
    reload)       docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile ;;
    logs)         docker compose logs -f --tail=100 ;;
    access)       tail -f "$APP_DIR/logs/access.log" 2>/dev/null || echo "No access log yet" ;;
    status|ps)    docker compose ps ;;
    config)       cat "$APP_DIR/Caddyfile" ;;
    env)          cat "$APP_DIR/.env" ;;
    test)
        source "$APP_DIR/.env"
        echo "Testing https://${SELF_STEAL_DOMAIN}:${SELF_STEAL_PORT}..."
        curl -sIk --max-time 5 "https://${SELF_STEAL_DOMAIN}:${SELF_STEAL_PORT}" | head -5
        ;;
    edit)         ${EDITOR:-nano} "$APP_DIR/Caddyfile" && docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile ;;
    uninstall)
        read -rp "Точно удалить selfsteal? [y/N]: " c
        [[ "$c" =~ ^[Yy]$ ]] || exit 0
        docker compose down -v 2>/dev/null
        rm -rf "$APP_DIR"
        rm -f /usr/local/bin/selfsteal
        echo "Удалено."
        ;;
    *)
        cat << HELP
selfsteal — управление Reality fakesite

Использование: selfsteal <команда>

  up            запустить
  down          остановить
  restart       перезапустить
  reload        перечитать Caddyfile без рестарта
  logs          логи Caddy (Docker)
  access        access.log в realtime
  status        статус контейнера
  config        показать Caddyfile
  env           показать .env
  test          curl -I на свой домен
  edit          редактировать Caddyfile + reload
  uninstall     удалить всё
HELP
        ;;
esac
CLI
    chmod +x "$BIN_PATH"
}

# ============================================
# Команды
# ============================================

cmd_install() {
    banner
    require_root

    if [[ -d "$APP_DIR" ]]; then
        warn "Selfsteal уже установлен в $APP_DIR"
        read -rp "Переустановить? [y/N]: " ow
        [[ "$ow" =~ ^[Yy]$ ]] || exit 0
        cd "$APP_DIR" && docker compose down 2>/dev/null
        rm -rf "$APP_DIR"
    fi

    echo ""
    read -rp "Введи домен (например, de1.example.com): " DOMAIN
    [[ -z "$DOMAIN" ]] && err "Домен пустой"

    read -rp "Порт для Caddy SSL [443]: " PORT
    PORT=${PORT:-443}
    [[ "$PORT" =~ ^[0-9]+$ ]] || err "Некорректный порт"

    choose_template

    info "Проверяю DNS..."
    check_dns "$DOMAIN"

    info "Проверяю порты..."
    check_ports "$PORT"

    install_docker_if_needed

    info "Создаю $APP_DIR..."
    mkdir -p "$HTML_DIR" "$LOG_DIR" "$CADDY_DATA_DIR"

    if [[ "$PROXY_TARGET" == local-* ]]; then
        local kind=${PROXY_TARGET#local-}
        local brand=$(generate_brand "$DOMAIN")
        info "Генерю локальный шаблон $kind, бренд: $brand"
        case "$kind" in
            saas)   build_local_saas "$brand" "$DOMAIN" ;;
            docs)   build_local_docs "$brand" "$DOMAIN" ;;
            status) build_local_status "$brand" ;;
        esac
        write_caddyfile_local "$DOMAIN" "$PORT"
        write_compose "$PORT" "local"
    else
        info "Reverse-proxy на $PROXY_TARGET"
        write_caddyfile_proxy "$DOMAIN" "$PORT" "$PROXY_TARGET"
        write_compose "$PORT" "proxy"
    fi

    write_env "$DOMAIN" "$PORT" "$PROXY_TARGET"
    install_cli

    info "Запускаю Docker..."
    cd "$APP_DIR"
    docker compose up -d > /dev/null 2>&1

    info "Жду получения SSL сертификата (до 60 сек)..."
    local ok_ssl=false
    for i in $(seq 1 30); do
        if curl -sk --max-time 3 "https://${DOMAIN}:${PORT}" -o /dev/null 2>&1; then
            ok_ssl=true
            break
        fi
        sleep 2
    done

    echo ""
    echo -e "${GREEN}╔═════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║  Установка завершена                                        ║${NC}"
    echo -e "${GREEN}╚═════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  Домен:     ${CYAN}https://${DOMAIN}$([ "$PORT" != "443" ] && echo ":${PORT}")${NC}"
    echo -e "  Шаблон:    ${TEMPLATE_NAME}"
    echo -e "  Порт:      ${PORT}"
    echo -e "  Каталог:   ${APP_DIR}"
    [[ "$ok_ssl" == "true" ]] && echo -e "  SSL:       ${GREEN}OK${NC}" || echo -e "  SSL:       ${YELLOW}проверь selfsteal logs${NC}"
    echo ""
    echo -e "${YELLOW}Reality inbound (Remnawave):${NC}"
    echo -e "  dest:        ${CYAN}127.0.0.1:${PORT}${NC}"
    echo -e "  serverNames: ${CYAN}[\"${DOMAIN}\"]${NC}"
    echo ""
    echo -e "${GRAY}Управление:${NC}"
    echo -e "  ${CYAN}selfsteal status${NC}     — статус"
    echo -e "  ${CYAN}selfsteal logs${NC}       — логи"
    echo -e "  ${CYAN}selfsteal test${NC}       — проверить домен"
    echo -e "  ${CYAN}selfsteal restart${NC}    — рестарт"
    echo -e "  ${CYAN}selfsteal uninstall${NC}  — удалить"
    echo ""
}

cmd_uninstall() {
    require_root
    [[ -d "$APP_DIR" ]] || err "Selfsteal не установлен"
    read -rp "Точно удалить? [y/N]: " c
    [[ "$c" =~ ^[Yy]$ ]] || exit 0
    cd "$APP_DIR" && docker compose down -v 2>/dev/null
    rm -rf "$APP_DIR" "$BIN_PATH"
    ok "Удалено"
}

cmd_help() {
    banner
    cat << HELP

Использование: bash $0 <команда>

  install      установить (по умолчанию)
  uninstall    удалить полностью
  help         эта справка

После установки используй команду: ${CYAN}selfsteal${NC}

HELP
}

# ============================================
# Main
# ============================================

case "${1:-install}" in
    install|"")  cmd_install ;;
    uninstall)   cmd_uninstall ;;
    help|-h|--help) cmd_help ;;
    *) err "Неизвестная команда: $1. Используй: install | uninstall | help" ;;
esac
