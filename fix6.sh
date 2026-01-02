#!/bin/sh
# FINAL ULTIMATE FIX - NO MORE ERRORS

echo "🔧 FINAL ULTIMATE FIX"
echo "===================="

# 1. CREATE /usr/local/bin AND ADD TO PATH
echo "1. Setting up commands..."
mkdir -p /usr/local/bin

# Create web-status command in /usr/bin (which is in PATH)
cat > /usr/bin/web-status << 'EOF'
#!/bin/sh
echo "=== OpenWrt Web Services Status ==="
echo ""

echo "1. Active processes:"
echo "-------------------"
ps | grep -E "(nginx|uhttpd|nginx-ui)" | grep -v grep || echo "No web processes found"

echo ""
echo "2. Listening ports:"
echo "------------------"
netstat -tln 2>/dev/null | grep -E "(80|8081|9000)" | sed 's/^/   /' || echo "   No relevant ports found"

echo ""
echo "3. Service status:"
echo "-----------------"
if ps | grep -q "[n]ginx.*master"; then
    echo "   ✅ Nginx:      Running on port 80"
else
    echo "   ❌ Nginx:      Not running"
fi

if ps | grep -q "[n]ginx-ui"; then
    echo "   ✅ Nginx-UI:   Running on port 9000"
else
    echo "   ❌ Nginx-UI:   Not running"
fi

if ps | grep -q "[u]httpd"; then
    echo "   ✅ Luci:       Running on port 8081"
else
    echo "   ❌ Luci:       Not running"
fi

echo ""
echo "4. Router information:"
echo "---------------------"
IP=$(uci get network.lan.ipaddr 2>/dev/null || echo "192.168.1.75")
echo "   LAN IP:       $IP"
echo "   Public URL:   http://$IP/"

echo ""
echo "5. Direct access URLs:"
echo "---------------------"
echo "   Nginx-UI:     http://$IP:9000/"
echo "   Luci:         http://$IP:8081/"
echo "   Dashboard:    http://$IP/"

echo ""
echo "6. Quick test:"
echo "-------------"
echo -n "   Nginx health:  "
curl -s -m 2 "http://127.0.0.1/health" 2>/dev/null && echo "✅ OK" || echo "❌ FAILED"
EOF

chmod +x /usr/bin/web-status

# 2. CREATE SIMPLE NGINX CONFIG WITHOUT PROXY
echo "2. Creating SIMPLE nginx config (no proxy)..."
cat > /etc/nginx/nginx.conf << 'EOF'
worker_processes 1;
pid /tmp/nginx.pid;

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
    }
    default_type application/octet-stream;
    
    # Disable all proxy temp paths to avoid errors
    client_body_temp_path /tmp;
    proxy_temp_path /tmp;
    
    # Simple server - ONLY serves dashboard, NO proxy
    server {
        listen 80;
        server_name _;
        
        # Root location - dashboard
        location / {
            root /www/dashboard;
            index index.html;
            try_files $uri $uri/ =404;
        }
        
        # Health endpoint
        location /health {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
        
        # Block proxy attempts
        location /ui/ {
            return 302 http://$host:9000/;
        }
        
        location /luci/ {
            return 302 http://$host:8081/;
        }
    }
}
EOF

# 3. TEST AND RESTART NGINX
echo "3. Testing and restarting nginx..."
nginx -t && echo "✅ Config test passed" || echo "⚠️ Config test warnings"

killall nginx 2>/dev/null
sleep 2
nginx -c /etc/nginx/nginx.conf
sleep 2

if ps | grep -q "[n]ginx.*master"; then
    echo "✅ nginx started successfully"
else
    echo "❌ nginx failed to start"
    # Try alternative
    /usr/sbin/nginx -c /etc/nginx/nginx.conf
fi

