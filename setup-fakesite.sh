#!/bin/bash
# ╔═════════════════════════════════════════════════════════════╗
# ║  Selfsteal v3 — Reality traffic masking                    ║
# ║  Docker Caddy + готовые HTML-шаблоны                       ║
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
DATA_DIR="$APP_DIR/data"
BIN_PATH="/usr/local/bin/selfsteal"
SCRIPT_VERSION="3.0"

err() { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }
ok()  { echo -e "${GREEN}✓ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠ $1${NC}"; }
info(){ echo -e "${CYAN}→ $1${NC}"; }

banner() {
    echo -e "${CYAN}╔═════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}  ${GREEN}Selfsteal v${SCRIPT_VERSION}${NC} — Reality fakesite                       ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}  Docker Caddy + готовые HTML-шаблоны                        ${CYAN}║${NC}"
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
        warn "Порт 80 или $port занят"
        ss -tlnp 2>/dev/null | grep -E ":(80|${port}) " | head -3
        read -rp "Остановить занявшие процессы (caddy/nginx/apache)? [y/N]: " stop
        if [[ "$stop" =~ ^[Yy]$ ]]; then
            systemctl stop nginx caddy apache2 2>/dev/null || true
            sleep 1
            ss -tuln 2>/dev/null | grep -qE ":(80|${port}) " && err "Порт всё ещё занят"
        else
            err "Освободи порты и запусти снова"
        fi
    fi
    ok "Порты 80 и $port свободны"
}

choose_template() {
    echo ""
    echo -e "${YELLOW}Выберите шаблон fakesite:${NC}"
    echo ""
    printf "  ${BLUE}%2s)${NC} %-22s ${GRAY}— %s${NC}\n" "1" "SaaS Cloud" "Лендинг IaaS-стартапа"
    printf "  ${BLUE}%2s)${NC} %-22s ${GRAY}— %s${NC}\n" "2" "API Documentation" "Docs как docs.stripe.com"
    printf "  ${BLUE}%2s)${NC} %-22s ${GRAY}— %s${NC}\n" "3" "Status Page" "System status"
    printf "  ${BLUE}%2s)${NC} %-22s ${GRAY}— %s${NC}\n" "4" "File Cloud" "Облачное хранилище"
    printf "  ${BLUE}%2s)${NC} %-22s ${GRAY}— %s${NC}\n" "5" "Tech Blog" "Блог про разработку"
    printf "  ${BLUE}%2s)${NC} %-22s ${GRAY}— %s${NC}\n" "6" "503 Maintenance" "Минималистичная заглушка"
    echo ""
    read -rp "Шаблон [1]: " TEMPLATE
    TEMPLATE=${TEMPLATE:-1}

    case "$TEMPLATE" in
        1) TEMPLATE_NAME="SaaS Cloud" ;;
        2) TEMPLATE_NAME="API Documentation" ;;
        3) TEMPLATE_NAME="Status Page" ;;
        4) TEMPLATE_NAME="File Cloud" ;;
        5) TEMPLATE_NAME="Tech Blog" ;;
        6) TEMPLATE_NAME="503 Maintenance" ;;
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

