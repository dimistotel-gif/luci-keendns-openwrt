#!/bin/sh
# Fix package manager (opkg) in Luci

echo "=============================================="
echo "   ВОССТАНОВЛЕНИЕ МЕНЕДЖЕРА ПАКЕТОВ LUCI"
echo "=============================================="

echo "1. Проверяем установленные пакеты Luci..."
opkg list-installed | grep luci-app-package-manager

echo "2. Переустанавливаем luci-app-opkg..."
opkg remove --force-removal-of-dependent-packages luci-app-package-manager luci-i18n-package-manager-ru 2>/dev/null
opkg update
opkg install luci-app-package-manager luci-i18n-package-manager-ru

echo "3. Проверяем файлы менеджера пакетов..."
ls -la /usr/lib/lua/luci/controller/opkg.lua 2>/dev/null || echo "Файл контроллера не найден"
ls -la /usr/lib/lua/luci/model/cbi/opkg.lua 2>/dev/null || echo "Файл модели не найден"

echo "4. Создаём недостающие файлы если нужно..."
mkdir -p /usr/lib/lua/luci/controller
mkdir -p /usr/lib/lua/luci/model/cbi

# Контроллер opkg
if [ ! -f "/usr/lib/lua/luci/controller/opkg.lua" ]; then
    echo "Создаём контроллер opkg..."
    cat > /usr/lib/lua/luci/controller/opkg.lua << 'EOF'
module("luci.controller.opkg", package.seeall)

function index()
    local page

    page = entry({"admin", "system", "packages"}, cbi("opkg"), _("Software"), 50)
    page.dependent = false
    page.leaf = true

    entry({"admin", "system", "packages", "action"}, call("action"))
end

function action()
    local os = require "os"
    local io = require "io"
    local sys = require "luci.sys"
    local http = require "luci.http"
    local util = require "luci.util"

    local cmd = http.formvalue("cmd")
    local pkg = http.formvalue("pkg")

    if cmd == "install" then
        os.execute("opkg install " .. pkg .. " >/tmp/opkg.log 2>&1")
    elseif cmd == "remove" then
        os.execute("opkg remove " .. pkg .. " >/tmp/opkg.log 2>&1")
    elseif cmd == "update" then
        os.execute("opkg update >/tmp/opkg.log 2>&1")
    end

    local log = ""
    local f = io.open("/tmp/opkg.log", "r")
    if f then
        log = f:read("*all")
        f:close()
    end

    http.prepare_content("application/json")
    http.write_json({log = log})
end
EOF
fi

# Модель CBI opkg
if [ ! -f "/usr/lib/lua/luci/model/cbi/opkg.lua" ]; then
    echo "Создаём модель opkg..."
    cat > /usr/lib/lua/luci/model/cbi/opkg.lua << 'EOF'
local ipkg = require "luci.model.ipkg"

m = Map("opkg", translate("Software"))
m:chain("luci")

s = m:section(TypedSection, "opkg", "")
s.anonymous = true

s:option(Value, "filter", translate("Filter"))

inst = s:option(DummyValue, "_installed", translate("Installed packages"))
inst.template = "admin_system/opkg"

upg = s:option(DummyValue, "_upgrades", translate("Upgrades"))
upg.template = "admin_system/opkg"

btn = s:option(Button, "_update", translate("Update lists"))
btn.inputtitle = translate("Update")
btn.inputstyle = "apply"
btn.forcewrite = true

function btn.write(self, section, value)
    os.execute("opkg update >/tmp/opkg.log 2>&1")
end

return m
EOF
fi

echo "5. Перезапускаем uHTTPd..."
/etc/init.d/uhttpd restart
sleep 2

echo "6. Очищаем кэш Luci..."
rm -rf /tmp/luci-*

echo ""
echo "=============================================="
echo "   ПРОВЕРКА"
echo "=============================================="

echo "1. Тест страницы менеджера пакетов..."
if curl -s "http://127.0.0.1/cgi-bin/luci/admin/system/packages" 2>/dev/null | grep -q "Software\|Пакеты"; then
    echo "✅ Менеджер пакетов доступен"
else
    echo "❌ Менеджер пакетов не доступен"
fi

echo ""
echo "2. Проверяем пакет luci-app-package-manager..."
opkg files luci-app-package-manager 2>/dev/null | head -5

echo ""
echo "3. Альтернативная установка (если не установлен)..."
if ! opkg list-installed | grep -q luci-app-package-manager; then
    echo "Устанавливаем luci-app-package-manager..."
    opkg install luci-app-package-manager
fi

echo ""
echo "=============================================="
echo "   ИНСТРУКЦИЯ"
echo "=============================================="
echo ""
echo "Если менеджер пакетов всё ещё не работает:"
echo ""
echo "1. Временно используйте командную строку:"
echo "   opkg update"
echo "   opkg list-installed"
echo "   opkg install <пакет>"
echo ""
echo "2. Или установите через SSH:"
echo "   scp package.ipk root@192.168.1.75:/tmp/"
echo "   opkg install /tmp/package.ipk"
echo ""
echo "3. Попробуйте альтернативный URL:"
echo "   http://192.168.1.75/cgi-bin/luci/admin/system/opkg"
echo ""
echo "=============================================="
echo "   Откройте: http://192.168.1.75/"
echo "   Затем: Система → Software"
echo "=============================================="
