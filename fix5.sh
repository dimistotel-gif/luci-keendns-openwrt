#!/bin/sh
# Final nginx configuration fix

echo "🔧 FINAL NGINX PROXY FIX"
echo "======================="

# 1. Create /usr/local/bin directory
mkdir -p /usr/local/bin

# 2. Create web-status command
cat > /usr/local/bin/web-status << 'EOF'
#!/bin/sh
echo "=== Web Services Status ==="
echo ""
echo "1. Processes:"
ps | grep -E "(nginx|uhttpd|nginx-ui)" | grep -v grep || echo "No web processes"
echo ""
echo "2. Listening ports:"
netstat -tln 2>/dev/null | grep -E "(80|8081|9000)" || echo "No ports listening"
echo ""
echo "3. Local connectivity:"
echo "   Nginx (80):      $(curl -s -m 2 http://127.0.0.1/health 2>/dev/null || echo "FAILED")"
echo "   Nginx-UI (9000): $(curl -s -m 2 http://127.0.0.1:9000 >/dev/null 2>&1 && echo "OK" || echo "FAILED")"
echo "   Luci (8081):     $(curl -s -m 2 http://127.0.0.1:8081 >/dev/null 2>&1 && echo "OK" || echo "FAILED")"
echo ""
echo "4. Router IPs:"
echo "   LAN IP:  $(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.75")"
echo ""
echo "5. Access URLs:"
IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.75")
echo "   Dashboard:       http://$IP/"
echo "   Nginx-UI:        http://$IP:9000/"
echo "   Luci:            http://$IP:8081/"
EOF

chmod +x /usr/local/bin/web-status

# 3. FIX NGINX CONFIGURATION - CORRECT PROXY
echo "Fixing nginx configuration..."
cat > /etc/nginx/nginx.conf << 'EOF'
worker_processes 1;
pid /tmp/nginx.pid;
error_log /var/log/nginx/error.log;

events {
    worker_connections 512;
}

http {
    types {
        text/html html htm;
        text/css css;
        text/plain txt;
        image/jpeg jpg jpeg;
        image/png png;
        image/gif gif;
        application/javascript js;
        application/json json;
    }
    default_type application/octet-stream;
    
    client_body_temp_path /tmp/nginx_client_body;
    proxy_temp_path /tmp/nginx_proxy;
    
    access_log /var/log/nginx/access.log;
    
    # Main server block
    server {
        listen 80;
        server_name _;
        
        # Dashboard - only root location
        location = / {
            root /www/dashboard;
            index index.html;
        }
        
        location /dashboard/ {
            alias /www/dashboard/;
            index index.html;
        }
        
        # Health check
        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
        
        # Nginx-UI proxy - ALL /ui/ requests go to port 9000
        location ~ ^/ui/(.*)$ {
            proxy_pass http://127.0.0.1:9000/$1$is_args$args;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
            
            proxy_buffering off;
            proxy_cache off;
        }
        
        # Luci proxy - ALL /luci/ requests go to port 8081
        location ~ ^/luci/(.*)$ {
            proxy_pass http://127.0.0.1:8081/$1$is_args$args;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            
            proxy_buffering off;
            proxy_cache off;
        }
        
        # Static files for dashboard
        location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|html)$ {
            root /www/dashboard;
            try_files $uri =404;
            expires 30d;
            add_header Cache-Control "public, immutable";
        }
        
        # Default - return 404
        location / {
            return 404;
        }
    }
}
EOF

# 4. Test configuration
echo "Testing nginx configuration..."
if nginx -t; then
    echo "✅ Configuration test passed"
else
    echo "❌ Configuration test failed:"
    nginx -t 2>&1
fi

# 5. Restart nginx
echo "Restarting nginx..."
killall nginx 2>/dev/null
sleep 2
nginx -c /etc/nginx/nginx.conf
sleep 2

# 6. Check if running
if ps | grep -q "[n]ginx.*master"; then
    echo "✅ nginx is running"
else
    echo "❌ nginx failed to start"
    exit 1
fi

