#!/bin/sh
# KeenDNS for OpenWrt - Installer
# GitHub: https://github.com/tvoj-git/keendns-openwrt
# Usage: wget -O - https://raw.githubusercontent.com/tvoj-git/keendns-openwrt/main/install.sh | sh

set -e

# Configuration
VERSION="1.0.0"
DOMAIN="hleba.duckdns.org"
ROUTER_IP="192.168.100.1"
INSTALL_LOG="/tmp/keendns-install.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Functions
log() {
    echo -e "${GREEN}[*]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[!]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    exit 1
}

print_banner() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║      KeenDNS for OpenWrt v$VERSION       ║"
    echo "║      GitHub: tvoj-git/keendns-openwrt    ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
}

check_system() {
    log "Проверка системы..."
    
    # Check root
    [ "$(id -u)" -ne 0 ] && error "Требуются права root!"
    
    # Check OpenWrt
    [ ! -f "/etc/openwrt_release" ] && error "Это не OpenWrt!"
    
    # Check architecture
    ARCH=$(uname -m)
    log "Архитектура: $ARCH"
    
    # Check memory
    MEM_FREE=$(free | grep Mem | awk '{print $4}')
    [ "$MEM_FREE" -lt 50000 ] && warn "Мало свободной памяти: ${MEM_FREE}KB"
}

install_dependencies() {
    log "Установка зависимостей..."
    
    # Update packages
    if ! opkg update >> "$INSTALL_LOG" 2>&1; then
        error "Не удалось обновить пакеты"
    fi
    
    # Install nginx if not present
    if ! opkg list-installed | grep -q "^nginx"; then
        log "Установка nginx..."
        opkg install nginx-full nginx-mod-luci >> "$INSTALL_LOG" 2>&1 || {
            error "Ошибка установки nginx"
        }
    else
        log "nginx уже установлен"
    fi
    
    # Install luci if not present
    if ! opkg list-installed | grep -q "^luci"; then
        log "Установка Luci..."
        opkg install luci luci-base luci-mod-admin-full >> "$INSTALL_LOG" 2>&1 || {
            warn "Ошибка установки Luci (возможно уже установлен)"
        }
    fi
}

