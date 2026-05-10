# 🛡 Selfsteal Caddy Installer

> Поднимает **fakesite на своём домене** (Caddy в Docker) для использования как `dest` в XRay Reality.
> Один скрипт, один домен, валидный TLS-сертификат от Let's Encrypt.

[![Bash](https://img.shields.io/badge/Bash-5.0+-4EAA25?logo=gnubash&logoColor=white)]()
[![Docker](https://img.shields.io/badge/Docker-required-2496ED?logo=docker&logoColor=white)]()
[![Caddy](https://img.shields.io/badge/Caddy-2.x-1F88C0?logo=caddy&logoColor=white)]()
[![License](https://img.shields.io/badge/license-MIT-green)]()

---

## 🎯 Что делает

- Ставит Docker и Docker Compose (если их нет)
- Поднимает **Caddy в контейнере** (`selfsteal-caddy`)
- Генерирует Caddyfile под твой домен
- Автоматически выпускает **сертификат Let's Encrypt** (HTTP-01)
- Кладёт минимальный HTML-fakesite в `/opt/selfsteal/html/`
- Слушает `:443` и `:80` на хосте через `network_mode: host`

После установки можно подставить адрес и SNI в XRay Reality инбаунд:

```json
"dest": "127.0.0.1:443",
"serverNames": ["cdn.example.com"]
```

---

## 🚀 Установка

### 1. Настрой DNS

Добавь A-запись в DNS-панели регистратора:

```
cdn.example.com   A   <IP сервера>   TTL 300
```

Проверь:

```bash
dig +short cdn.example.com
```

Должен вернуть IP сервера.

### 2. Запусти скрипт

```bash
bash <(curl -Ls https://raw.githubusercontent.com/USER/REPO/main/install.sh)
```

Скрипт спросит:
- Домен (например `cdn.example.com`)
- Email для Let's Encrypt (по умолчанию `admin@<домен>`)

Дальше всё автоматом.

---

## 🧪 Проверка

```bash
# Сертификат валидный?
echo | openssl s_client -connect 127.0.0.1:443 -servername cdn.example.com 2>/dev/null \
  | openssl x509 -noout -subject -dates
```

Ожидаемый вывод:

```
subject=CN = cdn.example.com
notBefore=...
notAfter=...
```

Снаружи:

```bash
curl -v https://cdn.example.com
```

Должен открыться HTML-fakesite.

---

## ⚙️ Управление

```bash
cd /opt/selfsteal

# Логи
docker logs -f selfsteal-caddy

# Рестарт
docker compose restart

# Стоп
docker compose down

# Старт
docker compose up -d
```

---

## 📁 Структура

```
/opt/selfsteal/
├── Caddyfile             # конфиг Caddy
├── docker-compose.yml    # docker-compose с network_mode: host
├── .env                  # домен и email
├── html/                 # fakesite (можешь заменить своим контентом)
├── data/                 # серты Caddy (Let's Encrypt account + cert)
└── logs/                 # access-логи
```

Чтобы заменить fakesite — просто положи свой `index.html` (и любые ассеты) в `/opt/selfsteal/html/`.

---

## 🔧 XRay Reality

После установки в инбаунде XRay укажи:

```json
"streamSettings": {
    "network": "tcp",
    "security": "reality",
    "realitySettings": {
        "dest": "127.0.0.1:443",
        "show": false,
        "xver": 0,
        "shortIds": ["..."],
        "privateKey": "...",
        "serverNames": ["cdn.example.com"]
    }
}
```

В клиенте/панели Remnawave используй тот же домен в поле SNI.

---

## ❓ Troubleshooting

**Серт не выпускается, в логах `challenge failed`**
Проверь что A-запись домена указывает именно на этот сервер и что порт 80 не заблокирован файрволом провайдера.

**Порт 80/443 занят**
Скрипт сам останавливает старый `selfsteal-caddy`, системный `caddy` и `nginx`. Если занят чем-то ещё — `ss -tlnp | grep -E ':(80|443) '` покажет процесс.

**Хочу поменять домен**
Отредактируй `/opt/selfsteal/Caddyfile`, замени старый домен на новый, перезапусти: `docker compose down && docker compose up -d`. Серт выпустится заново автоматически.

---

## 📜 Лицензия

MIT