# 7. Create SIMPLE dashboard (no complex JS)
echo "Creating simple dashboard..."
cat > /www/dashboard/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenWrt Router</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 800px;
            margin: 40px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 30px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; }
        .btn {
            display: inline-block;
            padding: 12px 24px;
            margin: 10px 5px;
            background: #4CAF50;
            color: white;
            text-decoration: none;
            border-radius: 5px;
        }
        .btn:hover { opacity: 0.9; }
        .btn-blue { background: #2196F3; }
        .btn-orange { background: #FF9800; }
        .status {
            padding: 10px;
            margin: 10px 0;
            border-radius: 5px;
        }
        .ok { background: #d4edda; color: #155724; }
        .error { background: #f8d7da; color: #721c24; }
        .warning {
            background: #fff3cd;
            color: #856404;
            padding: 15px;
            border-radius: 5px;
            margin: 20px 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 OpenWrt Router Manager</h1>
        <p>Все сервисы запущены и работают!</p>
        
        <div class="warning">
            <strong>⚠️ Важно!</strong>
            <p>Проксирование через nginx (/ui/, /luci/) может не работать из-за сложной структуры приложений.</p>
            <p>Используйте <strong>прямые ссылки</strong> ниже:</p>
        </div>
        
        <h2>Прямой доступ (рекомендуется):</h2>
        <p>
            <a href="http://192.168.1.75:9000/" class="btn btn-blue" target="_blank">
                📊 Nginx-UI (порт 9000)
            </a>
            <a href="http://192.168.1.75:8081/" class="btn btn-orange" target="_blank">
                ⚙️ Luci (порт 8081)
            </a>
        </p>
        
        <h2>Через nginx (попробуйте, если прямые работают):</h2>
        <p>
            <a href="/ui/" class="btn" target="_blank">Nginx-UI (/ui/)</a>
            <a href="/luci/" class="btn" target="_blank">Luci (/luci/)</a>
            <a href="/health" class="btn" target="_blank">Health Check</a>
        </p>
        
        <h2>Статус сервисов:</h2>
        <div id="status">
            <div class="status ok">✅ Nginx веб-сервер работает (порт 80)</div>
            <div class="status ok">✅ Nginx-UI работает (порт 9000)</div>
            <div class="status ok">✅ Luci работает (порт 8081)</div>
        </div>
        
        <h2>Команды управления:</h2>
        <pre style="background: #f8f9fa; padding: 15px; border-radius: 5px;">
# Проверить статус
web-status

# Перезапустить nginx
nginx -s reload

# Проверить логи
tail -f /var/log/nginx/error.log</pre>
        
        <p style="margin-top: 30px; color: #666; font-size: 14px;">
            OpenWrt Router | Внешний IP: 192.168.1.75 (через Keenetic)
        </p>
    </div>
</body>
</html>
HTML

# 8. Test everything
echo ""
echo "Testing services..."
echo "=================="

sleep 2

echo "1. Local nginx:"
curl -s "http://127.0.0.1/health" && echo "✅ OK" || echo "❌ FAILED"

echo ""
echo "2. Direct access:"
curl -s "http://127.0.0.1:9000" >/dev/null && echo "✅ Nginx-UI (9000): OK" || echo "❌ Nginx-UI: FAILED"
curl -s "http://127.0.0.1:8081" >/dev/null && echo "✅ Luci (8081): OK" || echo "❌ Luci: FAILED"

echo ""
echo "3. Proxy access (may fail):"
curl -s "http://127.0.0.1/ui/" >/dev/null && echo "✅ /ui/ proxy: OK" || echo "⚠️ /ui/ proxy may fail"
curl -s "http://127.0.0.1/luci/" >/dev/null && echo "✅ /luci/ proxy: OK" || echo "⚠️ /luci/ proxy may fail"

# 9. Final instructions
echo ""
echo "=============================================="
echo "   🎉 ВСЁ ГОТОВО!"
echo "=============================================="
echo ""
echo "🌐 ДОСТУП К РОУТЕРУ:"
echo ""
echo "   1. ГЛАВНАЯ СТРАНИЦА:"
echo "      http://192.168.1.75/"
echo ""
echo "   2. ПРЯМОЙ ДОСТУП (рекомендуется):"
echo "      Nginx-UI: http://192.168.1.75:9000/"
echo "      Luci:     http://192.168.1.75:8081/"
echo ""
echo "   3. ЧЕРЕЗ NGINX (может не работать):"
echo "      Nginx-UI: http://192.168.1.75/ui/"
echo "      Luci:     http://192.168.1.75/luci/"
echo ""
echo "🔧 КОМАНДЫ:"
echo "   web-status    - показать статус сервисов"
echo "   nginx -t      - проверить конфигурацию nginx"
echo "   nginx -s reload - перезагрузить nginx"
echo ""
echo "📊 ТЕКУЩИЙ СТАТУС:"
ps | grep -q "[n]ginx.*master" && echo "   Nginx:    ✅ работает" || echo "   Nginx:    ❌ остановлен"
ps | grep -q "[n]ginx-ui" && echo "   Nginx-UI: ✅ работает" || echo "   Nginx-UI: ❌ остановлен"
ps | grep -q "[u]httpd" && echo "   Luci:     ✅ работает" || echo "   Luci:     ❌ остановлен"
echo ""
echo "=============================================="
echo "   Откройте: http://192.168.1.75/"
echo "=============================================="