create_luci_module() {
    log "Создание модуля Luci..."
    
    # Create directories
    mkdir -p /usr/lib/lua/luci/controller/keendns
    mkdir -p /usr/lib/lua/luci/model/cbi/keendns
    mkdir -p /usr/share/luci/menu.d
    
    # Create controller
    cat > /usr/lib/lua/luci/controller/keendns/controller.lua << 'EOF'
module("luci.controller.keendns.controller", package.seeall)

function index()
    entry({"admin", "services", "keendns"}, cbi("keendns/manage"), _("Поддомены"), 60)
    entry({"admin", "services", "keendns", "add"}, call("add_subdomain")).leaf = true
    entry({"admin", "services", "keendns", "delete"}, call("delete_subdomain")).leaf = true
    entry({"admin", "services", "keendns", "status"}, call("status_page")).leaf = true
end

function add_subdomain()
    local http = require("luci.http")
    local subdomain = http.formvalue("subdomain")
    local ip = http.formvalue("ip")
    local port = http.formvalue("port")
    
    if subdomain and ip and port then
        local cmd = string.format('/usr/lib/keendns/add-subdomain "%s" "%s" "%s"', 
            subdomain, ip, port)
        os.execute(cmd)
    end
    
    http.redirect(luci.dispatcher.build_url("admin/services/keendns"))
end

function delete_subdomain()
    local http = require("luci.http")
    local subdomain = http.formvalue("subdomain")
    
    if subdomain then
        os.execute(string.format('/usr/lib/keendns/remove-subdomain "%s"', subdomain))
    end
    
    http.redirect(luci.dispatcher.build_url("admin/services/keendns"))
end

function status_page()
    local template = require("luci.template")
    local sys = require("luci.sys")
    
    local status = {
        nginx = sys.exec("ps | grep nginx | grep -v grep | wc -l") or "0",
        configs = sys.exec("ls -1 /etc/nginx/conf.d/*.conf 2>/dev/null | wc -l") or "0",
        domain = "hleba.duckdns.org"
    }
    
    template.render("keendns/status", {status = status})
end
EOF

    # Create CBI model
    cat > /usr/lib/lua/luci/model/cbi/keendns/manage.lua << 'EOF'
local sys = require("luci.sys")
local uci = require("luci.model.uci").cursor()

m = Map("keendns", "Управление поддоменами", 
    [[
    <strong>Аналог KeenDNS для OpenWrt</strong><br>
    Добавляйте поддомены и указывайте внутренний IP:PORT как в оригинальном Keenetic
    ]])

-- Section for adding new subdomain
s = m:section(SimpleSection, nil, "Добавить новый поддомен")

subdomain = s:option(Value, "new_subdomain", "Поддомен")
subdomain.placeholder = "ha"
subdomain.datatype = "hostname"
subdomain.rmempty = false

ip = s:option(Value, "new_ip", "Внутренний IP")
ip.placeholder = "192.168.100.100"
ip.datatype = "ip4addr"
ip.rmempty = false

port = s:option(Value, "new_port", "Порт")
port.placeholder = "8123"
port.datatype = "port"
port.rmempty = false

-- Add button
btn = s:option(Button, "_add", "")
btn.title = " "
btn.inputtitle = "➕ Добавить поддомен"
btn.inputstyle = "add"

function btn.write(self, section)
    local subdomain_val = subdomain:formvalue(section)
    local ip_val = ip:formvalue(section)
    local port_val = port:formvalue(section)
    
    if subdomain_val and ip_val and port_val then
        local cmd = string.format('/usr/lib/keendns/add-subdomain "%s" "%s" "%s"', 
            subdomain_val, ip_val, port_val)
        sys.call(cmd)
        
        -- Clear fields
        luci.http.redirect(luci.dispatcher.build_url("admin/services/keendns"))
    end
end

-- Current subdomains section
local current = m:section(Table, {}, "Текущие поддомены")

current.template = "cbi/tblsection"
current.anonymous = true

current:option(DummyValue, "subdomain", "Поддомен")
current:option(DummyValue, "target", "Внутренний адрес")
current:option(DummyValue, "status", "Статус")

function current.cfgsections(self)
    local sections = {}
    local handle = io.popen("grep -h 'server_name' /etc/nginx/conf.d/*.conf 2>/dev/null | awk '{print $2}' | cut -d. -f1")
    
    if handle then
        for line in handle:lines() do
            table.insert(sections, line)
        end
        handle:close()
    end
    
    return sections
end

function current.create(self, section)
    -- Do nothing
end

function current.parse(self, section)
    -- Do nothing
end

return m
EOF

    # Create status view
    mkdir -p /usr/lib/lua/luci/view/keendns
    cat > /usr/lib/lua/luci/view/keendns/status.htm << 'EOF'
<%+header%>
<div class="cbi-map">
    <h2 name="content">Статус KeenDNS</h2>
    
    <div class="cbi-section">
        <h3>Информация о системе</h3>
        <div class="cbi-value">
            <label class="cbi-value-title">Домен:</label>
            <div class="cbi-value-field">
                <strong><%=status.domain%></strong>
            </div>
        </div>
        <div class="cbi-value">
            <label class="cbi-value-title">NGINX процессов:</label>
            <div class="cbi-value-field">
                <%=status.nginx%>
            </div>
        </div>
        <div class="cbi-value">
            <label class="cbi-value-title">Настроено поддоменов:</label>
            <div class="cbi-value-field">
                <%=status.configs%>
            </div>
        </div>
    </div>
    
    <div class="cbi-section">
        <h3>Быстрые ссылки</h3>
        <div class="cbi-value">
            <div class="cbi-value-field">
                <a class="cbi-button cbi-button-apply" href="<%=url('admin/services/keendns')%>">Управление поддоменами</a>
                <a class="cbi-button" href="<%=url('admin/system/filebrowser')%>">Файловый менеджер</a>
                <a class="cbi-button" href="/">Главная страница</a>
            </div>
        </div>
    </div>
</div>
<%+footer%>
EOF

    # Create menu
    cat > /usr/share/luci/menu.d/luci-app-keendns.json << 'EOF'
{
    "admin/services/keendns": {
        "title": "Поддомены",
        "order": 60,
        "action": {
            "type": "view",
            "path": "keendns/manage"
        }
    }
}
EOF
}

