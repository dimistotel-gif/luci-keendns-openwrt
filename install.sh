cat > /tmp/install-keendns.sh << 'EOF'
#!/bin/sh

echo "Установка KeenDNS для OpenWrt..."

# 1. Установка Caddy
opkg update
opkg install caddy

# 2. Создание директорий
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/model/cbi
mkdir -p /usr/share/luci/menu.d

# 3. Luci контроллер
cat > /usr/lib/lua/luci/controller/keendns.lua << 'CONTROLLER_EOF'
module("luci.controller.keendns", package.seeall)
function index()
    entry({"admin", "services", "keendns"}, cbi("keendns"), _("Поддомены"), 60)
end
CONTROLLER_EOF

# 4. Интерфейс настройки
cat > /usr/lib/lua/luci/model/cbi/keendns.lua << 'CBI_EOF'
m = Map("keendns", "Управление поддоменами")
s = m:section(TypedSection, "rule", "Правила")
s.addremove = true
s.anonymous = false
s:option(Value, "subdomain", "Поддомен")
s:option(Value, "ip", "IP")
s:option(Value, "port", "Порт")
return m
CBI_EOF

# 5. Меню
cat > /usr/share/luci/menu.d/luci-keendns.json << 'MENU_EOF'
{"admin/services/keendns": {"title": "Поддомены", "order": 60, "action": {"type": "view", "path": "keendns"}}}
MENU_EOF

# 6. Конфиг
cat > /etc/config/keendns << 'CONFIG_EOF'
config rule 'ha'
    option subdomain 'ha'
    option ip '192.168.1.100'
    option port '8123'
CONFIG_EOF

# 7. Скрипт синхронизации
cat > /usr/bin/keendns-apply << 'SCRIPT_EOF'
#!/bin/sh
# Генерируем Caddyfile
echo "# KeenDNS" > /etc/caddy/Caddyfile
uci show keendns | grep rule | while read line; do
    name=$(echo $line | cut -d. -f2 | cut -d= -f1)
    subdomain=$(uci get keendns.$name.subdomain)
    ip=$(uci get keendns.$name.ip)
    port=$(uci get keendns.$name.port)
    echo "$subdomain.ваш_домен.duckdns.org { reverse_proxy http://$ip:$port }" >> /etc/caddy/Caddyfile
done
/etc/init.d/caddy restart
SCRIPT_EOF

chmod +x /usr/bin/keendns-apply

echo "Готово! Перезагрузи страницу Luci."
echo "Будет в: Сервисы → Поддомены"
EOF

chmod +x /tmp/install-keendns.sh
/tmp/install-keendns.sh
