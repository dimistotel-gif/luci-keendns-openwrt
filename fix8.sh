#!/bin/sh
# COMPLETE RESTORE TO ORIGINAL STATE

echo "🔥 ПОЛНОЕ ВОССТАНОВЛЕНИЕ ОРИГИНАЛЬНОГО СОСТОЯНИЯ"
echo "=============================================="

# 1. СТОП ВСЕГО
echo "1. Останавливаем всё..."
/etc/init.d/nginx stop 2>/dev/null
/etc/init.d/nginx-ui stop 2>/dev/null
/etc/init.d/uhttpd stop 2>/dev/null
killall nginx nginx-ui uhttpd 2>/dev/null
sleep 2

# 2. УДАЛЯЕМ ВСЁ ЧТО Я УСТАНОВИЛ
echo "2. Удаляем ВСЁ установленное..."
opkg remove --force-removal-of-dependent-packages nginx nginx-* luci-app-package-manager 2>/dev/null
rm -rf /opt/nginx-ui /etc/nginx-ui /www/dashboard /www/keendns /www/nginx-* 2>/dev/null

# 3. ВОССТАНАВЛИВАЕМ ОРИГИНАЛЬНЫЙ LUCI И UHTTPD
echo "3. Восстанавливаем оригинальный Luci..."
opkg remove --force-removal-of-dependent-packages luci-* uhttpd* 2>/dev/null
rm -rf /etc/config/uhttpd /etc/config/luci* /tmp/luci* /var/lib/rpcd/luci*

# 4. СТАВИМ ЧИСТЫЙ LUCI И UHTTPD
echo "4. Устанавливаем чистый Luci и uHTTPd..."
opkg update
opkg install luci-base luci-mod-admin-full luci-theme-bootstrap uhttpd uhttpd-mod-ubus rpcd-mod-luci

# 5. СОЗДАЁМ ОРИГИНАЛЬНЫЙ КОНФИГ UHTTPD
echo "5. Создаём оригинальный конфиг uHTTPd..."
cat > /etc/config/uhttpd << 'EOF'
config uhttpd 'main'
    option listen_http '0.0.0.0:80'
    option home '/www'
    option rfc1918_filter '1'
    option max_requests '3'
    option max_connections '100'
    option network_timeout '60'
    option http_keepalive '20'
    option tcp_keepalive '1'
    option ubus_prefix '/ubus'

config uhttpd 'ubus'
    option socket '/var/run/ubus.sock'
EOF

# 6. ВОССТАНАВЛИВАЕМ СТАНДАРТНЫЕ ПАКЕТЫ LUCI
echo "6. Восстанавливаем стандартные пакеты Luci..."
opkg install luci-app-firewall luci-mod-network luci-mod-status luci-mod-system luci-proto-ipv6 luci-proto-ppp

# 7. СТАВИМ LUA ДЛЯ LUCI (ЭТО БЫЛО В ОРИГИНАЛЕ!)
echo "7. Устанавливаем Lua для Luci..."
opkg install liblua lua luci-lua-runtime

# 8. ПЕРЕУСТАНАВЛИВАЕМ luci-app-package-manager ЕСЛИ БЫЛ
echo "8. Восстанавливаем менеджер пакетов..."
opkg install luci-app-package-manager luci-i18n-package-manager-ru 2>/dev/null || echo "Пакет недоступен, пропускаем"

# 9. ВОССТАНАВЛИВАЕМ PODKOP ЕСЛИ БЫЛ
echo "9. Восстанавливаем podkop..."
if opkg list-installed | grep -q podkop; then
    echo "Podkop уже установлен"
else
    # Проверяем был ли podkop
    if [ -f "/usr/bin/podkop" ]; then
        echo "Восстанавливаем Luci для podkop..."
        opkg install luci-app-podkop luci-i18n-podkop-ru 2>/dev/null || echo "Пакет podkop недоступен"
    fi
fi

# 10. ЧИСТИМ ВСЕ МОИ ИЗМЕНЕНИЯ
echo "10. Чистим все мои изменения..."
rm -f /usr/bin/web-status /usr/bin/restart-web /usr/local/bin/start-web 2>/dev/null
rm -f /usr/lib/lua/luci/controller/nginx-*.lua 2>/dev/null
rm -f /usr/lib/lua/luci/controller/keendns.lua 2>/dev/null
rm -f /usr/share/luci/menu.d/luci-app-*.json 2>/dev/null
rm -rf /usr/lib/lua/luci/view/nginx-* 2>/dev/null
rm -rf /usr/lib/lua/luci/view/keendns 2>/dev/null

# 11. ВОССТАНАВЛИВАЕМ ОРИГИНАЛЬНЫЙ /www
echo "11. Восстанавливаем оригинальную структуру /www..."
rm -rf /www/* 2>/dev/null
mkdir -p /www /www/cgi-bin
ln -sf /usr/lib/lua/luci/sgi/uhttpd.lua /www/cgi-bin/luci 2>/dev/null || true

# 12. ЗАПУСКАЕМ UHTTPD
echo "12. Запускаем uHTTPd..."
/etc/init.d/uhttpd enable
/etc/init.d/uhttpd start
sleep 3

# 13. ПЕРЕЗАПУСКАЕМ RPCD
echo "13. Перезапускаем rpcd..."
/etc/init.d/rpcd restart
sleep 2

# 14. ФИНАЛЬНАЯ ПРОВЕРКА
echo ""
echo "=============================================="
echo "   🔥 ФИНАЛЬНАЯ ПРОВЕРКА"
echo "=============================================="

echo "1. Процессы:"
ps | grep -E "(uhttpd|rpcd)" | grep -v grep || echo "⚠️ Процессы не найдены"

echo ""
echo "2. Порт 80:"
netstat -tln 2>/dev/null | grep :80 || echo "⚠️ Порт 80 не слушается"

echo ""
echo "3. Lua установлен:"
which lua && lua -v 2>/dev/null || echo "⚠️ Lua не найден"

echo ""
echo "4. Luci файлы:"
ls -la /www/cgi-bin/luci 2>/dev/null || echo "⚠️ Luci CGI не найден"

echo ""
echo "5. Тест Luci локально:"
if curl -s http://127.0.0.1/cgi-bin/luci 2>/dev/null | grep -q "OpenWrt\|Luci"; then
    echo "✅ Luci работает локально"
else
    echo "❌ Luci не отвечает"
fi

IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.75")

echo ""
echo "=============================================="
echo "   🎉 ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО!"
echo "=============================================="
echo ""
echo "🌐 ОТКРОЙТЕ В БРАУЗЕРЕ:"
echo "   http://${IP}/"
echo ""
echo "🔧 ЕСЛИ ЧТО-ТО НЕ ТАК - ЗАПУСТИТЕ ЭТИ КОМАНДЫ:"
echo ""
echo "   # Полная переустановка Luci"
echo "   opkg remove --force-removal-of-dependent-packages luci-* uhttpd*"
echo "   opkg install luci uhttpd"
echo "   reboot"
echo ""
echo "   # Или полный сброс"
echo "   firstboot -y && reboot"
echo ""
echo "=============================================="