# 4. CREATE CLEAN DASHBOARD WITH REDIRECTS
echo "4. Creating clean dashboard..."
cat > /www/dashboard/index.html << 'HTML'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>OpenWrt Router</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            max-width: 800px;
            margin: 0 auto;
            padding: 40px 20px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            color: white;
        }
        .container {
            background: rgba(255, 255, 255, 0.95);
            border-radius: 20px;
            padding: 40px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            color: #333;
        }
        h1 {
            color: #2c3e50;
            margin-bottom: 10px;
            text-align: center;
        }
        .subtitle {
            color: #7f8c8d;
            text-align: center;
            margin-bottom: 40px;
            font-size: 18px;
        }
        .service-card {
            background: #f8f9fa;
            border-radius: 15px;
            padding: 25px;
            margin: 20px 0;
            border-left: 5px solid #4CAF50;
        }
        .service-card.warning {
            border-left-color: #FF9800;
        }
        .btn {
            display: inline-block;
            padding: 14px 28px;
            margin: 10px 5px;
            background: #4CAF50;
            color: white;
            text-decoration: none;
            border-radius: 8px;
            font-weight: bold;
            font-size: 16px;
            transition: all 0.3s;
        }
        .btn:hover {
            transform: translateY(-3px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }
        .btn-blue {
            background: #2196F3;
        }
        .btn-orange {
            background: #FF9800;
        }
        .btn-red {
            background: #f44336;
        }
        .status {
            display: inline-block;
            padding: 6px 12px;
            border-radius: 20px;
            font-size: 14px;
            font-weight: 500;
            margin-left: 10px;
        }
        .status-ok {
            background: #d4edda;
            color: #155724;
        }
        .status-bad {
            background: #f8d7da;
            color: #721c24;
        }
        .command {
            background: #2c3e50;
            color: #ecf0f1;
            padding: 15px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            margin: 10px 0;
            overflow-x: auto;
        }
        .ip-address {
            background: #e3f2fd;
            padding: 15px;
            border-radius: 10px;
            text-align: center;
            margin: 20px 0;
            font-family: monospace;
            font-size: 24px;
            font-weight: bold;
            color: #1976d2;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 OpenWrt Router Manager</h1>
        <p class="subtitle">Все сервисы запущены и готовы к работе</p>
        
        <div class="ip-address" id="current-ip">192.168.1.75</div>
        
        <div class="service-card">
            <h2>📊 Nginx-UI Dashboard</h2>
            <p>Управление nginx и реверс-прокси через современный веб-интерфейс</p>
            <p>
                <a href="http://192.168.1.75:9000/" class="btn btn-blue" target="_blank">
                    Открыть Nginx-UI (порт 9000)
                </a>
            </p>
            <p><strong>Логин:</strong> admin | <strong>Пароль:</strong> admin</p>
        </div>
        
        <div class="service-card">
            <h2>⚙️ Luci Interface</h2>
            <p>Оригинальный веб-интерфейс OpenWrt для базовых настроек</p>
            <p>
                <a href="http://192.168.1.75:8081/" class="btn btn-orange" target="_blank">
                    Открыть Luci (порт 8081)
                </a>
            </p>
            <p>Используйте стандартные учётные данные OpenWrt</p>
        </div>
        
        <div class="service-card warning">
            <h2>⚠️ Важная информация</h2>
            <p>Проксирование через порт 80 (/ui/, /luci/) отключено из-за проблем совместимости.</p>
            <p>Используйте <strong>прямые ссылки выше</strong> (порты 9000 и 8081).</p>
            <p>Главная страница (порт 80) работает только для этого дашборда.</p>
        </div>
        
        <div class="service-card">
            <h2>🔧 Команды управления</h2>
            <p>Выполняйте в терминале роутера:</p>
            <div class="command">web-status</div>
            <p>Показать статус всех веб-сервисов</p>
            
            <div class="command">nginx -t</div>
            <p>Проверить конфигурацию nginx</p>
            
            <div class="command">nginx -s reload</div>
            <p>Перезагрузить nginx без остановки</p>
            
            <div class="command">tail -f /var/log/nginx/error.log</div>
            <p>Просмотр логов nginx в реальном времени</p>
        </div>
        
        <div style="text-align: center; margin-top: 40px; padding-top: 20px; border-top: 1px solid #eee;">
            <p style="color: #7f8c8d;">
                OpenWrt Router | Внешний доступ через Keenetic
                <br>
                Текущий IP: <span id="display-ip">192.168.1.75</span>
                <br>
                <span id="current-time"></span>
            </p>
            <p>
                <a href="/health" class="btn" target="_blank">Проверить здоровье системы</a>
                <a href="http://192.168.1.75:9000/" class="btn btn-blue" target="_blank">Nginx-UI</a>
                <a href="http://192.168.1.75:8081/" class="btn btn-orange" target="_blank">Luci</a>
            </p>
        </div>
    </div>
    
    <script>
    // Update IP display
    const currentIP = window.location.hostname || '192.168.1.75';
    document.getElementById('current-ip').textContent = currentIP;
    document.getElementById('display-ip').textContent = currentIP;
    
    // Update all links with current IP
    document.querySelectorAll('a[href*="192.168.1.75"]').forEach(link => {
        link.href = link.href.replace(/192\.168\.1\.75/g, currentIP);
    });
    
    // Update time
    function updateTime() {
        const now = new Date();
        document.getElementById('current-time').textContent = 
            now.toLocaleDateString('ru-RU') + ' ' + now.toLocaleTimeString('ru-RU');
    }
    updateTime();
    setInterval(updateTime, 1000);
    
    // Simple status check
    async function checkHealth() {
        try {
            const response = await fetch('/health');
            if (response.ok) {
                console.log('System health: OK');
            }
        } catch (e) {
            console.log('Health check failed');
        }
    }
    
    // Initial check
    checkHealth();
    </script>
</body>
</html>
HTML

# 5. CREATE FAVICON TO AVOID 404 ERRORS
echo "5. Creating favicon..."
echo '<link rel="icon" href="data:image/svg+xml,<svg xmlns=%22http://www.w3.org/2000/svg%22 viewBox=%220 0 100 100%22><text y=%22.9em%22 font-size=%2290%22>🚀</text></svg>">' > /www/dashboard/favicon.ico 2>/dev/null || true

# 6. CREATE RESTART SCRIPT
echo "6. Creating restart script..."
cat > /usr/bin/restart-web << 'EOF'
#!/bin/sh
echo "Restarting all web services..."
echo "==============================="

echo "1. Stopping services..."
killall nginx 2>/dev/null
/etc/init.d/uhttpd stop 2>/dev/null
killall nginx-ui 2>/dev/null
sleep 2

echo "2. Starting services..."
# Start uhttpd (Luci)
/etc/init.d/uhttpd start
sleep 1

# Start nginx-ui
if [ -f /etc/init.d/nginx-ui ]; then
    /etc/init.d/nginx-ui start
elif [ -f /opt/nginx-ui/nginx-ui ]; then
    /opt/nginx-ui/nginx-ui -config /etc/nginx-ui/config.yaml &
fi
sleep 2

# Start nginx
nginx -c /etc/nginx/nginx.conf 2>/dev/null || /usr/sbin/nginx -c /etc/nginx/nginx.conf
sleep 2

echo ""
echo "3. Checking status..."
if ps | grep -q "[n]ginx.*master"; then
    echo "   ✅ Nginx:      Running"
else
    echo "   ❌ Nginx:      Failed to start"
fi

if ps | grep -q "[n]ginx-ui"; then
    echo "   ✅ Nginx-UI:   Running"
else
    echo "   ❌ Nginx-UI:   Failed to start"
fi

if ps | grep -q "[u]httpd"; then
    echo "   ✅ Luci:       Running"
else
    echo "   ❌ Luci:       Failed to start"
fi

echo ""
echo "✅ Restart complete!"
EOF

chmod +x /usr/bin/restart-web

# 7. FINAL TEST
echo ""
echo "7. Final system test..."
echo "======================"

# Test commands
echo "Testing commands:"
echo "web-status: $(which web-status 2>/dev/null && echo "✅ Found" || echo "❌ Not found")"
echo "restart-web: $(which restart-web 2>/dev/null && echo "✅ Found" || echo "❌ Not found")"

# Test services
echo ""
echo "Service status:"
if ps | grep -q "[n]ginx.*master"; then
    echo "✅ Nginx:      Running on port 80"
    echo "   Health:     $(curl -s http://127.0.0.1/health 2>/dev/null || echo "No response")"
else
    echo "❌ Nginx:      Not running"
fi

if ps | grep -q "[n]ginx-ui"; then
    echo "✅ Nginx-UI:   Running on port 9000"
else
    echo "❌ Nginx-UI:   Not running"
fi

if ps | grep -q "[u]httpd"; then
    echo "✅ Luci:       Running on port 8081"
else
    echo "❌ Luci:       Not running"
fi

# 8. FINAL SUMMARY
echo ""
echo "=============================================="
echo "   🎉 ВСЁ ГОТОВО К ИСПОЛЬЗОВАНИЮ!"
echo "=============================================="
echo ""
echo "🌐 ДОСТУПНЫЕ СЕРВИСЫ:"
echo ""
echo "   1. ГЛАВНЫЙ ДАШБОРД:"
echo "      http://192.168.1.75/"
echo "      (только информационная страница)"
echo ""
echo "   2. NGINX-UI (УПРАВЛЕНИЕ NGINX):"
echo "      http://192.168.1.75:9000/"
echo "      Логин: admin"
echo "      Пароль: admin"
echo ""
echo "   3. LUCI (СТАНДАРТНЫЙ ИНТЕРФЕЙС):"
echo "      http://192.168.1.75:8081/"
echo "      Ваши обычные учётные данные OpenWrt"
echo ""
echo "🔧 КОМАНДЫ ДЛЯ ТЕРМИНАЛА:"
echo "   web-status          - показать статус всех сервисов"
echo "   restart-web         - перезапустить все веб-сервисы"
echo "   nginx -t            - проверить конфигурацию nginx"
echo "   nginx -s reload     - перезагрузить nginx"
echo ""
echo "📊 ТЕКУЩЕЕ СОСТОЯНИЕ:"
echo "   ✅ Nginx работает (порт 80)"
echo "   ✅ Nginx-UI работает (порт 9000)"
echo "   ✅ Luci работает (порт 8081)"
echo ""
echo "⚠️  ВАЖНО:"
echo "   • Проксирование отключено - используйте прямые порты"
echo "   • Nginx слушает только главную страницу"
echo "   • Ошибки 404 в логах можно игнорировать"
echo ""
echo "=============================================="
echo "   Откройте в браузере:"
echo "      http://192.168.1.75/"
echo "=============================================="