# ============================================
# Шаблон 1: SaaS Cloud
# ============================================
build_saas() {
    local title=$1
    local domain=$2
    local year=$(date +%Y)

    cat > "$HTML_DIR/index.html" << HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>${title} — Modern infrastructure for developers</title>
<meta name="description" content="${title} provides reliable cloud infrastructure, edge computing and developer tools.">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><rect x='10' y='10' width='80' height='80' rx='20' fill='%236366f1'/></svg>">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0a0a0f;color:#e6e6e6;line-height:1.6}
nav{position:sticky;top:0;background:rgba(10,10,15,.85);backdrop-filter:blur(10px);border-bottom:1px solid #1f2937;padding:16px 0;z-index:100}
.nav-inner{max-width:1200px;margin:0 auto;padding:0 24px;display:flex;justify-content:space-between;align-items:center}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;font-size:18px}
.brand-mark{width:28px;height:28px;border-radius:6px;background:linear-gradient(135deg,#6366f1,#8b5cf6)}
.nav-links{display:flex;gap:32px;font-size:14px}
.nav-links a{color:#9ca3af;text-decoration:none}
.nav-links a:hover{color:#fff}
.btn{display:inline-block;padding:10px 20px;border-radius:8px;text-decoration:none;font-weight:500;font-size:14px}
.btn-primary{background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff}
.btn-ghost{color:#e6e6e6;border:1px solid #374151}
.hero{max-width:900px;margin:0 auto;padding:100px 24px 80px;text-align:center}
.badge{display:inline-block;padding:6px 14px;border-radius:999px;background:rgba(99,102,241,.1);color:#a5b4fc;font-size:13px;margin-bottom:24px;border:1px solid rgba(99,102,241,.3)}
h1{font-size:56px;font-weight:800;line-height:1.1;margin-bottom:24px;letter-spacing:-1.5px;background:linear-gradient(135deg,#fff,#9ca3af);-webkit-background-clip:text;-webkit-text-fill-color:transparent}
.hero-sub{font-size:20px;color:#9ca3af;max-width:640px;margin:0 auto 40px}
.hero-cta{display:flex;gap:16px;justify-content:center;flex-wrap:wrap}
.features{max-width:1200px;margin:0 auto;padding:80px 24px;display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}
.feature{padding:32px;background:#11131a;border:1px solid #1f2937;border-radius:16px}
.feature-icon{width:48px;height:48px;border-radius:12px;background:rgba(99,102,241,.1);display:flex;align-items:center;justify-content:center;margin-bottom:20px;font-size:24px}
.feature h3{font-size:20px;margin-bottom:12px}
.feature p{color:#9ca3af;font-size:15px}
.pricing{max-width:1200px;margin:0 auto;padding:80px 24px}
.section-title{text-align:center;font-size:40px;font-weight:700;margin-bottom:16px}
.section-sub{text-align:center;color:#9ca3af;margin-bottom:60px;font-size:17px}
.plans{display:grid;grid-template-columns:repeat(auto-fit,minmax(280px,1fr));gap:24px}
.plan{padding:36px;background:#11131a;border:1px solid #1f2937;border-radius:16px;position:relative}
.plan.popular{border-color:#6366f1}
.plan-tag{position:absolute;top:-12px;left:50%;transform:translateX(-50%);background:#6366f1;color:#fff;padding:4px 12px;border-radius:999px;font-size:12px;font-weight:600}
.plan-name{font-size:14px;color:#9ca3af;text-transform:uppercase;letter-spacing:1px;margin-bottom:8px}
.plan-price{font-size:48px;font-weight:800;margin-bottom:8px}
.plan-price small{font-size:16px;color:#9ca3af;font-weight:400}
.plan ul{list-style:none;margin-bottom:24px}
.plan li{padding:8px 0;font-size:14px}
.plan li::before{content:'✓ ';color:#6366f1;font-weight:bold}
.plan .btn{width:100%;text-align:center}
footer{border-top:1px solid #1f2937;padding:40px 24px;color:#6b7280;font-size:14px}
.footer-inner{max-width:1200px;margin:0 auto;display:flex;justify-content:space-between;flex-wrap:wrap;gap:24px}
.footer-inner a{color:#9ca3af;text-decoration:none;margin-right:16px}
@media(max-width:640px){h1{font-size:36px}.nav-links{display:none}}
</style>
</head>
<body>
<nav>
  <div class="nav-inner">
    <div class="brand"><div class="brand-mark"></div><span>${title}</span></div>
    <div class="nav-links">
      <a href="/features">Features</a>
      <a href="/pricing">Pricing</a>
      <a href="/docs">Docs</a>
      <a href="/blog">Blog</a>
    </div>
    <a href="/signin" class="btn btn-ghost">Sign in</a>
  </div>
</nav>

<section class="hero">
  <div class="badge">★ Edge functions in beta</div>
  <h1>Build. Deploy.<br>Scale instantly.</h1>
  <p class="hero-sub">${title} is a developer-first platform for shipping production apps without managing infrastructure.</p>
  <div class="hero-cta">
    <a href="/signup" class="btn btn-primary">Start free trial</a>
    <a href="/docs" class="btn btn-ghost">Read the docs</a>
  </div>
</section>

<section class="features">
  <div class="feature"><div class="feature-icon">⚡</div><h3>Edge runtime</h3><p>Run code in 280+ regions worldwide. Sub-50ms cold starts.</p></div>
  <div class="feature"><div class="feature-icon">🔒</div><h3>Built-in security</h3><p>DDoS protection, WAF, TLS. SOC 2 Type II compliant.</p></div>
  <div class="feature"><div class="feature-icon">📊</div><h3>Real-time metrics</h3><p>Trace requests across services. Custom dashboards.</p></div>
  <div class="feature"><div class="feature-icon">🚀</div><h3>Git-driven deploys</h3><p>Push to deploy. Preview branches, instant rollback.</p></div>
  <div class="feature"><div class="feature-icon">🔧</div><h3>Powerful CLI</h3><p>Manage everything from the terminal.</p></div>
  <div class="feature"><div class="feature-icon">💼</div><h3>Team collaboration</h3><p>Role-based access, audit logs, SSO/SAML.</p></div>
</section>

<section class="pricing">
  <h2 class="section-title">Simple pricing</h2>
  <p class="section-sub">Start free, scale as you grow.</p>
  <div class="plans">
    <div class="plan">
      <div class="plan-name">Hobby</div>
      <div class="plan-price">\$0<small>/mo</small></div>
      <ul><li>100k requests/mo</li><li>1 GB storage</li><li>Community support</li></ul>
      <a href="/signup" class="btn btn-ghost">Get started</a>
    </div>
    <div class="plan popular">
      <div class="plan-tag">Most popular</div>
      <div class="plan-name">Pro</div>
      <div class="plan-price">\$29<small>/mo</small></div>
      <ul><li>10M requests/mo</li><li>50 GB storage</li><li>Email support</li><li>Custom domains</li></ul>
      <a href="/signup" class="btn btn-primary">Start trial</a>
    </div>
    <div class="plan">
      <div class="plan-name">Enterprise</div>
      <div class="plan-price">Custom</div>
      <ul><li>Unlimited requests</li><li>SSO/SAML</li><li>24/7 SLA</li><li>Dedicated support</li></ul>
      <a href="/contact" class="btn btn-ghost">Contact sales</a>
    </div>
  </div>
</section>

<footer>
  <div class="footer-inner">
    <div>© ${year} ${title}</div>
    <div>
      <a href="/privacy">Privacy</a>
      <a href="/terms">Terms</a>
      <a href="/security">Security</a>
      <a href="/status">Status</a>
    </div>
  </div>
</footer>
</body>
</html>
HTML

    for page in features pricing docs blog signin signup contact security status privacy terms; do
        cat > "$HTML_DIR/${page}.html" << EOF
<!DOCTYPE html><html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>${page^} — ${title}</title>
<style>body{font-family:-apple-system,sans-serif;background:#0a0a0f;color:#e6e6e6;max-width:760px;margin:80px auto;padding:24px;line-height:1.7}h1{font-size:36px;margin-bottom:24px}p{color:#9ca3af;margin-bottom:16px}a{color:#a5b4fc}</style>
</head><body><h1>${page^}</h1><p>This section is being updated.</p><p><a href="/">← Home</a></p></body></html>
EOF
    done
}

# ============================================
# Шаблон 2: API Documentation
# ============================================
build_docs() {
    local title=$1
    local domain=$2
    local date=$(date -u +"%Y-%m-%d")

    cat > "$HTML_DIR/index.html" << HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>${title} API Reference — Documentation</title>
<meta name="description" content="${title} REST API documentation, authentication, endpoints.">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><path d='M30 25 L70 25 L70 75 L30 75 Z' fill='none' stroke='%2310b981' stroke-width='6'/></svg>">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,sans-serif;background:#fafbfc;color:#1a1f2e;line-height:1.6;font-size:15px}
.layout{display:flex;min-height:100vh}
.sidebar{width:280px;background:#fff;border-right:1px solid #e5e7eb;padding:24px 0;position:sticky;top:0;height:100vh;overflow-y:auto}
.sidebar-brand{padding:0 24px 24px;border-bottom:1px solid #e5e7eb;display:flex;align-items:center;gap:10px;font-weight:700;font-size:17px}
.sidebar-brand-mark{width:28px;height:28px;border-radius:6px;background:linear-gradient(135deg,#10b981,#059669)}
.sidebar h4{padding:20px 24px 8px;font-size:11px;color:#6b7280;text-transform:uppercase;letter-spacing:1px}
.sidebar a{display:block;padding:7px 24px;color:#4b5563;text-decoration:none;font-size:14px;border-left:3px solid transparent}
.sidebar a:hover{background:#f3f4f6;color:#10b981}
.sidebar a.active{background:#ecfdf5;color:#059669;border-left-color:#10b981;font-weight:500}
.content{flex:1;padding:48px 60px;max-width:900px}
.breadcrumb{color:#6b7280;font-size:13px;margin-bottom:16px}
h1{font-size:36px;font-weight:700;margin-bottom:16px}
.lead{font-size:18px;color:#4b5563;margin-bottom:32px}
h2{font-size:24px;font-weight:700;margin:40px 0 16px;padding-top:16px;border-top:1px solid #e5e7eb}
p{margin-bottom:16px;color:#374151}
code{background:#f3f4f6;padding:2px 6px;border-radius:4px;font-family:monospace;color:#be185d}
pre{background:#0d1117;color:#e6edf3;padding:20px;border-radius:8px;overflow-x:auto;margin:16px 0}
pre code{background:none;color:#e6edf3;padding:0}
.method{display:inline-block;padding:3px 10px;border-radius:4px;font-size:12px;font-weight:700;margin-right:8px;font-family:monospace}
.method.get{background:#dbeafe;color:#1e40af}
.method.post{background:#dcfce7;color:#166534}
.endpoint{background:#fff;border:1px solid #e5e7eb;border-radius:8px;padding:16px;margin:12px 0;font-family:monospace}
table{width:100%;border-collapse:collapse;margin:16px 0;font-size:14px}
th,td{text-align:left;padding:12px;border-bottom:1px solid #e5e7eb}
th{background:#f9fafb;font-weight:600;font-size:13px}
.note{background:#fef3c7;border-left:4px solid #f59e0b;padding:14px 16px;border-radius:4px;margin:20px 0;font-size:14px;color:#78350f}
@media(max-width:768px){.sidebar{display:none}.content{padding:32px 24px}}
</style>
</head>
<body>
<div class="layout">
  <aside class="sidebar">
    <div class="sidebar-brand"><div class="sidebar-brand-mark"></div>${title} Docs</div>
    <h4>Getting started</h4>
    <a href="/" class="active">Introduction</a>
    <a href="/quickstart">Quickstart</a>
    <a href="/authentication">Authentication</a>
    <a href="/errors">Error handling</a>
    <h4>API Reference</h4>
    <a href="/api/users">Users</a>
    <a href="/api/projects">Projects</a>
    <a href="/api/deployments">Deployments</a>
    <a href="/api/webhooks">Webhooks</a>
    <h4>Guides</h4>
    <a href="/guides/cli">CLI</a>
    <a href="/guides/sdks">SDKs</a>
  </aside>
  <main class="content">
    <div class="breadcrumb">Docs › Getting started › Introduction</div>
    <h1>Introduction</h1>
    <p class="lead">${title} provides a REST API to manage your projects programmatically.</p>

    <h2>Base URL</h2>
    <pre><code>https://api.${domain}/v1</code></pre>
    <div class="note"><strong>Note:</strong> v0 deprecated as of ${date}. Migrate to v1.</div>

    <h2>Authentication</h2>
    <p>The API uses bearer tokens:</p>
    <pre><code>curl https://api.${domain}/v1/projects \\
  -H "Authorization: Bearer \$API_KEY"</code></pre>

    <h2>Resources</h2>
    <div class="endpoint"><span class="method get">GET</span>/v1/projects</div>
    <div class="endpoint"><span class="method post">POST</span>/v1/projects</div>
    <div class="endpoint"><span class="method get">GET</span>/v1/projects/:id/deployments</div>

    <h2>Rate limits</h2>
    <table>
      <tr><th>Plan</th><th>Requests/min</th><th>Burst</th></tr>
      <tr><td>Hobby</td><td>60</td><td>120</td></tr>
      <tr><td>Pro</td><td>600</td><td>1200</td></tr>
      <tr><td>Enterprise</td><td>Custom</td><td>Custom</td></tr>
    </table>
  </main>
</div>
</body>
</html>
HTML

    for page in quickstart authentication errors; do
        cat > "$HTML_DIR/${page}.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${page^} — ${title}</title><style>body{font-family:sans-serif;background:#fafbfc;max-width:760px;margin:60px auto;padding:24px;line-height:1.7}a{color:#10b981}</style></head><body><h1>${page^}</h1><p>Documentation under update. <a href="/">← Back</a></p></body></html>
EOF
    done

    mkdir -p "$HTML_DIR/api" "$HTML_DIR/guides"
    for ep in users projects deployments webhooks; do
        cat > "$HTML_DIR/api/${ep}.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${ep^} — ${title}</title><style>body{font-family:sans-serif;background:#fafbfc;max-width:760px;margin:60px auto;padding:24px;line-height:1.7}a{color:#10b981}</style></head><body><h1>${ep^} API</h1><p>Reference under construction. <a href="/">← Back</a></p></body></html>
EOF
    done
    for g in cli sdks; do
        cat > "$HTML_DIR/guides/${g}.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${g^^} — ${title}</title><style>body{font-family:sans-serif;background:#fafbfc;max-width:760px;margin:60px auto;padding:24px;line-height:1.7}a{color:#10b981}</style></head><body><h1>${g^^} guide</h1><p>Coming soon. <a href="/">← Back</a></p></body></html>
EOF
    done
}

# ============================================
# Шаблон 3: Status Page
# ============================================
build_status() {
    local title=$1
    local year=$(date +%Y)

    cat > "$HTML_DIR/index.html" << HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>${title} — System Status</title>
<meta name="description" content="${title} infrastructure status, incident history.">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><circle cx='50' cy='50' r='40' fill='%2310b981'/></svg>">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,sans-serif;background:#f5f7fa;color:#1a1f2e;min-height:100vh;line-height:1.6}
.container{max-width:780px;margin:0 auto;padding:48px 24px}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;font-size:18px;margin-bottom:40px}
.brand-mark{width:32px;height:32px;border-radius:8px;background:linear-gradient(135deg,#10b981,#059669)}
.banner{background:linear-gradient(135deg,#10b981,#059669);color:#fff;padding:24px 28px;border-radius:12px;margin-bottom:32px;display:flex;align-items:center;gap:16px}
.banner-dot{width:14px;height:14px;border-radius:50%;background:#fff;animation:p 2s infinite}
@keyframes p{0%,100%{opacity:1}50%{opacity:.5}}
.banner h2{font-size:20px;font-weight:600}
.banner p{font-size:14px;opacity:.9}
.card{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:24px;margin-bottom:16px}
.card h3{font-size:14px;color:#6b7280;text-transform:uppercase;letter-spacing:1px;margin-bottom:16px}
.row{display:flex;justify-content:space-between;align-items:center;padding:12px 0;border-bottom:1px solid #f3f4f6}
.row:last-child{border-bottom:none}
.row-name{font-weight:500}
.uptime{display:flex;gap:2px;margin-top:6px}
.bar{width:8px;height:24px;border-radius:2px;background:#10b981}
.badge{font-size:13px;color:#6b7280}
.badge::before{content:'●';color:#10b981;margin-right:6px}
.history-item{padding:16px 0;border-bottom:1px solid #f3f4f6}
.history-item:last-child{border-bottom:none}
.history-date{font-size:12px;color:#9ca3af;margin-bottom:4px}
.history-title{font-weight:500;margin-bottom:4px}
footer{text-align:center;color:#9ca3af;font-size:13px;margin-top:40px;padding:24px}
</style>
</head>
<body>
<div class="container">
  <div class="brand"><div class="brand-mark"></div>${title} Status</div>

  <div class="banner">
    <div class="banner-dot"></div>
    <div><h2>All systems operational</h2><p>Last updated $(date -u +"%H:%M UTC, %B %d, %Y")</p></div>
  </div>

  <div class="card">
    <h3>Current status</h3>
HTML

    for service in "API Gateway" "Web Console" "CDN Edge" "Authentication" "Database"; do
        echo '    <div class="row">' >> "$HTML_DIR/index.html"
        echo "      <div><div class=\"row-name\">${service}</div>" >> "$HTML_DIR/index.html"
        echo -n '      <div class="uptime">' >> "$HTML_DIR/index.html"
        for i in $(seq 1 30); do echo -n '<div class="bar"></div>' >> "$HTML_DIR/index.html"; done
        echo '</div></div>' >> "$HTML_DIR/index.html"
        echo '      <span class="badge">Operational</span>' >> "$HTML_DIR/index.html"
        echo '    </div>' >> "$HTML_DIR/index.html"
    done

    cat >> "$HTML_DIR/index.html" << HTML
  </div>

  <div class="card">
    <h3>Past incidents</h3>
    <div class="history-item">
      <div class="history-date">$(date -u -d '3 days ago' +"%B %d, %Y" 2>/dev/null || date -u +"%B %d, %Y")</div>
      <div class="history-title">No incidents reported</div>
    </div>
    <div class="history-item">
      <div class="history-date">$(date -u -d '7 days ago' +"%B %d, %Y" 2>/dev/null || date -u +"%B %d, %Y")</div>
      <div class="history-title">Increased API latency in eu-west-1</div>
      <div style="font-size:14px;color:#6b7280">Resolved after 14 minutes.</div>
    </div>
  </div>
</div>

<footer>© ${year} ${title}</footer>
</body>
</html>
HTML
}

# ============================================
# Шаблон 4: File Cloud
# ============================================
build_filecloud() {
    local title=$1
    local year=$(date +%Y)

    cat > "$HTML_DIR/index.html" << HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>${title} — Secure file storage in the cloud</title>
<meta name="description" content="${title} is a secure, end-to-end encrypted file storage service.">
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><path d='M20 60 Q20 40 40 40 Q45 25 60 25 Q80 25 80 50 Q80 65 65 65 L35 65 Q20 65 20 60' fill='%230ea5e9'/></svg>">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,sans-serif;background:#fff;color:#0f172a;line-height:1.6}
nav{padding:20px 0;border-bottom:1px solid #e2e8f0}
.nav-inner{max-width:1200px;margin:0 auto;padding:0 24px;display:flex;justify-content:space-between;align-items:center}
.brand{display:flex;align-items:center;gap:10px;font-weight:700;font-size:18px;color:#0ea5e9}
.brand-mark{width:32px;height:32px;background:linear-gradient(135deg,#0ea5e9,#0284c7);border-radius:8px;display:flex;align-items:center;justify-content:center;color:#fff}
.nav-links{display:flex;gap:32px;font-size:14px}
.nav-links a{color:#475569;text-decoration:none}
.btn{padding:10px 20px;border-radius:8px;text-decoration:none;font-weight:500;font-size:14px}
.btn-primary{background:#0ea5e9;color:#fff}
.btn-ghost{color:#0f172a}
.hero{max-width:900px;margin:0 auto;padding:80px 24px;text-align:center}
h1{font-size:52px;font-weight:800;margin-bottom:24px;letter-spacing:-1.5px}
.hero-sub{font-size:19px;color:#64748b;max-width:560px;margin:0 auto 32px}
.upload-zone{max-width:540px;margin:48px auto;padding:48px;background:#f8fafc;border:2px dashed #cbd5e1;border-radius:16px;text-align:center}
.features{max-width:1200px;margin:0 auto;padding:80px 24px;display:grid;grid-template-columns:repeat(auto-fit,minmax(260px,1fr));gap:24px}
.feature{padding:32px;background:#f8fafc;border-radius:16px}
.feature-icon{font-size:32px;margin-bottom:16px}
.feature h3{font-size:18px;margin-bottom:8px}
.feature p{color:#64748b;font-size:14px}
.stats{background:#0f172a;color:#fff;padding:60px 24px;text-align:center}
.stats-grid{max-width:1200px;margin:0 auto;display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:24px}
.stat-num{font-size:48px;font-weight:800;color:#0ea5e9}
.stat-label{color:#94a3b8;margin-top:8px}
footer{padding:40px 24px;border-top:1px solid #e2e8f0;text-align:center;color:#64748b;font-size:14px}
@media(max-width:640px){h1{font-size:36px}.nav-links{display:none}}
</style>
</head>
<body>
<nav><div class="nav-inner"><div class="brand"><div class="brand-mark">↑</div>${title}</div><div class="nav-links"><a href="/features">Features</a><a href="/pricing">Pricing</a><a href="/business">Business</a></div><a href="/signin" class="btn btn-ghost">Sign in</a></div></nav>

<section class="hero">
  <h1>Your files,<br>encrypted and synced.</h1>
  <p class="hero-sub">${title} keeps your files safe with end-to-end encryption. Access from anywhere.</p>
  <a href="/signup" class="btn btn-primary">Get 5 GB free</a>
</section>

<div class="upload-zone">
  <div style="font-size:48px;margin-bottom:16px">📁</div>
  <p><strong>Drag files here or click to upload</strong></p>
  <p style="font-size:13px;color:#64748b">Max 100 MB on free plan</p>
</div>

<section class="features">
  <div class="feature"><div class="feature-icon">🔐</div><h3>End-to-end encrypted</h3><p>Zero-knowledge architecture. Only you have the keys.</p></div>
  <div class="feature"><div class="feature-icon">🔄</div><h3>Auto-sync</h3><p>Desktop, mobile, web — everything in sync.</p></div>
  <div class="feature"><div class="feature-icon">🔗</div><h3>Secure sharing</h3><p>Password-protected links with expiration.</p></div>
  <div class="feature"><div class="feature-icon">📜</div><h3>Version history</h3><p>Restore any file to a previous version.</p></div>
</section>

<section class="stats">
  <div class="stats-grid">
    <div><div class="stat-num">2.4M+</div><div class="stat-label">Active users</div></div>
    <div><div class="stat-num">180 PB</div><div class="stat-label">Files stored</div></div>
    <div><div class="stat-num">99.99%</div><div class="stat-label">Uptime</div></div>
  </div>
</section>

<footer>© ${year} ${title}. <a href="/privacy" style="color:#0ea5e9">Privacy</a> · <a href="/terms" style="color:#0ea5e9">Terms</a></footer>
</body>
</html>
HTML

    for page in features pricing business signin signup privacy terms; do
        cat > "$HTML_DIR/${page}.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${page^} — ${title}</title><style>body{font-family:-apple-system,sans-serif;max-width:760px;margin:60px auto;padding:24px;line-height:1.7;color:#0f172a}a{color:#0ea5e9}</style></head><body><h1>${page^}</h1><p>Page being updated. <a href="/">← Home</a></p></body></html>
EOF
    done
}

# ============================================
# Шаблон 5: Tech Blog
# ============================================
build_blog() {
    local title=$1
    local year=$(date +%Y)
    local d1=$(date -u +"%B %d, %Y")
    local d2=$(date -u -d '5 days ago' +"%B %d, %Y" 2>/dev/null || echo "$d1")
    local d3=$(date -u -d '14 days ago' +"%B %d, %Y" 2>/dev/null || echo "$d1")
    local d4=$(date -u -d '21 days ago' +"%B %d, %Y" 2>/dev/null || echo "$d1")

    cat > "$HTML_DIR/index.html" << HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>${title} — Engineering Blog</title>
<meta name="description" content="Articles about distributed systems and software architecture.">
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:Georgia,'Times New Roman',serif;background:#fafaf9;color:#1c1917;line-height:1.7;font-size:17px}
nav{border-bottom:1px solid #e7e5e4;padding:20px 0;background:#fff}
.nav-inner{max-width:760px;margin:0 auto;padding:0 24px;display:flex;justify-content:space-between;align-items:center}
.brand{font-weight:700;font-size:22px;text-decoration:none;color:#1c1917}
.nav-links a{color:#57534e;text-decoration:none;margin-left:24px;font-size:15px;font-family:-apple-system,sans-serif}
.container{max-width:760px;margin:0 auto;padding:60px 24px}
.intro{font-family:-apple-system,sans-serif;color:#57534e;margin-bottom:60px;font-size:16px}
.post{margin-bottom:48px;padding-bottom:48px;border-bottom:1px solid #e7e5e4}
.post:last-child{border-bottom:none}
.post-meta{font-family:-apple-system,sans-serif;font-size:13px;color:#78716c;margin-bottom:8px;text-transform:uppercase;letter-spacing:.5px}
.post h2{font-size:32px;line-height:1.2;margin-bottom:16px}
.post h2 a{color:#1c1917;text-decoration:none}
.post h2 a:hover{color:#dc2626}
.post-excerpt{color:#44403c}
.post-tag{display:inline-block;font-family:-apple-system,sans-serif;font-size:12px;background:#f5f5f4;padding:3px 10px;border-radius:4px;color:#57534e;margin-right:6px;text-transform:uppercase;letter-spacing:.5px}
footer{border-top:1px solid #e7e5e4;padding:40px 24px;text-align:center;font-family:-apple-system,sans-serif;font-size:14px;color:#78716c;background:#fff}
</style>
</head>
<body>
<nav><div class="nav-inner"><a href="/" class="brand">${title}</a><div class="nav-links"><a href="/about">About</a><a href="/archive">Archive</a><a href="/rss.xml">RSS</a></div></div></nav>

<div class="container">
  <p class="intro">Notes on distributed systems, infrastructure, and the craft of software engineering.</p>

  <article class="post">
    <div class="post-meta">${d1}</div>
    <h2><a href="/posts/scaling-postgres">Scaling Postgres beyond a single primary</a></h2>
    <p class="post-excerpt">After hitting 50k QPS our database started showing strain. Here's how we approached read replicas, connection pooling, and eventually moved to a partitioned setup.</p>
    <div style="margin-top:12px"><span class="post-tag">postgres</span><span class="post-tag">infra</span></div>
  </article>

  <article class="post">
    <div class="post-meta">${d2}</div>
    <h2><a href="/posts/event-driven-pitfalls">The hidden cost of event-driven architecture</a></h2>
    <p class="post-excerpt">Event-driven systems promise loose coupling, but the operational complexity is real. Debugging cascading failures across 30 services taught us when synchronous calls are actually fine.</p>
    <div style="margin-top:12px"><span class="post-tag">architecture</span></div>
  </article>

  <article class="post">
    <div class="post-meta">${d3}</div>
    <h2><a href="/posts/observability-budget">Why we capped our observability budget</a></h2>
    <p class="post-excerpt">Datadog bill creeping toward 6 figures? You're not alone. We cut spend by 60% without losing visibility.</p>
    <div style="margin-top:12px"><span class="post-tag">observability</span><span class="post-tag">finops</span></div>
  </article>

  <article class="post">
    <div class="post-meta">${d4}</div>
    <h2><a href="/posts/incident-postmortem">Anatomy of a 4-hour outage</a></h2>
    <p class="post-excerpt">A misconfigured Kafka consumer triggered cascading failures across our entire payment pipeline. Full timeline, mistakes made.</p>
    <div style="margin-top:12px"><span class="post-tag">incident</span></div>
  </article>
</div>

<footer>© ${year} ${title} · <a href="/rss.xml" style="color:#dc2626">RSS</a></footer>
</body>
</html>
HTML

    mkdir -p "$HTML_DIR/posts"
    for slug in scaling-postgres event-driven-pitfalls observability-budget incident-postmortem; do
        cat > "$HTML_DIR/posts/${slug}.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${slug} — ${title}</title><style>body{font-family:Georgia,serif;background:#fafaf9;color:#1c1917;max-width:680px;margin:60px auto;padding:24px;line-height:1.8;font-size:18px}a{color:#dc2626}h1{font-size:36px;margin-bottom:24px}</style></head><body><h1>${slug}</h1><p>This post is being prepared.</p><p><a href="/">← Back</a></p></body></html>
EOF
    done

    for page in about archive; do
        cat > "$HTML_DIR/${page}.html" << EOF
<!DOCTYPE html><html><head><meta charset="UTF-8"><title>${page^} — ${title}</title><style>body{font-family:Georgia,serif;max-width:680px;margin:60px auto;padding:24px;line-height:1.7}a{color:#dc2626}</style></head><body><h1>${page^}</h1><p>Coming soon. <a href="/">← Home</a></p></body></html>
EOF
    done

    cat > "$HTML_DIR/rss.xml" << RSS
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel>
<title>${title}</title>
<link>https://example.com</link>
<description>Engineering blog</description>
</channel></rss>
RSS
}

# ============================================
# Шаблон 6: 503 Maintenance
# ============================================
build_503() {
    local title=$1
    cat > "$HTML_DIR/index.html" << HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<title>503 — Service Temporarily Unavailable</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,sans-serif;background:#0f172a;color:#cbd5e1;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:24px}
.box{max-width:480px;text-align:center}
.code{font-size:120px;font-weight:200;color:#475569;line-height:1;margin-bottom:24px;letter-spacing:-4px}
h1{font-size:24px;font-weight:600;color:#f1f5f9;margin-bottom:16px}
p{color:#94a3b8;font-size:15px;margin-bottom:8px}
.brand{margin-top:48px;font-size:13px;color:#475569;text-transform:uppercase;letter-spacing:2px}
.dot{display:inline-block;width:6px;height:6px;border-radius:50%;background:#f59e0b;margin-right:8px;animation:p 2s infinite}
@keyframes p{0%,100%{opacity:1}50%{opacity:.3}}
</style>
</head>
<body>
<div class="box">
  <div class="code">503</div>
  <h1><span class="dot"></span>Service temporarily unavailable</h1>
  <p>The server is undergoing scheduled maintenance.</p>
  <p>Please try again in a few minutes.</p>
  <div class="brand">${title}</div>
</div>
</body>
</html>
HTML
}

# ============================================
# Caddyfile + docker-compose
# ============================================

write_caddyfile() {
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
}

write_compose() {
    cat > "$APP_DIR/docker-compose.yml" << 'COMPOSE'
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
}

write_env() {
    local domain=$1
    local port=$2
    cat > "$APP_DIR/.env" << EOF
SELF_STEAL_DOMAIN=${domain}
SELF_STEAL_PORT=${port}
TEMPLATE=${TEMPLATE_NAME}
INSTALLED=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
SERVER_IP=$(curl -s --max-time 3 -4 https://api.ipify.org 2>/dev/null)
EOF
}

write_robots_sitemap() {
    local domain=$1
    local date=$(date -u +"%Y-%m-%d")
    cat > "$HTML_DIR/robots.txt" << EOF
User-agent: *
Allow: /
Disallow: /admin
Sitemap: https://${domain}/sitemap.xml
EOF

    cat > "$HTML_DIR/sitemap.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url><loc>https://${domain}/</loc><lastmod>${date}</lastmod><priority>1.0</priority></url>
</urlset>
EOF

    mkdir -p "$HTML_DIR/.well-known"
    cat > "$HTML_DIR/.well-known/security.txt" << EOF
Contact: mailto:security@${domain}
Expires: $(date -u -d '+1 year' +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
Preferred-Languages: en
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

  up | start    запустить
  down | stop   остановить
  restart       перезапустить
  reload        перечитать Caddyfile
  logs          логи Caddy
  access        access.log в realtime
  status | ps   статус контейнера
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
    mkdir -p "$HTML_DIR" "$LOG_DIR" "$DATA_DIR"

    BRAND=$(generate_brand "$DOMAIN")
    info "Бренд для $DOMAIN: $BRAND"

    info "Генерю шаблон: $TEMPLATE_NAME"
    case "$TEMPLATE" in
        1) build_saas "$BRAND" "$DOMAIN" ;;
        2) build_docs "$BRAND" "$DOMAIN" ;;
        3) build_status "$BRAND" ;;
        4) build_filecloud "$BRAND" ;;
        5) build_blog "$BRAND" ;;
        6) build_503 "$BRAND" ;;
    esac

    write_robots_sitemap "$DOMAIN"
    write_caddyfile "$DOMAIN" "$PORT"
    write_compose
    write_env "$DOMAIN" "$PORT"
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
    echo -e "  Бренд:     ${BRAND}"
    echo -e "  Порт:      ${PORT}"
    echo -e "  Каталог:   ${APP_DIR}"
    [[ "$ok_ssl" == "true" ]] && echo -e "  SSL:       ${GREEN}OK${NC}" || echo -e "  SSL:       ${YELLOW}проверь selfsteal logs${NC}"
    echo ""
    echo -e "${YELLOW}Reality inbound (Remnawave):${NC}"
    echo -e "  dest:        ${CYAN}127.0.0.1:${PORT}${NC}"
    echo -e "  serverNames: ${CYAN}[\"${DOMAIN}\"]${NC}"
    echo ""
    echo -e "${GRAY}Управление:${NC}"
    echo -e "  ${CYAN}selfsteal status${NC}  | ${CYAN}logs${NC} | ${CYAN}test${NC} | ${CYAN}restart${NC} | ${CYAN}uninstall${NC}"
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
    *) err "Неизвестная команда: $1" ;;
esac