create_nginx_config() {
    log "Настройка NGINX..."
    
    # Create config directory
    mkdir -p /etc/nginx/conf.d
    
    # Main nginx config
    cat > /etc/nginx/nginx.conf << 'EOF'
user nobody nogroup;
worker_processes auto;
error_log /tmp/nginx_error.log;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    sendfile on;
    keepalive_timeout 65;
    
    # Основной сервер - проксирует всё через nginx
    server {
        listen 80;
        server_name _;
        
        # Luci веб-интерфейс
        location / {
            proxy_pass http://127.0.0.1:80;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
        }
        
        # Статичные файлы KeenDNS
        location /keendns/ {
            alias /www/keendns/;
        }
    }
    
    # Поддомены (будут добавляться автоматически)
    include /etc/nginx/conf.d/*.conf;
}
EOF

    # Create empty keendns config
    echo "# KeenDNS поддомены" > /etc/nginx/conf.d/keendns.conf
    echo "# Создано: $(date)" >> /etc/nginx/conf.d/keendns.conf
    echo "" >> /etc/nginx/conf.d/keendns.conf
}

create_management_scripts() {
    log "Создание скриптов управления..."
    
    # Create keendns directory
    mkdir -p /usr/lib/keendns
    
    # Add subdomain script
    cat > /usr/lib/keendns/add-subdomain << 'EOF'
#!/bin/sh
# Добавление поддомена в KeenDNS

if [ $# -ne 3 ]; then
    echo "Использование: $0 <поддомен> <ip> <порт>"
    echo "Пример: $0 ha 192.168.100.100 8123"
    exit 1
fi

SUBDOMAIN="$1"
IP="$2"
PORT="$3"
DOMAIN="hleba.duckdns.org"
CONFIG_FILE="/etc/nginx/conf.d/keendns.conf"
TEMP_FILE="/tmp/keendns.tmp"

# Проверяем нет ли уже такого поддомена
if grep -q "server_name $SUBDOMAIN\\.$DOMAIN" "$CONFIG_FILE"; then
    echo "❌ Поддомен $SUBDOMAIN уже существует!"
    exit 1
fi

# Добавляем конфиг
echo "" >> "$CONFIG_FILE"
echo "# $SUBDOMAIN - добавлено $(date)" >> "$CONFIG_FILE"
echo "server {" >> "$CONFIG_FILE"
echo "    listen 80;" >> "$CONFIG_FILE"
echo "    server_name $SUBDOMAIN.$DOMAIN;" >> "$CONFIG_FILE"
echo "    " >> "$CONFIG_FILE"
echo "    location / {" >> "$CONFIG_FILE"
echo "        proxy_pass http://$IP:$PORT;" >> "$CONFIG_FILE"
echo "        proxy_set_header Host \$host;" >> "$CONFIG_FILE"
echo "        proxy_set_header X-Real-IP \$remote_addr;" >> "$CONFIG_FILE"
echo "        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;" >> "$CONFIG_FILE"
echo "    }" >> "$CONFIG_FILE"
echo "}" >> "$CONFIG_FILE"

# Проверяем конфиг
if nginx -t > /dev/null 2>&1; then
    # Перезагружаем nginx
    if /etc/init.d/nginx reload > /dev/null 2>&1; then
        echo "✅ Поддомен добавлен: $SUBDOMAIN.$DOMAIN → $IP:$PORT"
    else
        echo "⚠️  Поддомен добавлен, но не удалось перезагрузить nginx"
    fi
else
    # Откатываем изменения
    grep -v "server_name $SUBDOMAIN\\.$DOMAIN" "$CONFIG_FILE" > "$TEMP_FILE"
    mv "$TEMP_FILE" "$CONFIG_FILE"
    echo "❌ Ошибка в конфигурации nginx. Изменения отменены."
    exit 1
fi
EOF

    # Remove subdomain script
    cat > /usr/lib/keendns/remove-subdomain << 'EOF'
#!/bin/sh
# Удаление поддомена из KeenDNS

if [ $# -ne 1 ]; then
    echo "Использование: $0 <поддомен>"
    echo "Пример: $0 ha"
    exit 1
fi

SUBDOMAIN="$1"
DOMAIN="hleba.duckdns.org"
CONFIG_FILE="/etc/nginx/conf.d/keendns.conf"
TEMP_FILE="/tmp/keendns.tmp"

# Проверяем существует ли поддомен
if ! grep -q "server_name $SUBDOMAIN\\.$DOMAIN" "$CONFIG_FILE"; then
    echo "❌ Поддомен $SUBDOMAIN не найден!"
    exit 1
fi

# Удаляем блок конфига
awk -v subdomain="$SUBDOMAIN.$DOMAIN" '
BEGIN { skip = 0 }
/server_name/ && $0 ~ subdomain { skip = 1 }
skip && /^[[:space:]]*}/ { skip = 0; next }
!skip { print }
' "$CONFIG_FILE" > "$TEMP_FILE"

mv "$TEMP_FILE" "$CONFIG_FILE"

# Перезагружаем nginx
if /etc/init.d/nginx reload > /dev/null 2>&1; then
    echo "✅ Поддомен удалён: $SUBDOMAIN.$DOMAIN"
else
    echo "⚠️  Поддомен удалён, но не удалось перезагрузить nginx"
fi
EOF

    # List subdomains script
    cat > /usr/lib/keendns/list-subdomains << 'EOF'
#!/bin/sh
# Список поддоменов KeenDNS

echo "📋 Список поддоменов KeenDNS:"
echo ""

CONFIG_FILE="/etc/nginx/conf.d/keendns.conf"

if [ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]; then
    echo "   Нет настроенных поддоменов"
    exit 0
fi

awk '
/server_name/ {
    subdomain = $2
    gsub(/;$/, "", subdomain)
    gsub(/^[[:space:]]*server_name[[:space:]]+/, "", subdomain)
    gsub(/[[:space:]]*$/, "", subdomain)
}
/proxy_pass/ && subdomain {
    ip_port = $0
    gsub(/^[[:space:]]*proxy_pass[[:space:]]+http:\/\//, "", ip_port)
    gsub(/;[[:space:]]*$/, "", ip_port)
    printf "   %s → %s\n", subdomain, ip_port
    subdomain = ""
}
' "$CONFIG_FILE"
EOF

    # Make scripts executable
    chmod +x /usr/lib/keendns/add-subdomain
    chmod +x /usr/lib/keendns/remove-subdomain
    chmod +x /usr/lib/keendns/list-subdomains
    
    # Create symlinks for easy access
    ln -sf /usr/lib/keendns/add-subdomain /usr/bin/keendns-add
    ln -sf /usr/lib/keendns/remove-subdomain /usr/bin/keendns-remove
    ln -sf /usr/lib/keendns/list-subdomains /usr/bin/keendns-list
}

create_config_file() {
    log "Создание конфигурации..."
    
    cat > /etc/config/keendns << 'EOF'
config keendns 'global'
    option enabled '1'
    option version '1.0.0'
    option domain 'hleba.duckdns.org'
    option router_ip '192.168.100.1'

config example 'ha'
    option name 'Home Assistant'
    option subdomain 'ha'
    option ip '192.168.100.100'
    option port '8123'
    option enabled '1'
    option description 'Пример: Home Assistant'
EOF
}

start_services() {
    log "Запуск сервисов..."
    
    # Stop nginx if running
    /etc/init.d/nginx stop > /dev/null 2>&1
    
    # Start nginx
    if /etc/init.d/nginx start > /dev/null 2>&1; then
        /etc/init.d/nginx enable
        log "NGINX запущен и добавлен в автозагрузку"
    else
        error "Не удалось запустить NGINX"
    fi
    
    # Clear Luci cache
    rm -rf /tmp/luci-* /tmp/uci-*
    
    # Restart uhttpd
    if /etc/init.d/uhttpd restart > /dev/null 2>&1; then
        log "Luci перезапущен"
    else
        warn "Не удалось перезапустить Luci"
    fi
}

show_summary() {
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║                УСТАНОВКА ЗАВЕРШЕНА!                      ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "🌐 Доступ к управлению:"
    echo "   • Luci: http://$ROUTER_IP"
    echo "   • Меню: Сервисы → Поддомены"
    echo ""
    echo "🛠️  Команды для терминала:"
    echo "   • keendns-add <поддомен> <ip> <порт>"
    echo "   • keendns-remove <поддомен>"
    echo "   • keendns-list"
    echo ""
    echo "📝 Примеры:"
    echo "   • keendns-add ha 192.168.100.100 8123"
    echo "   • keendns-add nc 192.168.100.101 8080"
    echo ""
    echo "🔧 Файлы конфигурации:"
    echo "   • /etc/nginx/conf.d/keendns.conf"
    echo "   • /etc/config/keendns"
    echo ""
    echo "📊 Проверка работы:"
    echo "   • curl -H 'Host: ha.hleba.duckdns.org' http://localhost"
    echo ""
    echo "⚠️  Если Luci недоступен, перезагрузите роутер: reboot"
    echo ""
    echo "Логи установки: $INSTALL_LOG"
    echo ""
}

# Main execution
main() {
    print_banner
    check_system
    install_dependencies
    create_luci_module
    create_nginx_config
    create_management_scripts
    create_config_file
    start_services
    show_summary
}

# Run main
main "$@"
