#!/bin/sh
# COMPLETE UNINSTALL - RETURN TO STOCK OPENWRT

echo "=============================================="
echo "   ПОЛНОЕ УДАЛЕНИЕ ВСЕХ ИЗМЕНЕНИЙ"
echo "=============================================="

echo "1. Останавливаем все сервисы..."
/etc/init.d/nginx stop 2>/dev/null
/etc/init.d/nginx-ui stop 2>/dev/null
killall nginx nginx-ui 2>/dev/null

echo "2. Удаляем nginx и все связанные пакеты..."
opkg remove --force-removal-of-dependent-packages nginx nginx-* 2>/dev/null

echo "3. Удаляем nginx-ui..."
rm -rf /opt/nginx-ui
rm -rf /etc/nginx-ui
rm -f /etc/init.d/nginx-ui

echo "4. Восстанавливаем оригинальный uHTTPd конфиг..."
if [ -f /etc/config/uhttpd.backup.original ]; then
    cp /etc/config/uhttpd.backup.original /etc/config/uhttpd
elif [ -f /etc/config/uhttpd.original.backup ]; then
    cp /etc/config/uhttpd.original.backup /etc/config/uhttpd
else
    # Создаем чистый конфиг uHTTPd
    cat > /etc/config/uhttpd << 'EOF'
config uhttpd 'main'
    option listen_http '0.0.0.0:80'
    option home '/www'
    option rfc1918_filter '1'
EOF
fi

echo "5. Удаляем все созданные файлы..."
rm -rf /www/nginx-*
rm -rf /www/dashboard
rm -rf /www/cgi-bin/api
rm -f /www/cgi-bin/nginx-*
rm -f /www/keendns
rm -f /www/nginx-admin

echo "6. Удаляем Luci меню..."
rm -f /usr/lib/lua/luci/controller/keendns.lua 2>/dev/null
rm -f /usr/lib/lua/luci/controller/nginx-*.lua 2>/dev/null

echo "7. Удаляем созданные команды..."
rm -f /usr/bin/web-status 2>/dev/null
rm -f /usr/bin/restart-web 2>/dev/null
rm -f /usr/local/bin/start-web 2>/dev/null
rm -f /usr/local/bin/web-status 2>/dev/null

echo "8. Удаляем конфиги nginx..."
rm -rf /etc/nginx
rm -rf /var/lib/nginx
rm -rf /var/log/nginx

echo "9. Очищаем временные файлы..."
rm -rf /tmp/nginx_*
rm -rf /tmp/nginx-*

echo "10. Перезапускаем uHTTPd..."
/etc/init.d/uhttpd restart
sleep 3

echo ""
echo "=============================================="
echo "   ✅ ВОССТАНОВЛЕНИЕ ЗАВЕРШЕНО!"
echo "=============================================="
echo ""
echo "📊 ТЕКУЩИЙ СТАТУС:"
echo "   uHTTPd (Luci):  $(ps | grep -q '[u]httpd' && echo '✅ Работает' || echo '❌ Остановлен')"
echo "   Nginx:          $(ps | grep -q '[n]ginx' && echo '⚠️  Ещё работает' || echo '✅ Удалён')"
echo "   Nginx-UI:       $(ps | grep -q '[n]ginx-ui' && echo '⚠️  Ещё работает' || echo '✅ Удалён')"
echo ""
echo "🌐 ДОСТУП К СТОКОВОМУ ИНТЕРФЕЙСУ:"
IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.1")
echo "   http://${IP}/"
echo ""
echo "🔧 ЕСЛИ ЧТО-ТО НЕ ТАК:"
echo "   1. Перезагрузите роутер: reboot"
echo "   2. Или выполните сброс: firstboot -y && reboot"
echo ""
echo "=============================================="
echo "   Откройте: http://${IP}/"
echo "=============================================="
